# 学习笔记 05｜Workflow + Agent 混合架构：骨架归流程，脑子归模型

**日期**：2026-06-30
**标签**：AI Agent · Workflow · LangGraph

> 上一章结束，检索链路立住了。但用户报一个手机号说查物流：模型得先拿手机号查订单、从订单翻出物流单号、再拿单号查一次物流——当时的系统只许模型开一次工具调用，走完查订单就没了下文。套个循环让模型想查多久查多久？光套循环不够，还得想明白：客服系统把主动权整个交出去，让模型想干嘛就干嘛，捅的乱子比查不到一次物流严重得多。这一章讲清楚这个循环配在哪、怎么配。

---

## 一、两个主角：控制权交给谁

| | Workflow | Agent |
|---|---|---|
| 谁决定下一步 | **写代码的人**（运行时严格照路径走） | **运行时的模型**（现场判断要不要调工具、调哪个、再调一次吗） |
| 本质 | 整条流程写死在代码里 | 把「下一步该干嘛」的决定权交给大模型 |
| 关键词 | 照手册走 | 现场拿主意 |

先想清楚这层区别，后面「为什么要拼在一起用」才有的放矢。

---

## 二、客服请求走一圈：六个节点接力

1. **指代消解**：把「它多少钱」补全成「蓝牙耳机多少钱」——依赖上下文的问法先变成独立成立的问题
2. **意图识别**：识别用户想干嘛（物流/订单/商品/退款退货/售后/投诉/闲聊）
3. **按意图分流**：
   - **知识类**（政策、商品 FAQ）→ 强制先走一趟检索，资料先捞出来当上下文
   - **业务数据类**（物流、订单、售后）→ 直接进下一步
   - **闲聊** → 零检索零执行，直接回写死话术把话题引回产品咨询
   - **投诉** → 先回安抚话术，「转人工」「建工单」两个选项交用户自己点，不进执行环节
4. **主力 Agent**：这一章的主角。知识类分支在进 Agent 之前先过一道**置信度闸**——证据够才连同问题交给 Agent 作答，不够直接走兜底话术 + 记下问题留飞轮。**为什么闸卡在 Agent 之前**：Agent 的答复逐字流式吐给用户，等答完再判证据就晚了，弱证据凑出来的答案早发出去了。业务数据类没检索证据，不走闸
5. **记录日志**：模型想了什么、调了哪些工具、花了多少 token 全部留痕（可观测性的地基）

**骨架归属**：指代消解、意图识别、分流、证据闸、日志都是确定性的 Workflow 路径；只有主力 Agent 是临场判断。

---

## 三、主力 Agent 的引擎：ReAct 循环

ReAct = Reasoning + Acting，推理加行动。三步循环：

1. **Thought**：想一句现在该干嘛
2. **Action**：据此调用一个工具
3. **Observation**：工具结果递回来看

拿到 Observation 不算完，回到第 1 步——模型拿着新结果重新想。如此往复，直到信息够才收敛出最终答复。

**精髓**：「每拿到一个 Observation 就重新想一次」。走一步看一步，中间结果影响下一步，不是提前规划好整条路径再一口气执行。手机号查物流：先查订单 → 看到已发货带着物流单号 → 才决定下一步查这个单号的物流。下一步查什么，是盯着上一步的结果临场定的。

**Agent 是纯 LLM 能力的超集**：
- 简单知识类问题（「什么是运费险」）：资料已检索好随问题递进来，模型第一步发现上下文够用，连工具都不调直接组织语言——跟裸 LLM 调用一次没两样，不多花一分成本
- 复杂业务类（查订单+退款进度+确认运费）：走完一步信息不够，接着想接着查，多走几步才收敛

不用在 Agent 前面再加一层「这事简单还是复杂」的判断——**各种分支全被 Agent 吸收进去了**。

---

## 四、祛魅：循环这东西，你自己也写得出来

Agent 听着玄乎，拆开看就是一段带工具清单的 for 循环：

```python
async def run_agent(query: str, max_turns: int = 6):
    messages = [SystemMessage(AGENT_SYSTEM), HumanMessage(query)]
    for step in range(1, max_turns + 1):
        ai = await model.ainvoke(messages)
        messages.append(ai)
        if not ai.tool_calls:
            return ai.content          # 无工具调用 → 收敛
        for tc in ai.tool_calls:
            run = await execute_tool_call(tc, conversation_id=0)
            messages.append(run.tool_message)   # 结果塞回去，下一圈接着想
    return "(未收敛)"                   # 封顶用尽，生产应走兜底话术
```

