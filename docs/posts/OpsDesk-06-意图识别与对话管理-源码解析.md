# 第 06 章：意图识别与对话管理（源码解析）

**日期**：2026-09-01
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 06 章：意图识别与对话管理（项目落地笔记）.md`
> 本解析逐段走读意图分类、指代消解、工单号提取与中断-恢复。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/core/intent.py` | 意图分类：结构化输出 + 兜底 |
| `app/core/coref.py` | 指代消解：半截话补全 + 兜底原句 |
| `app/graph/nodes.py` | 节点实现：历史构造、工单号正则、fetch_ticket 中断 |
| `app/api/actions.py` | 中断续跑 API（resume / 建单 / 确认） |

## intent.py 逐段走读

### 意图集合与结构化输出

```python
INTENTS = ("报修", "查工单", "故障咨询", "巡检", "合同费用", "备件咨询", "投诉", "闲聊", "其他")

class _Intent(BaseModel):
    intent: Literal["报修", "查工单", "故障咨询", "巡检", "合同费用", "备件咨询", "投诉", "闲聊", "其他"] = Field(
        description="九类意图之一")
    confidence: float = Field(default=0.5, ge=0.0, le=1.0, description="判断把握 0-1")
```

- `Literal` 把输出限定死在 9 个值——模型没有自由发挥空间
- `confidence` 模型自评把握度（0-1），下游可做置信度门控
- 走 `llm.structured`（with_structured_output）：一次调用直接吐出符合 Pydantic 结构的 JSON

### classify：异常全兜底

```python
async def classify(query: str, history: str = "") -> dict:
    model = llm.structured(_Intent, model=settings.intent_model or None)
    try:
        r: _Intent = await (INTENT_CLASSIFY_PROMPT | model).ainvoke(
            {"query": query, "history": history or "(无)"})
    except Exception:
        return {"intent": "其他", "confidence": 0.0}
    intent = r.intent if r.intent in INTENTS else "其他"
    return {"intent": intent, "confidence": float(r.confidence)}
```

- **模型抽风/上游超时 → 归"其他"**（最保守兜底，替换 ch05 的回退闲聊）——意图分错最多走错出口，流程兜底能接住；让异常扩散才是灾难
- **越界输出再校验**：`r.intent if r.intent in INTENTS else "其他"`——结构化输出也可能返回不在枚举里的值（模型不老实），二次校验
- **扁平字段避 glm 嵌套 502**：意图模型早期用嵌套结构，某上游对深层嵌套 JSON 响应格式不稳定直接 502，字段拍平后消失
- **`settings.intent_model` 可单独指定**（空则回落 chat_model）——意图是地基，值得单独选模型求准

## coref.py 逐段走读

```python
async def resolve(query: str, history: str = "") -> str:
    try:
        model = get_chat_model()
        r = await (COREF_REWRITE_PROMPT | model).ainvoke(
            {"query": query, "history": history or "(无)"})
        text = (r.content if isinstance(r.content, str) else "").strip()
    except Exception:
        return query
    return text or query
```

- **结合历史把半截话补成完整问句**（"它为啥总是过载报警" → "VFD-3005 变频器为啥总是过载报警"）
- **失败兜底返回原句**：消解是增强不是依赖——挂了就原样往下走，不阻断链路
- 消解后的 `resolved_query` 是下游唯一口径：检索、意图分类、工单号提取全用消解后的句子

## nodes.py 逐段走读

### _history_text：摘要行 + 滑窗

```python
def _history_text(state, max_turns: int = 6) -> str:
    msgs = memory.build_window(state.get("messages", []),
                               state.get("summary_upto_msg_id") or 0,
                               settings.context_window_max_tokens)
    prior = msgs[:-1] if msgs else []
    lines = []
    for m in prior[-max_turns:]:
        role = "用户" if isinstance(m, HumanMessage) else "助手"
        text = m.content if isinstance(m.content, str) else ""
        if text:
            lines.append(f"{role}:{text}")
    body = "\n".join(lines)
    head = memory.summary_line(state.get("summary"))
    return f"{head}\n{body}".strip() if head else body
```

- **两层结构**：`summary_line` 摘要行（"早前对话摘要:..."）+ 滑窗内最近 `max_turns` 轮原文
- `msgs[:-1]` 去掉本轮最后一条 human（当前问题在 query 里，不重复喂）
- `build_window` 先按摘要边界切窗（第 7 章）——跨滑窗的指代（"最开始那个工单"）靠摘要行兜住

### _TICKET_RE：中英混排的正则边界坑

