# 第 07 章：会话上下文管理（源码解析）

**日期**：2026-09-05
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 07 章：会话上下文管理（项目落地笔记）.md`
> 本解析按文件逐段走读，讲清每个函数为什么这么写。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/core/memory.py` | 会话存储、token 裁剪、锚点切窗、摘要注入 |
| `app/core/summarizer.py` | 后台滚动摘要：边界计算、LLM 压缩、任务调度 |
| `app/graph/nodes.py` | `_history_text` 消费方：摘要行 + 滑窗喂给 coref/意图 |
| `app/graph/state.py` | `summary` / `summary_upto_msg_id` 两个 state 字段 |

## memory.py 逐段走读

### SessionStore：内存会话存储

```python
class SessionStore:
    def __init__(self) -> None:
        self._sessions: dict[str, list[BaseMessage]] = {}

    def get(self, session_id: str) -> list[BaseMessage]:
        return self._sessions.get(session_id, [])

    def append(self, session_id: str, *messages: BaseMessage) -> None:
        self._sessions.setdefault(session_id, []).extend(messages)
```

极简 dict 封装。注释明说"本章不做持久化"——上下文管理的真正持久化在 MySQL（`conversations` / `dialog_messages` 表，由 repository 管），这个内存 store 是历史遗留/本地快速验证用，真实链路从 DB 加载。

### trim_history：token 兜底裁剪

```python
def trim_history(messages, max_tokens):
    return trim_messages(
        messages,
        strategy="last",
        token_counter=count_tokens_approximately,
        max_tokens=max_tokens,
        start_on="human",
        allow_partial=False,
    )
```

LangChain `trim_messages` 的关键参数：

- `strategy="last"`：从末尾往前留（保留最近的）
- `start_on="human"`：窗口起点对齐到用户消息——不能从一条助手消息中间开始，否则模型看到的是半截话
- `allow_partial=False`：宁可在 token 上限内多留/少留，也不切半条消息（切半条消息会让模型读到残缺句子，比超点预算更糟）
- `count_tokens_approximately`：近似 token 计数，不调 tokenizer，快

### _db_msg_id：从消息 id 解出 MySQL 消息 id

```python
_DB_ID_PREFIX = "db-"

def _db_msg_id(m: BaseMessage) -> int | None:
    mid = getattr(m, "id", None)
    if isinstance(mid, str) and mid.startswith(_DB_ID_PREFIX):
        try:
            return int(mid[len(_DB_ID_PREFIX):])
        except ValueError:
            return None
    return None
```

**这是锚点切窗的地基**：入口约定 `HumanMessage.id = f"db-{msg_id}"`，把 LangChain 消息和 MySQL 持久化消息一一对应。消息 id 不是任意值，而是能回查数据库的锚点。解析失败（非 db- 前缀 / 不是数字）返回 None，调用方会把它当"非锚点"处理。

### build_window：锚点切窗 + token 兜底

```python
def build_window(messages, summary_upto_msg_id, max_tokens):
    start = 0
    if summary_upto_msg_id:
        for i, m in enumerate(messages):
            if isinstance(m, HumanMessage):
                did = _db_msg_id(m)
                if did is not None and did > summary_upto_msg_id:
                    start = i
                    break
    window = messages[start:]
    trimmed = trim_history(window, max_tokens=max_tokens)
    return trimmed or window
```

核心逻辑三步：

1. **找起点**：遍历消息，找到第一条"db-id 大于摘要边界"的**用户消息**，滑窗从它开始——边界之前的内容已被摘要接管，不需要原文
2. **切窗**：`messages[start:]` 一条不切地取下来（保证语义完整）
3. **token 兜底**：`trim_history` 按 token 预算再压一层；**裁到空就回退原窗**（`trimmed or window`）——宁可超预算，不能把刚说的关键话裁没

注意它**只在调模型前现拼、不改 State**——build_window 是纯函数，不产生副作用。

### summary_line / summary_system：摘要注入的两种形态

```python
def summary_line(summary: str | None) -> str:
    return f"(早前对话摘要:{summary})" if summary else ""

def summary_system(summary: str | None) -> SystemMessage | None:
    if not summary:
        return None
    return SystemMessage(f"## 早前对话摘要(更早轮次已压缩,其中事实可信)\n{summary}")
```

同一个摘要，两种消费方式：

- `summary_line`：**一行文本前缀**，拼进 coref/意图分类的历史字符串（nodes `_history_text` 里 `head = memory.summary_line(...)`），成本极低
- `summary_system`：**一条 SystemMessage**，紧跟人设 system 塞给主力 Agent——它比滑窗原文更可信（"其中事实可信"），模型回答长程问题时优先依据它

## summarizer.py 逐段走读

### _Summary：摘要的结构化约束

```python
class _Summary(BaseModel):
    summary: str = Field(description="早期对话滚动摘要,只含事实与诉求")
```

structured output 约束模型：摘要只写事实与诉求，不写情绪、寒暄。字段描述就是给模型的指令，`llm.structured` 会把它送进函数调用的 schema。