跟第 2 章那圈单轮编排比，差别只有外面那个 `for`。**所谓 Agent = 给大模型配一个能反复调用工具的循环 + 一份工具清单，不是某个框架变出来的魔法。** LangGraph 做的也是同一件事，只是把这个循环放进一张更大的图里管理，没有重新发明什么。

### max_turns：管「钻牛角尖出不来」

工具描述写得含糊、两个工具用途重叠，模型看完结果一转身又调同一个。步数封顶给硬上限：一步一次模型调用，数得清、好解释。各家 SDK 给的同一件东西（LangChain `max_iterations` 默认 15、Claude `max_turns`）。本场景一轮最多两三步，封 6 步够用有余量。

### 常见误会：token 花销不该当停止条件

它防的不是打转，是**烧钱和撑爆上下文**。ReAct 每步都要把工具结果追加进上下文再整段重喂，花销滚着涨，该管，但该在别处管：阈值按真实用量分布标定，标偏一点就掐在模型已经决定调工具、结果还没拿到那一刻——用户看到半句「好的，我来查一下」然后没了下文。

---

## 五、Workflow 里那个 AI 节点，为什么非 Agent 不可

两条路都走不通：
- **裸 LLM**：没有工具，无法凭空知道手机号名下的订单状态（训练语料里压根没有）
- **写死分支**：把「先查订单再查物流」写死在 Workflow 里。能用但走不远——下一步依赖上一步结果，订单状态不同该查的完全不同；每冒一种新组合加一条新分支，代码爆炸，改一次分支测一遍所有旧分支

兜一圈还是得把「先查什么、再查什么」的决定权交出去。Agent 跟裸 LLM 的区别在于手里多了工具，跟写死分支的区别在于不需要开发者提前替它想好每一种排列组合。

---

## 六、全交给 Agent 会怎样：三个问题

1. **排查问题**：同一句提问跑两次，思考路径可能不一样（这次先查订单再查物流，下次先查商品）——很难指着某一步说「就是它错了」，调试监控难度比确定性流程高一大截
2. **漏了流程**：模型会自己「忘事」。知识类问题本该先检索，全权交给 Agent 后它有时漏调工具、凭训练语料直接给答案——听着像那么回事，其实资料里没这条，纯属编的；低置信度时本该拒答，它学「聪明」了也会硬凑一个糊弄过去。**两条都是业务上碰不得的硬约束**，被绕过用户拿到的就是自信满满的错误答案
3. **响应太慢**：大量用户只问几句，必须对首句或前几句迅速准确回答——不能依赖 Agent 自己去探索和用 RAG，时间不可控，稳定性也是

---

## 七、Workflow 把硬约束焊进轨道

「跳过检索硬答」「该拒答不拒答」能不能靠 Workflow 补回来？能，这正是 Workflow 最拿手的：

- **知识类必先检索**：写成死规矩，凡是判定知识类的意图一律先走检索，结果作为上下文交给主力 Agent——模型没有「忘记检索」这一说
- **置信度兜底**：证据不够流程强制回兜底话术，不让模型硬编

效果：幻觉率明显压下去；检索本身很快，相比模型推理生成，多这一趟查询几乎不增加成本——**用一点点确定性成本换稳定性和可控性，ROI 划算**。

Workflow 干的事：把几条不容商量的硬约束，从「希望模型别出错」的一厢情愿，变成「代码逻辑上模型压根绕不过去」的硬性保证。可观测性也顺路来了：每个节点各管一段职责，出问题顺着路径一步步查是谁的锅。

**结论**：生产环境几乎不存在非此即彼——用 Workflow 编排确定性骨架（硬约束嵌在路径节点上，保证整体行为可控、可观测、可调试），把最需要临场判断的活交给主力 Agent 这一个执行节点（在骨架划定的范围内自由发挥组合多变、依赖中间结果的逻辑）。**骨架管稳定，脑子管灵活。**

---

## 八、编排层为什么选 LangGraph

LangChain 链式组织（`|` 把 Runnable 首尾相接）适合「从头到尾一条直线」；客服流程是**分流再汇合**的图状走法：意图识别完要分流，几条支线还要在主力 Agent 汇合，状态从用户消息一路带到日志。硬拿链去拼，拼得七扭八歪。

LangGraph 把每一步做成图上的命名「节点」，节点间「边」连接，边上可挂条件决定走哪条分支，一份共享「State」顺图走完全程，每个节点都能读它改它：

