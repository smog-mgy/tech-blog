# 第 05 章：Workflow + Agent 混合架构（源码解析）

**日期**：2026-08-28
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 05 章：Workflow + Agent 混合架构（项目落地笔记）.md`
> 本解析逐段走读 LangGraph 状态图的骨架、分流函数与状态 reducer。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/graph/build.py` | 状态图骨架：节点、边、条件边 |
| `app/graph/routing.py` | 分流：意图→出口映射、证据闸、ReAct 停止条件 |
| `app/graph/state.py` | 状态定义与 reducer（trace 累加/重置） |

## build.py 逐段走读

### 节点登记

```python
def _builder() -> StateGraph:
    b = StateGraph(ConversationState)
    b.add_node("resolve_reference", nodes.resolve_reference)
    b.add_node("classify_intent", nodes.classify_intent)
    b.add_node("retrieve_knowledge", nodes.retrieve_knowledge)
    b.add_node("confidence_check", nodes.confidence_check)  # 实体节点(trace 门控);判断在其后条件边
    b.add_node("main_agent", nodes.main_agent)
    b.add_node("agent_tools", nodes.agent_tools)
    b.add_node("complaint_reply", nodes.complaint_reply)
    b.add_node("script_reply", nodes.script_reply)
    b.add_node("fallback_reply", nodes.fallback_reply)
    b.add_node("fetch_ticket", nodes.fetch_ticket)
    b.add_node("retrieve_policy", nodes.retrieve_policy)
    b.add_node("log", nodes.log_node)
    ...
```

13 个节点，每个节点一个职责。注意 `confidence_check` 的注释——"实体节点（trace 门控）；判断在其后条件边"：节点本身要执行（产生 trace），判断逻辑放条件边。

### 骨架边：消解 → 意图 → 分流

```python
b.add_edge(START, "resolve_reference")
b.add_edge("resolve_reference", "classify_intent")
b.add_conditional_edges("classify_intent", route_by_intent, {
    "escalate": "complaint_reply",
    "fallback_script": "script_reply",
    "knowledge": "retrieve_knowledge",
    "ticket_flow": "fetch_ticket",
    "business": "main_agent",
})
```

- 无条件边：消解 → 意图（必走）
- 条件边：按 `route_by_intent` 返回值映射到五个出口之一

### 工单子流程确定性链

```python
b.add_edge("fetch_ticket", "retrieve_policy")
b.add_edge("retrieve_policy", "main_agent")
```

报修/查工单/备件不自由发挥：取单 → 检索制度 → 才轮到 Agent——**确定性链把"必做的事"锁死**（归属校验、强制检索在进 Agent 之前完成）。

### 知识路证据闸

```python
b.add_edge("retrieve_knowledge", "confidence_check")
b.add_conditional_edges("confidence_check", confidence_gate, {
    "strong": "main_agent",
    "weak": "fallback_reply",
})
```

检索完必须过置信度闸：强放行给 Agent、弱直接兜底——**模型对弱证据根本不出场**（回答是流式的，吐出去收不回来，必须卡在生成前）。

### 主力 Agent ReAct 环

```python
b.add_conditional_edges("main_agent", should_continue, {
    "continue": "agent_tools",
    "stop": "log",
})
b.add_edge("agent_tools", "main_agent")
```

main_agent ⇄ agent_tools 循环，`should_continue` 决定是否收敛——模型决定要不要调工具，框架执行，循环直到停止条件（下面 routing 细讲）。

### 确定性出口 → 日志 → END

```python
b.add_edge("complaint_reply", "log")
b.add_edge("script_reply", "log")
b.add_edge("fallback_reply", "log")
b.add_edge("log", END)
```

所有出口统一过 `log` 节点收尾（落库、留痕），再 END。

## routing.py 逐段走读

### INTENT_TO_ROUTE：映射单一来源