### compute_boundary：新摘要边界怎么算

```python
def compute_boundary(messages, keep_turns: int) -> int | None:
    user_idx = [i for i, m in enumerate(messages) if m.role == "user"]
    if len(user_idx) <= keep_turns:
        return None
    cut = user_idx[-keep_turns]
    if cut == 0:
        return None
    return messages[cut - 1].id
```

数学逻辑：

- `messages` 是按 id 升序的 user/assistant 行
- 找出所有用户消息下标，取**倒数第 keep_turns 个**作为切点
- 切点指向"倒数第 keep_turns 轮用户消息"，返回它**前一条消息的 id** 作为边界——这样滑窗从"倒数第 keep_turns 轮用户消息"开始，正好保住最近 keep_turns 轮完整原文
- 轮数不足 / 切点落在会话开头 → `None`（本次放弃，等轮数够了再说）

### summarize_dialog：LLM 滚动重写

```python
async def summarize_dialog(old_summary: str, dialog: str) -> str:
    model = llm.structured(_Summary, model=settings.summary_model or None)
    r: _Summary = await (SUMMARY_PROMPT | model).ainvoke(
        {"old_summary": old_summary or "(无)", "dialog": dialog})
    return (r.summary or "").strip()
```

滚动重写的核心：输入是 **旧摘要 + 新滑出段**，不是全部历史——摘要长度有界，不会越滚越长。`settings.summary_model` 可单独指定摘要模型（空则回落 chat_model）。

### run_summary：任务体

```python
async def run_summary(conversation_id: int) -> None:
    conv = await repository.get_conversation(conversation_id)
    if conv is None:
        return
    msgs = await repository.list_dialog_messages(conversation_id)
    boundary = compute_boundary(msgs, settings.context_window_turns)
    old_upto = conv.summary_upto_msg_id or 0
    if boundary is None or boundary <= old_upto:
        logger.info("summary skip ...")
        return
    seg = [m for m in msgs if old_upto < m.id <= boundary]
    dialog = "\n".join(f"{'用户' if m.role == 'user' else '助手'}:{m.content}" for m in seg if m.content)
    summary = await summarize_dialog(conv.summary or "", dialog)
    if not summary:
        raise ValueError("摘要为空,放弃更新")
    await repository.update_conversation_summary(conversation_id, summary, boundary)
```

流水线六步：

1. 读会话（不存在直接返回）
2. 读全部消息
3. 算新边界；**边界没推进（`<= old_upto`）就放弃**——防止重复压缩同一段
4. 取 `(old_upto, boundary]` 之间的消息当新滑出段（只压缩新增部分，天然幂等）
5. LLM 滚动重写；**摘要为空抛异常放弃更新**（宁可保留旧摘要，不写空摘要）
6. `update_conversation_summary(conversation_id, summary, boundary)` **原子更新两字段**——summary 和 boundary 一起落库，杜绝"摘要写了、边界没动"的中间态

全程 log 成本毫秒数——后台任务也要可观测。

### maybe_schedule_summary：触发与防抖

```python
_running: dict[int, asyncio.Task] = {}   # cid -> 在跑任务(防抖:在跑不重复起)

async def maybe_schedule_summary(conversation_id: int) -> None:
    try:
        if conversation_id in _running:
            return
        conv = await repository.get_conversation(conversation_id)
        if conv is None:
            return
        n = await repository.count_messages_after(conversation_id, conv.summary_upto_msg_id)
        # ...（n 达阈值 → create_task 后台跑，不 await）
```

三个设计：

- **防抖**：同一会话有在跑任务就不重复起（`_running` 表）
- **计数触发**：`count_messages_after` 统计边界后新增消息数，达阈值才跑——不是每轮都跑
- **不阻塞**：`create_task` 后台跑、不 await，用户回复路径上任何异常只 log 不外抛（触发条件仍在，下一轮自然重触发）

## 数据流全景

```
轮结束后
  → maybe_schedule_summary(cid)
      → 防抖检查 → 计数达阈值 → create_task（不 await）
          → run_summary(cid)
              → 读消息 → 算边界 → 取新滑出段 → LLM 滚动重写
              → 原子更新 summary + summary_upto_msg_id（MySQL）
下一轮入口
  → 从 MySQL 加载 summary / summary_upto_msg_id 进 state
  → build_window：从边界后第一条用户消息起取滑窗（摘要接管更早内容）
  → summary_line → coref/意图；summary_system → 主力 Agent
```

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| `db-{msg_id}` 锚点 | 把 LangChain 消息与 MySQL 消息一一对应，滑窗边界可精确回查 |
| 锚点切窗（不是纯 token 裁剪） | 早期事实由摘要接管，滑窗保住近期完整原文 |
| `trimmed or window` | 裁到空宁可超预算回退，不丢关键话 |
| 后台异步 + 计数触发 + 防抖 | 摘要不阻塞回复，也不重复跑 |
| 滚动重写 | 摘要长度有界，不会越滚越长 |
| 两字段原子更新 | 杜绝摘要与边界不同步的中间态 |