```python
graph = StateGraph(ConversationState)
graph.add_node("resolve_reference", resolve_reference_node)    # 指代消解
graph.add_node("classify_intent", classify_intent_node)        # 意图识别
graph.add_node("retrieve_knowledge", retrieve_knowledge_node)  # 知识检索
graph.add_node("main_agent", main_agent_node)                  # 主力 Agent
graph.add_node("confidence_check", confidence_check_node)      # 置信度判断
graph.add_node("fallback_reply", fallback_reply_node)          # 兜底话术

graph.add_edge("resolve_reference", "classify_intent")         # 直连边
graph.add_conditional_edges("classify_intent", route_by_intent, {
    "knowledge": "retrieve_knowledge",   # 知识类，先走一趟检索
    "business": "main_agent",            # 业务数据类，直进主力 Agent
})
graph.add_edge("retrieve_knowledge", "confidence_check")
graph.add_conditional_edges("confidence_check", confidence_gate, {
    "strong": "main_agent",              # 证据够 → 交给主力 Agent
    "weak": "fallback_reply",            # 证据弱 → 直接兜底，不进 Agent
})
```

- `add_node` 定义节点，`add_edge` 加直连边，`add_conditional_edges` 接按判断走分支的边——`route_by_intent` 返回什么字符串就走对应节点
- 前面几章的 `ChatOpenAI`、Prompt 模板、流式输出放进节点照用，一个不用换
- 图状态自带 **checkpointer** 持久化，中断能接着跑；后面配 Langfuse 可观测天然对齐每个节点

**为什么不用 Dify/Coze 低代码平台拖拽**：省掉体力活，但换来的是链路封在平台里，出了问题看不清某一步在做什么，没法按业务逻辑精细控制每个节点；真要接自己的数据库和鉴权体系，平台照样要写代码。这门课要教的是怎么用 AI 工程化把系统一行行写出来。

---

## 九、代码走读要点

### State：图里流的是什么

```python
class ConversationState(TypedDict, total=False):
    messages: Annotated[list[AnyMessage], add_messages]  # 跨轮历史，checkpointer 续接
    intent: str            # 九类之一
    resolved_query: str    # 指代消解+改写后的完整问句
    steps: int             # ReAct 步数（停止条件）
    tokens_used: int       # token 预算累加
    trace: Annotated[dict, merge_dict]  # 留痕
```

- `total=False`：节点只返回自己改动的几个键，不用每次构造完整 State
- **`Annotated` 字段 = 有 reducer 的通道**：节点返回 `{"messages": [ai]}` 时 `add_messages` 会**追加**而不是整个替换；没 `Annotated` 的是普通标量，后写覆盖先写。这个区分后面会反复咬人
- 字段上的章节注释是全课的状态总账（第 6 章订单数据、第 7 章摘要锚点、第 9 章置信度快照）

### merge_dict 的 None 哨兵

```python
def merge_dict(a, b):
    if b is None:
        return {}           # None = 重置哨兵
    return {**(a or {}), **b}
```

State 按会话持久化，下一轮 `trace` 里留着上一轮内容。直觉传空字典清零，但 merge 通道 `merge(旧,{}) = 旧`，清不掉。于是约定：**入口传 `None` 表示重置**。前提是图内节点从不传 `None`——这种约定必须写进 docstring，不然下一个人在节点里返回 `{"trace": None}` 把整份留痕清空。

### 分流：写死的那部分

```python
INTENT_TO_ROUTE: dict[str, str] = {
    "投诉": "escalate", "闲聊": "fallback_script", "其他": "fallback_script",
    "商品咨询": "knowledge", "退款退货": "refund_flow", "售后": "refund_flow",
    "人工": "business", "物流": "business", "订单": "business",
}

def route_by_intent(state) -> str:
    return INTENT_TO_ROUTE.get(state.get("intent", ""), "business")
```

- 意图由模型判，映射到哪个出口由这张表定死——模型只回答「这句话属于哪类」，「投诉类怎么处理」代码说了算
- **这张表的值 = 条件边映射表的键，必须一致**，写在一个地方才不会漂；别处再抄一份，改漏一处，某类意图静默走到错误出口，日志还看不出异常
- 未知意图归 business 是保守选择：归兜底话术的话，模型判飞一次用户就被打发走了；归主力 Agent 至少还有机会调工具去查
- classify 用 `Literal[...]` 枚举，模型只能从九类里选；schema 约束了不代表模型守约，还有 `in INTENTS` 二次校验；整个调用 try 包住，异常归「其他」+ confidence 记 0，让下游看出是兜底不是真判断
- `settings.intent_model or None` 留口子：意图分类可单独指定模型，求准取向——每轮都跑，判错一次后面整条路跑偏，影响面比省点钱大得多