```python
INTENT_TO_ROUTE: dict[str, str] = {
    "投诉": "escalate",
    "闲聊": "fallback_script",
    "其他": "fallback_script",
    "故障咨询": "knowledge",
    "巡检": "knowledge",
    "合同费用": "knowledge",
    "报修": "business",
    "查工单": "business",
    "备件咨询": "business",
}

def route_by_intent(state) -> str:
    return INTENT_TO_ROUTE.get(state.get("intent", ""), "business")
```

- 9 类意图收成 5 个出口（注释："写死的分流规则，spec §3.1 / README route_by_intent；返回值 = build.py 条件边映射键，单一来源不漂移"）
- **未知意图保守归 business**：让 Agent 自己应对——宁可走 Agent 兜底，不硬塞错误出口

### confidence_gate：证据闸

```python
def confidence_gate(state) -> str:
    return "strong" if state.get("evidence_strong") else "weak"
```

只读一个布尔字段决定放行/兜底——生成前证据闸的判定极简，重的置信度计算在节点里（第 9 章的四信号闸）。

### should_continue：ReAct 停止条件

```python
def should_continue(state) -> str:
    last = state["messages"][-1]
    has_tool_calls = isinstance(last, AIMessage) and bool(last.tool_calls)
    if not has_tool_calls:
        return "stop"
    if state.get("steps", 0) >= settings.max_agent_steps:
        return "stop"
    return "continue"
```

docstring 是本文件最值得读的一段，把"为什么用步数不用 token"讲透：

- **只用步数封顶，不在这里卡 token**：步数一步一次模型调用，数得清、好解释；各家 Agent SDK 给的也是 max_turns / max_iterations 这类步数上限
- **token 是另一件事**：管的是烧钱和撑爆上下文，不是死循环；阈值要按真实用量分布标定，归第 9 章成本控制
- **混在一起卡的后果**：一次估偏就把工具链整条掐断，而且掐在模型已经决定调工具之后——用户只看到半句"我这就去查"

停止逻辑两步：最后一条不是带 tool_calls 的 AIMessage → 收敛；steps 达上限 → 强停（护栏防打转）。

## state.py 逐段走读

### ConversationState：全链路状态

```python
class ConversationState(TypedDict, total=False):
    messages: Annotated[list[AnyMessage], add_messages]  # 跨轮历史,checkpointer 续接
    summary: str
    summary_upto_msg_id: int
    user_id: str
    conversation_id: int
    intent: str
    resolved_query: str
    intent_confidence: float
    ticket_id: str
    ticket_data: dict
    route: str
    evidence: str
    citations: list
    evidence_strong: bool
    evidence_confidence: float
    fallback_source: str
    retrieved_snapshot: list
    answer: str
    steps: int
    tokens_used: int
    suggested_actions: list
    trace: Annotated[dict, merge_dict]
```

- `TypedDict, total=False`：字段可缺省，节点按需读写
- `messages` 用 `add_messages` reducer：跨轮追加而不是覆盖（checkpointer 续接的依据）
- `trace` 用 `merge_dict` reducer（下面讲）

### merge_dict：trace 累加与重置

```python
def merge_dict(a: dict | None, b: dict | None) -> dict:
    """trace 累加 reducer:后写覆盖同键,其余合并;b 为 None 是重置哨兵。"""
    if b is None:
        return {}
    return {**(a or {}), **b}
```

- 图内各节点写 trace 恒为真 dict（后写覆盖同键、其余合并）
- **入口（_graph_input）每轮传 trace=None 清零本轮**——注释点破原因："merge 通道塞 {} 清不掉（merge(旧, {}) = 旧），故用 None 触发重置"
- **为什么必须每轮清零**：上一轮的条件键（如 retrieve_policy 走了没有）会跨轮残留，下一轮不相关的问题可能被残留键带偏

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| 条件边 vs 无条件边 | 必走的锁死、可选的走条件，纪律与灵活分层 |
| 证据闸在生成前 | 回答流式不可撤回，弱证据直接兜底 |
| 步数封顶不卡 token | token 是成本问题不是死循环问题，混卡会掐断工具链 |
| 未知意图归 business | 不硬塞错误出口，让 Agent 兜底 |
| trace=None 重置哨兵 | merge 塞 {} 清不掉，防条件键跨轮残留 |
