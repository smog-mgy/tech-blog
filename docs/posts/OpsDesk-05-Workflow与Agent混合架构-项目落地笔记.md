# 第 05 章：Workflow + Agent 混合架构 —— 项目落地笔记

**日期**：2026-08-27
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及源码：`app/graph/build.py`、`app/graph/nodes.py`、`app/graph/routing.py`、`app/graph/state.py`

## 从一次事故说起

这套架构不是一开始就这样的。最早我图省事，把整条链路交给一个 Agent——意图分类、检索、回答全让它自己来。结果一跑真实场景就现了原形：

- 它会**图省事跳过检索**，凭模型记忆直接答——用户问自家设备的事，它答得头头是道但全是编的
- 该拒答的时候它**敢硬编一个像模像样的答案**
- 建单这种写操作，它敢自己拍板，不问用户

运维场景这种事一次就是事故。所以架构改成了现在的样子：**确定性 Workflow 定纪律，Agent 只做它擅长的开放推理**。

## 图长什么样

`build.py` 里用 LangGraph 的状态图把整条链路画出来：

```
resolve_reference（指代消解）
  → classify_intent（意图分类）
    → 四个出口：
      投诉 → complaint_reply（安抚话术，模型不出场）
      闲聊/其他 → script_reply（兜底脚本）
      知识类 → retrieve_knowledge → confidence_check（证据闸）→ main_agent / fallback_reply
      报修/查工单/备件 → fetch_ticket → retrieve_policy → main_agent（确定性子流程）
    → main_agent 的 ReAct 环：main_agent ⇄ agent_tools，直到停止条件
  → log → END
```

关键设计：**该写死的用代码写死，该开放的才交给模型**。

## 写死的部分

**1. 意图 → 出口的映射是代码，不是模型的自由发挥**

`routing.py` 里一张表定死：

```python
INTENT_TO_ROUTE = {
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
```

识别要细（日志、成本统计都靠意图标签），处理要合（好几类走法一样），**映射表全项目只有一份**——分流和日志都读它，不会两处对不上。

**2. 知识路必须过证据闸**

`retrieve_knowledge → confidence_check`，`confidence_gate` 判断证据强不强：强才放给模型答，弱直接走 `fallback_reply` 兜底。**模型根本不出场**——回答是流式一个字一个字推给用户的，吐出去收不回来，所以这道检查必须卡在生成之前。

**3. 工单子流程是确定性链**

报修/查工单/备件不走自由发挥，走 `fetch_ticket → retrieve_policy → main_agent` 这条写死的链：先取工单（归属校验在这里拦人）、再检索制度、最后才把"这张单怎么处理"交给模型。

**4. 投诉、闲聊是确定性出口**

`complaint_reply`、`script_reply` 直接产出固定话术，模型完全不出场——投诉不该让模型自由发挥（容易火上浇油），闲聊不用浪费 token。

## 留给模型的：ReAct 环

主力 Agent 只在一个小圈子里活动：`main_agent ⇄ agent_tools`。模型决定要不要调工具、调什么，框架负责执行（第 2 章的引擎）。

停止条件写在 `should_continue`：

```python
last = state["messages"][-1]
has_tool_calls = isinstance(last, AIMessage) and bool(last.tool_calls)
if not has_tool_calls:
    return "stop"          # 模型不再要求调工具 → 收敛
if state.get("steps", 0) >= settings.max_agent_steps:
    return "stop"          # 步数封顶强停（护栏）
return "continue"
```

这里有个取舍值得记下来：**只用步数封顶，不在这里卡 token**。步数一步一次模型调用，数得清、好解释；token 管的是烧钱和撑爆上下文，是另一件事，混在这里卡的话一次估偏就把工具链整条掐断——而且掐在模型已经决定调工具之后，用户只看到半句"我这就去查"。

## 踩过的坑：state 里 trace 跨轮残留

状态定义在 `state.py`，其中 `trace` 字段的 reducer 有个细节：

```python
def merge_dict(a: dict | None, b: dict | None) -> dict:
    if b is None:
        return {}
    return {**(a or {}), **b}
```

为什么入口要传 `None` 当"重置哨兵"？因为 merge 通道塞 `{}` 清不掉（merge(旧, {}) = 旧），上一轮的条件键（比如 retrieve_policy 走了没有）会**跨轮残留**——下一轮不相关的问题可能被上一轮的残留键带偏。所以入口每轮传 `trace=None` 清零，图内节点写 trace 恒为真 dict，既不误伤累加又能保证每轮干净。

## 现在这套架构好在哪

面试官视角（或者说，将来你自己回头看）：**每一步为什么存在都有来路**。不是照着最佳实践堆出来的，是每个翻车场景逼出来的：

| 翻车 | 应对 |
|---|---|
| Agent 跳过检索凭记忆答 | 知识路强制先检索 + 证据闸 |
| 该拒答时硬编 | 证据弱直接兜底，模型不出场 |
| 建单拍板不问用户 | 写操作走确定性子流程 + 确认流 |
| 投诉被模型自由发挥激化 | 确定性安抚话术 |

## 怎么验证

```bash
# 图编排的行为测试（意图路由、节点顺序、中断帧 payload）
& "D:\Pythonproject\mewhelp\.venv\Scripts\python.exe" -m pytest tests/graph/ -q

# 起应用后分别试四类问题，看走向不同出口：
# 知识类：电机过热报警怎么排查 → 检索 → 证据闸 → Agent
# 报修类：VFD-3005 变频器过载报警帮我报修 → 工单子流程 → 确认卡
# 投诉类：我要投诉你们服务太差 → 安抚话术（模型不出场）
# 闲聊类：今天天气怎么样 → 兜底脚本
```