```python
# 工单号:优先完整 WO-YYYY-NNNN;只报后段数字(如 0001)时回退 4+ 位数字;
# 用 lookaround 而非 \b——CJK 与数字同属 \w,\b 在「工单0001」处不成立
_TICKET_RE = re.compile(r"WO-\d{4}-\d{4}|(?<!\d)(\d{4,})(?!\d)")

def _extract_ticket_id(text: str) -> str | None:
    m = _TICKET_RE.search(text or "")
    return m.group(0) if m else None
```

- 优先完整格式 `WO-2026-0001`
- 只报后段数字（"0001"）时回退 4+ 位数字
- **用 lookaround（`(?<!\d)`/`(?!\d)`）而不是 `\b`**：CJK 与数字同属 `\w`，`\b` 在"工单0001"这种中英混排处不成立——`\b` 要求一侧是 `\w` 一侧非 `\w`，而"单"和"0"都是 `\w`，边界不存在。lookaround 只看两侧是不是数字，精确得多

### fetch_ticket：中断-恢复

```python
async def fetch_ticket(state) -> dict:
    uid = state.get("user_id", "")
    tid = state.get("ticket_id") or _extract_ticket_id(
        state.get("resolved_query") or _user_text(state))
    while not business.owns_ticket(uid, str(tid or "")):
        tickets = business.list_user_tickets(uid)                     # 只读,可安全重跑
        tid = interrupt({"type": "select_ticket", "tickets": tickets})  # resume 回填工单号
    data = business.ticket_snapshot(tid)
    return {"ticket_id": tid, "ticket_data": data,
            "trace": {"fetch_ticket": {"ticket_id": tid}}}
```

逐点拆：

1. **取号**：优先 state 里的 ticket_id（resume 回填的），否则从消解后的问句里正则抽取
2. **归属校验放节点层**：注释点破——"该子流程是确定性节点，不经 agent_tools，工具那道校验够不着"。用户随口报的号、resume 端点回传的号，都得过同一道 `owns_ticket`（空 user_id 一律不放行）
3. **`while` + `interrupt`**：不满足归属就一直中断弹选择器，直到前端点选合法工单号 resume 回填
4. **interrupt 前只做只读**：`list_user_tickets` 不写状态，resume 时本节点从头重跑安全——不会因重跑产生副作用
5. **为什么宁可打断用户也不让模型猜**：工单号是敏感业务数据，猜错就建到别人的单上

## actions.py 逐段走读（中断续跑 API）

### resume_action：SSE 续跑

```python
@router.post("/api/actions/resume")
async def resume_action(req: ResumeRequest):
    if req.ticket_id is None and req.confirmed is None:
        raise HTTPException(status_code=400, detail="ticket_id 与 confirmed 至少传一个")
    resume_value = req.ticket_id if req.ticket_id is not None else {"confirmed": bool(req.confirmed)}

    async def event_stream() -> AsyncIterator[str]:
        async for ev in runtime.stream_resume(req.conversation_id, resume_value):
            ...
```

- **两种中断语义**：工单选择器点选回 `ticket_id`；工单预览卡回 `confirmed`（ch08，resume 值为 `{"confirmed": bool}`，agent_tools 按此放行/拒绝）
- 参数校验：ticket_id 与 confirmed 至少传一个（400 早拦，不走到图里才发现）
- SSE 事件流与 /api/chat 同构——前端同一套流式渲染

### create_ticket / confirm_ticket：写操作 API

```python
@router.post("/api/actions/create-ticket", response_model=CreateTicketResponse)
async def create_ticket_action(req: CreateTicketRequest) -> CreateTicketResponse:
    try:
        ticket_no = await repository.create_ticket(
            req.conversation_id, req.description, req.ticket_type)
    except SQLAlchemyError:
        logger.exception("建工单失败 conv=%s", req.conversation_id)
        raise HTTPException(status_code=503, detail="工单系统暂时不可用,请稍后重试")
    return CreateTicketResponse(ticket_no=ticket_no)
```

- **用户点了才写 tickets 表**（确认流：模型只出草稿，人确认才落库）
- DB 异常统一转 503 + 人话（"工单系统暂时不可用，请稍后重试"）——不把 SQLAlchemy 异常裸抛给前端

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| `Literal` 限定输出 + 二次校验 | 模型没有自由发挥空间，越界归"其他" |
| 分类异常全兜底 | 意图分错最多走错出口，异常扩散才是灾难 |
| 扁平字段 | 嵌套结构化输出触发上游 502 |
| 消解失败返回原句 | 消解是增强不是依赖，不阻断链路 |
| lookaround 而非 `\b` | CJK 与数字同属 `\w`，中英混排边界失效 |
| 归属校验放节点层 | 确定性子流程不经 agent_tools，工具校验够不着 |
| interrupt 前只读 | resume 从头重跑安全无副作用 |
| resume 参数早校验（400） | ticket_id 与 confirmed 至少传一个，不走到图里才发现 |
