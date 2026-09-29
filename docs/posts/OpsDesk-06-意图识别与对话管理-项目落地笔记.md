# 第 06 章：意图识别与对话管理 —— 项目落地笔记

**日期**：2026-08-31
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及源码：`app/core/intent.py`、`app/core/coref.py`、`app/core/query_understanding.py`、`app/graph/nodes.py`、`app/graph/routing.py`、`app/api/actions.py`

## 为什么意图是这一切的地基

用户一句话进来，系统第一件事不是回答，而是搞清楚**他想干嘛**。这个"想干嘛"就是意图。在 OpsDesk 里，意图标签的价值远超"分流"本身，它同时是：

- **分流的依据**：该查知识库的查知识库、该调工具调工具、该安抚的安抚
- **日志统计的维度**：按意图统计对话量、token 成本（第 9 章 cost-by-intent 就是按这个标签算的）
- **数据飞轮归类的依据**：哪类问题答不上最多、先补哪块知识（第 9 章）

所以这里有个设计原则贯穿始终：**识别要细，处理要合**。意图标签要细到能支撑统计（9 类），但处理出口要合到够用（4 个），中间靠一张映射表转接——这个后面细讲。

## 意图怎么分类出来的

### 分类本身：LLM 结构化输出 + 置信度

`app/core/intent.py` 用模型做意图分类，但**不是让它自由发挥**，而是要求它输出一个严格的结构化对象：

```python
INTENTS = ("报修", "查工单", "故障咨询", "巡检", "合同费用", "备件咨询", "投诉", "闲聊", "其他")

class _Intent(BaseModel):
    intent: Literal["报修", "查工单", "故障咨询", "巡检", "合同费用", "备件咨询", "投诉", "闲聊", "其他"] = Field(
        description="九类意图之一")
    confidence: float = Field(default=0.5, ge=0.0, le=1.0, description="判断把握 0-1")
```

注意 `Literal` 把输出限定死在 9 个值里——模型没有自由发挥的空间。`confidence` 是模型自评的把握度（0-1），下游可以做置信度门控。整个调用走的是 `llm.structured(...)`，即 LangChain 的 `with_structured_output`：模型一次调用直接吐出符合 Pydantic 结构的 JSON，不用再解析。

### 两个看起来不起眼、实际都是坑的设计

**扁平字段，避 glm 嵌套 502**。注释里写得很清楚：`扁平字段避开 glm 嵌套 502`。早期意图模型用过嵌套结构，结果某家上游对深层嵌套 JSON 的响应格式不稳定，直接 502——后来把所有字段拍平，让模型只输出一层 key-value，问题消失。**结构化输出遇到不稳定，先怀疑是不是格式本身太复杂。**

**解析失败/越界 → 归"其他"**。`classify()` 把整个调用包在 try/except 里：

```python
try:
    r: _Intent = await (INTENT_CLASSIFY_PROMPT | model).ainvoke(...)
except Exception:
    return {"intent": "其他", "confidence": 0.0}
intent = r.intent if r.intent in INTENTS else "其他"
```

模型抽风、上游超时、输出不在 9 类里——**全部最保守兜底到"其他"**，而不是让流程炸掉或瞎猜。意图分错最多是走错出口，流程兜底能接住；让异常扩散才是灾难。

### 意图模型可以单独指定

`settings.intent_model` 为空时回落 `chat_model`——也就是说**意图分类可以单独用一个小/便宜的模型**。注释给的理由是"先求准"：意图是地基，分类质量直接影响所有下游，值得单独选模型调优，而不是跟着对话模型走。

## 让模型听懂半截话：指代消解

用户不会每次都把话说完整。你刚跟它聊完 VFD-3005 变频器，下一句说"它为啥总是过载报警"——"它"是谁？"报修一下"——报修什么？

`app/core/coref.py` 的 `resolve()` 干的就是这件事：**结合历史把半截话补成完整问句**：

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

三个要点：

1. **消解后的完整问句（resolved_query）是下游唯一的口径**——检索、意图分类、工单号提取全用消解后的句子，不是原始输入。这保证"它"在检索时已经是"VFD-3005 变频器"
2. **失败兜底返回原句**：消解挂了就原样往下走，不阻断链路——消解是增强不是依赖
3. **历史喂多少**：`_history_text` 构造历史时先按摘要边界切窗再取尾（第 7 章上下文管理细讲），跨滑窗的指代（"最开始那个工单"）靠摘要行兜住

## 从意图到出口：一张映射表

`routing.py` 里那张 `INTENT_TO_ROUTE`（第 5 章展示过），这里说它为什么是"单一来源不漂移"：

- **分流**读它：`route_by_intent` 按意图查表决定走 knowledge / business / escalate / fallback_script
- **日志统计**也读它：第 9 章的成本账、飞轮归类都按意图标签
- 全项目**只有这一份**——如果分流一套表、统计又抄一份，改一次就两处漂移，早晚对不上

"识别要细、处理要合"的落点就在这里：9 类意图收成 4 个出口，因为好几类的走法完全一样（故障咨询/巡检/合同费用都走 knowledge，报修/查工单/备件咨询都走 business）。

## 工单子流程里的对话管理：中断-恢复