### should_continue：ReAct 什么时候停

先看模型自己收没收敛（最后一条无 tool_calls），有 tool_calls 才看步数封顶。docstring 是本章最值得读的一段：**步数管死循环、token 管烧钱是两件事，别混**。

### 几个节点

- **complaint_reply**：给 `suggested_actions`（转人工/建工单）而不是直接建工单——用户抱怨一句不代表要开工单，后端递选项给前端，点不点用户定；`draft` 预填描述和类型，点了不用再问一遍。投诉和闲聊**零模型调用**，命中即返回固定话术
- **main_agent**：一次 ReAct 推理步，返回三个键——`messages` 走 add_messages 追加，`steps`/`tokens_used` 普通标量手写累加（`state.get(...) + 1`，土但明确表达「读旧值、加一、写回」）
- **resolve_answer**：答复两个来源统一——确定性节点写在 `state["answer"]`，Agent 答复在最后一条 AIMessage 上；接口层和日志层都调它，不用各自判断走哪条路
- **log_node 兼两职**：写一行完整留痕 + 落 MySQL 一条 assistant 消息。所有出口都连到它，这两件事一定发生——留痕落库不能指望每个节点自觉

### 运行时

- **checkpointer**：LangGraph 持久化机制，按 `thread_id` 存 State，下次同 thread_id 接着跑；本项目直接拿 `conversation_id` 当 thread_id。`_cm` 模块级变量必须留着——`AsyncSqliteSaver.from_conn_string` 给的是异步上下文管理器，手动 `__aenter__` 后不持有它，对象被回收连接就断了，症状是跑着跑着数据库连接莫名其妙没了
- **`_graph_input` 存在的唯一理由**：State 按会话持久化，无 reducer 的标量字段跨轮残留——上一轮投诉的 `answer` 和 `suggested_actions` 串到本轮物流问答（走 Agent 路不写 answer，`resolve_answer` 读到上一轮的安抚话术）。症状「上一轮的东西冒出来了」，每个节点单独看都没毛病。判据：`messages` 有 reducer 不清，`steps`/`tokens_used` 本轮预算每轮归零，`trace` 走 None 哨兵，**其余输出型标量一律清空**——这份清零列表要跟着 State 长，加新输出字段忘清就开坑
- **四个入口**：run_turn / stream_turn（新一轮）+ resume_turn / stream_resume（第 6 章中断后续跑）。新一轮先 `_ensure_conversation`，会话不存在抛 `ConversationNotFound`；接口层分开看：非流式 `/api/agent` 翻 404，SSE 接口这时已 200 开流改不了状态码，只能吐 `event: error` 帧
- **`_stream_events` 的 ANSWER_NODES 白名单**：图里调模型的节点不止一个——意图分类、Query 改写、证据自评全调，这些输出全不该上用户屏幕。不加白名单用户会看到「商品咨询」「订单配送时效是多久」这些内部产物混在答案里蹦出来。确定性节点（script/complaint/fallback）没调模型，没有 token 可逐吐，整块话术当一个 delta 发；前端两种都当 delta 处理看不出区别
- **dedup_actions**：ReAct 环可能走好几轮，每轮模型都可能提议同一个动作——前端收到两个一模一样的「建工单」按钮很难看，攒到流末尾统一按 type 去重再发，这也是 actions 帧不在中途发的原因

### 验收怎么写

- 验收「ReAct 顺序多步」：问「我手机尾号1001那个订单发货没？到哪了？」，断言 `{"query_order", "query_logistics"} <= tool_calls 名集`——单轮 Function Calling 做不到，能过说明 ReAct 环真的转起来了
- 走 `/api/agent` 非流式（看得到 tool_calls 轨迹），流式接口只给帧
- **每题独立会话**：共用一个会话，前一题问订单 1001，后一题判断被这段历史影响，断言时灵时不灵，查半天以为是代码问题
- **Agent 端到端验收本来就不百分之百确定**——同一道题跑两遍可能一次调两个工具、一次只调一个。要写在报告里，而不是反复重跑到全绿再截图

---

## 十、实战要点

需求八条：① 祛魅热身——先手写最裸的 Agent 循环（看清就是带工具的循环）再 LangGraph 重构；② 图骨架按流程搭（消解→意图→分流→检索→置信度闸→Agent→日志）；③ 分流写死：知识类（商品咨询、退款退货）强制 RAG + 置信度闸、业务类（物流订单售后）不预检索直进 Agent、投诉不进 Agent 出安抚+两可选项、闲聊固定话术零模型调用；④ 主力 Agent ReAct 循环（简单一步收敛、复杂按中间结果多步、缺信息追问），复用第 2 章工具；⑤ LangGraph State + checkpointer；⑥ 两节点先放最简（指代消解透传、意图识别简单 prompt 七类 JSON）；⑦ 置信度闸卡在检索后、进 Agent 前（流式答完再判就晚了）；⑧ 转人工/建工单是两件事分开做，都交前端自选、后端不自动执行。

验收五条：① 政策类问题日志见强制检索节点；② 订单物流问题 Agent 自调工具；③ 投诉出两个独立按钮，转人工前端模拟、建工单才写 tickets 表；④ 闲聊拿固定话术；⑤ 复杂问题 ReAct 走不止一步。

**关键决策**：
- checkpointer 选 **AsyncSqliteSaver**：LangGraph 自带 checkpointer 只有 InMemory/Sqlite/Postgres，**无官方 MySQL 版**；业务库虽是 MySQL，取「自带 + 生产级持久化」的 sqlite 版，与 MySQL 业务库解耦
- **强制 RAG 的原因**（实战验证）：第二章遇到过——Agent 自己「自觉」去调工具查知识库，有时就不去查直接回答，导致乱答幻觉；智能客服高可信场景乱答伤害大，所以 Workflow 强制检索、喂知识给 Agent，可靠性和泛化性都拿到
- **create_ticket 拦截为提议**：Agent 判断合适时**不写库**，把 args 转成「建工单」可选项存 suggested_actions，回一条合成 ToolMessage 让模型收敛；真正写库只在按钮端点 `POST /api/actions/create-ticket`
- **query_logistics 造真实依赖**：为让验收 5「先查订单再查物流、ReAct 走不止一步」真实成立（否则两工具都吃 order_id，模型会并行一步调俩），把入参从 `order_id` 改为 `tracking_no`，而 `tracking_no` 只能从 `query_order` 的返回取到——形成真实数据依赖

---

## 十一、本章小结

- **分工**：Workflow 把硬约束焊进轨道（强制检索、置信度兜底、投诉零模型），主力 Agent 靠 ReAct 临场判断（调哪个工具、走几步收敛）
- **祛魅**：Agent = 带工具清单的 for 循环；LangGraph 只是把它放进更大的图编排
- **三问题**：全交给 Agent → 排查难、漏流程、响应慢；确定性骨架正好治这三样
- **图编排**：add_node/add_edge/add_conditional_edges + 共享 State；checkpointer 按 thread_id 持久化
- **踩得最多的坑**：Annotated reducer 通道 vs 标量覆盖、merge 通道 None 哨兵、_graph_input 每轮清零、ANSWER_NODES 白名单防内部产物漏到前端

骨架搭完，图上还留着几个先点名没细讲的节点——下一章打开指代消解和意图识别，以及退款这种必须中途停下来问用户的流程怎么表达。

---

## 附：本章踩坑记录

| 坑 | 现象 | 解法 |
|---|---|---|
| 标量字段跨轮残留 | 上一轮投诉的 answer 串到本轮物流问答 | `_graph_input` 每轮显式清空输出型标量 |
| merge 通道清不掉 | 传空字典 trace 不重置 | 入口传 `None` 哨兵，约定写进 docstring |
| 客户端被回收 | 跑着跑着 checkpointer 连接没了 | 持有 `_cm` 上下文管理器对象 |
| 内部产物漏到前端 | 用户看到「商品咨询」「改写后的标准问法」 | ANSWER_NODES/DETERMINISTIC_ANSWER_NODES 白名单 |
| actions 重复 | 前端收到两个一模一样建工单按钮 | 流末尾 dedup_actions 按 type 去重 |
| 分流表漂移 | 某类意图静默走错出口，日志无异常 | INTENT_TO_ROUTE 单一来源，值与条件边键对齐 |
| 评估断言时灵时不灵 | 前一题历史污染后一题判断 | 每题独立会话 |
| 验收重跑到全绿 | 掩盖模型非确定性抖动 | 如实重跑记录，写进报告 |
| 模型并行调两个工具 | 验收「顺序多步」不成立 | query_logistics 改吃 tracking_no，形成真实数据依赖 |