这是第 5 章工单子流程里最硬核的一段，值得单独讲。`fetch_ticket` 节点：

```python
async def fetch_ticket(state) -> dict:
    uid = state.get("user_id", "")
    tid = state.get("ticket_id") or _extract_ticket_id(
        state.get("resolved_query") or _user_text(state))
    while not business.owns_ticket(uid, str(tid or "")):
        tickets = business.list_user_tickets(uid)
        tid = interrupt({"type": "select_ticket", "tickets": tickets})
    data = business.ticket_snapshot(tid)
    return {"ticket_id": tid, "ticket_data": data, ...}
```

### 问题一：工单号怎么从对话里抠出来

`_extract_ticket_id` 用的正则很讲究：

```python
_TICKET_RE = re.compile(r"WO-\d{4}-\d{4}|(?<!\d)(\d{4,})(?!\d)")
```

- 优先完整格式 `WO-2026-0001`
- 用户只报后段数字（"0001"）时，回退匹配 4 位以上数字
- **用 lookaround（`(?<!\d)`/`(?!\d)`）而不是 `\b`**——注释解释了原因：CJK 与数字同属 `\w`，`\b` 在"工单0001"这种中英混排处不成立，会匹配不到。这种边角坑不实际跑中文输入根本发现不了

### 问题二：为什么归属校验要放在节点层，而不只在工具里

注释原话：**"该子流程是确定性节点，不经 agent_tools，工具那道校验够不着。"**

这是很容易踩的洞：第 2 章我在工具层做了 `owns_ticket` 归属校验，但工单子流程是确定性链（fetch_ticket → retrieve_policy → main_agent），**根本不走 agent_tools**——如果校验只放在工具层，用户随口报一个别人的工单号，子流程就直接查了。所以节点层也过同一道 `owns_ticket`，用户随口报的号、resume 端点回传的号，都得过同一道判断。

### 问题三：缺工单号怎么办——打断用户，让他点选

`interrupt({"type": "select_ticket", "tickets": tickets})` 是 LangGraph 的 human-in-the-loop：流程跑到这里暂停、保存 checkpoint，把控制权交给前端。前端收到中断帧弹**工单选择器**（列出该用户名下所有工单），用户点选后 resume 回填 ticket_id，流程从保存点继续。

两个设计细节：

- **interrupt 之前只做只读**（`list_user_tickets` 不写状态），所以 resume 时本节点从头重跑是安全的——不会因为重跑产生副作用
- **为什么宁可打断用户也不让模型猜**：建单是写操作，工单号是敏感业务数据，模型猜错了就建到别人的单上。打断一次换一个确认，值

## 历史窗口怎么喂给模型

对话管理还有一层：分类/消解时给模型看多长的历史。`_history_text` 的做法：

```python
msgs = memory.build_window(state.get("messages", []),
                           state.get("summary_upto_msg_id") or 0,
                           settings.context_window_max_tokens)
prior = msgs[:-1] if msgs else []
for m in prior[-max_turns:]:   # 最近若干轮
    ...
head = memory.summary_line(state.get("summary"))
return f"{head}\n{body}".strip() if head else body
```

两层结构：**摘要行（最开头）+ 滑窗内最近若干轮原文**。摘要行把"用户最早报修了什么设备、工单号是什么"这种要长期记的事浓缩成一行，滑窗提供最近的完整上下文。跨滑窗的指代（"最开始那个工单"）就靠摘要行兜住。详细的分层上下文管理在第 7 章。

## 确定性出口：投诉和闲聊

不是所有意图都值得动用模型。`complaint_reply` 和 `script_reply` 是**确定性话术节点**，模型不出场：

- **投诉**：`COMPLAINT_REPLY_TEXT`——安抚话术写死。为什么？投诉场景用户情绪上头，模型自由发挥容易火上浇油，而且承诺"一定给您解决"可能超出系统能力
- **闲聊/其他**：`SCRIPT_REPLY_CHITCHAT` / `SCRIPT_REPLY_OTHER`——礼貌引导回运维话题

省钱是附带的，**可控才是目的**：这些场景不需要推理，确定性话术又快又不会出错。

## 踩坑汇总

1. **嵌套结构化输出触发上游 502** → 字段拍平，一次只输出一层 key-value
2. **正则 `\b` 在中英混排处失效**（CJK 同属 `\w`）→ 用 lookaround 手写边界
3. **归属校验只放工具层，确定性子流程够不着** → 节点层过同一道 owns_ticket
4. **分类器异常让流程炸** → 全部最保守兜底到"其他"，流程兜底接住
5. **消解失败阻断链路** → 兜底返回原句，消解是增强不是依赖

## 怎么验证

```bash
# 意图/提取相关测试
& "D:\Pythonproject\mewhelp\.venv\Scripts\python.exe" -m pytest tests/test_intent.py tests/test_extract_api.py tests/test_schemas.py -q

# 起应用后实测三类场景：
# 多轮指代：先问"TS-4001 温度传感器有什么参数"，再问"它安装在哪个位置"
# 报修确认流：VFD-3005 变频器过载报警帮我报修 → 应弹工单/确认卡
# 归属校验：我的工单 WO-2026-9999 处理到哪了 → 应被拦下
```
