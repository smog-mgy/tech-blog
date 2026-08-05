# 学习笔记 02｜Function Calling 工具链：让模型学会"查数据"

**日期**：2026-06-12
**标签**：AI Agent · Function Calling · 工具链

> 上一章收工，客服能聊天了，但用户一句「我上周买的蓝牙耳机怎么还没到？」就露馅——订单数据躺在公司数据库里，模型的知识是训练时固化进参数的，它上哪知道你家昨天的订单？这一章给客服装上手脚：从「会聊天」变成「能查数据、能办事」。

---

## 一、为什么需要 Function Calling

用户问订单，模型只剩两条路：
- **诚实**：「抱歉，我无法查询您的订单信息」→ 用户扭头去找人工
- **不诚实**：一本正经编「您的订单预计明天送达」→ 编得越流畅，客诉来得越快

把订单数据塞进 Prompt？行不通：
- 订单是**活数据**，状态随时在变，塞进去的那一刻就开始过期
- 全库几十万条订单，上下文窗口塞得下吗？

**正确的姿势**：数据别动，让模型开口「要」。它发现自己缺订单信息，就说一声「帮我查一下这个手机号的单」，我们的代码去取数据、把结果递回给它，它再组织语言回答。**模型出的是大脑判断，代码出的是手脚。**

---

## 二、Function Calling 原理：模型只张嘴，不动手

先破除最大误区：**模型从头到尾没有执行过任何代码**。它做的唯一一件事是输出一段结构化文本：「我想调用某某工具，参数是某某」。真正执行函数的是我们自己的程序。

类比：新客服工位上贴着一张内线清单——查订单打 8001、查物流打 8002、转工单打 8003。模型是那个客服，工具函数是电话那头的系统。

**安全边界**也顺带清楚了：模型能碰哪些数据、能做哪些操作，完全由我们递给它的工具清单说了算。没给它删库的工具，它说破天也删不了库。

### 流程四步（模型出场两次）

1. 模型从用户话里识别意图（要查订单）
2. 生成结构化工具调用请求（函数名 + 参数）——这就是「申请单」
3. 我们的代码执行函数，拿到真实数据
4. 结果「回灌」给模型，它据此组织给用户的回答

### 协议层面：三份 JSON

**① 说明书（tools 数组，随请求发给模型）**

```json
{
  "type": "function",
  "function": {
    "name": "query_order",
    "description": "根据订单号或下单手机号查询订单的状态、商品与金额",
    "parameters": {
      "type": "object",
      "properties": {
        "order_no": {"type": "string", "description": "订单号，形如 SO20260625001"},
        "phone": {"type": "string", "description": "下单时使用的 11 位手机号"}
      },
      "required": []
    }
  }
}
```

- `name` 工具名；`description` 告诉模型这工具干什么、什么时候用；`parameters` 用 JSON Schema 描述参数（就是参数的"格式合同"）
- **这份说明书就是会塞进上下文的 Prompt**，模型每次回答前先翻一遍，判断用不用工具、用哪个。所以 `description` 写得好不好，直接决定模型会不会在该出手时出手

**② 申请单（模型回复）**

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [{
    "id": "call_7f3a",
    "type": "function",
    "function": {"name": "query_order", "arguments": "{\"phone\": \"13800001234\"}"}
  }]
}
```

两个细节：`content` 是空的（模型这轮没说人话，只提交取数申请单）；`arguments` 是**字符串包着的 JSON**，拿到手得再解析一层——头一回对接几乎人人踩的坑。

**③ 结果单（我们回灌）**

```json
{
  "role": "tool",
  "tool_call_id": "call_7f3a",
  "content": "{\"order_no\": \"SO20260625001\", \"status\": \"已发货\", \"item\": \"蓝牙耳机\"}"
}
```

`tool_call_id` 必须跟申请单的 `id` 对上，模型才知道这份结果回应哪次调用。

**本质**：Function Calling 是一种消息格式的约定 + 一轮额外的对话往返。

---

## 三、打地基：项目骨架与四张表

- Web 层 FastAPI，数据层 SQLAlchemy 2.0 异步 + MySQL（Docker 起）
- 商品、订单、物流：真实生产里在电商/物流系统的 API 里，客服系统只管调接口拿数据；**本项目演示起见，在工具内部随机生成数据，不接真实接口、不建表**
- 真正落库四张表：

| 表 | 存什么 | 伺候谁 |
|---|---|---|
| `faq` | 问答对：问题、答案、分类 | `query_faq` |
| `conversations` | 会话壳：谁什么时候开启、处理状态 | 对话服务 |
| `messages` | 消息流水：每条消息的角色与内容 | 对话服务 |
| `tickets` | 人工工单：工单号、关联会话、问题、类型、状态 | `create_ticket` |

**设计要点**：
- `conversations` 和 `messages` 拆两张、一对多：消息是流水，会话是流水的壳。做转人工、做工单都要引用「这通会话」，全捏在消息表里就没有稳定的东西可指
- `messages.role` 对齐协议：`user` / `assistant` / `tool`。工具调用的申请单和结果单也是消息，原样落库，一通对话就能完整回放——后面可观测性章节，这些流水是排查问题的第一手材料
- `content` 字段**允许为空**：模型只发工具调用不说话时，正文本来就没有。设成 NOT NULL 第一次跑通工具调用就插入失败
- DDL 顶部 `SET NAMES utf8mb4` 别删：docker mysql client 默认 latin1，会把中文 ENUM 值 double-encode 成乱码，报错还指不到这里

---

## 四、五个业务工具的设计

### 三条设计原则

1. **一个工具只管一件事**。「查订单」和「查物流」别合成「查订单相关信息」，工具边界越清楚，模型选起来越不犯迷糊
2. **参数宁少勿多**。每个参数都得让模型有地方取值（用户的话或上下文），模型凭空变不出参数
3. **进出参都为「模型读得懂」服务**。工具的使用者是模型，返回一堆裸 ID 和内部枚举码，它没法跟用户交代

### query_order：订单查询

- 进参：订单号、手机号都可选，但**至少给一个**——用户多半报不出单号，会说「用 138 那个手机号买的」
- 出参：**按订单列表返回**。手机号下常挂好几个单，模型看到多条会自己追问「您问的是哪一单」，这层交互不用写一行分支逻辑
- **查无此单返回空列表 + 明确说明**（「未查询到相关订单」），别丢 null 或空串——结果越含糊，模型越容易自由发挥，含糊就是给幻觉留门缝

### query_product：商品查询

- 进参：名称关键词 + 分类，接住用户两种问法（「XX 有货吗」/「你们 XX 都有什么」）
- 出参：命中太多要**限条数**（如最多 10 条），超出截断并注明「还有更多商品，建议引导用户缩小范围」——把「数据太多」这个状态明明白白告诉模型

### query_logistics：物流查询

- 为什么有了 query_order 还要它？订单查询答「买了什么、什么状态」，物流查询答「货现在到哪了」。「到哪了」是头号高频问题，单独成工具路径更短；且二者数据本就在两个系统
- 进参只收订单号。用户报手机号催物流怎么办？本章单轮系统只能开一次单，模型只能先追问单号（后面章节处理）

### query_faq：政策与常见问题查询

契约只有一进一出：进用户问题字符串，出答案文本。内部用 SQL LIKE 模糊匹配：

```sql
SELECT question, answer FROM faq
WHERE question LIKE CONCAT('%', :keyword, '%')
   OR answer LIKE CONCAT('%', :keyword, '%')
LIMIT 3;
```

### create_ticket：转人工工单

四个读，这一个是写。**智能客服的设计底线是搞不定就体面交接**：用户情绪上来、问题超范围、反复查不到信息，都该有通往人工的路。出参给工单号 + 一句能直接念给用户听的确认话术。

---

## 五、@tool 装饰器：把函数亮给模型

裸调 SDK 要手写两份：函数一份、Schema 一份——函数加参数忘了同步 Schema，模型拿旧说明书调新函数，错都不知道错在哪。

LangChain 的 `@tool` 思路：**一份代码、两份产出**。

```python
from langchain.tools import tool
from typing import Annotated

@tool
def query_order(
    order_no: Annotated[str | None, "订单号，形如 SO20260625001"] = None,
    phone: Annotated[str | None, "下单时使用的 11 位手机号"] = None,
):
    """根据订单号或手机号查询订单，返回订单状态、商品与金额。

    订单号和手机号至少提供一个。用户报不出订单号时，用手机号查询。
    """
    ...
```

三个映射：**函数名 → 工具名，docstring → description，类型注解 + Annotated 中文说明 → 参数 Schema**。装饰器在定义那一刻抽取，与函数本体永远同步。

```python
print(query_order.name)         # query_order
print(query_order.description)  # docstring 内容
print(query_order.args)         # {'order_no': {'description': '...'}, 'phone': {'description': '...'}}
```

写 docstring 要换一副心态：**这段文字的读者是模型，它就是 Prompt 的一部分**。「查询订单」四个字当注释合格，当工具描述不合格。什么时候该用、参数从哪取、有什么使用限制都要写进去。

挂到模型一行：

```python
tools = [query_order, query_product, query_logistics, query_faq, create_ticket]
llm_with_tools = llm.bind_tools(tools)
```

### 参数描述的两种写法

- 参数少：`Annotated[str, Field(description="...")]` 直接写进注解
- 参数多/要复用/挂校验：独立 pydantic 模型 + `@tool(args_schema=XxxInput)`

### 模型看不见的参数：InjectedToolArg

```python
@tool
async def create_ticket(
    description: str,
    ticket_type: Literal["售后", "投诉", "咨询"],
    conversation_id: Annotated[int, InjectedToolArg],   # 系统注入，模型看不见
) -> dict:
```

凡是决定「这次调用代表谁」的参数，都不能让模型填——模型填的东西来自对话文本，而对话文本是用户可以随便写的。`InjectedToolArg` 让参数留在 args_schema 里（函数照样收到），但不进模型看到的 schema。真实的 `conversation_id` 由执行引擎调用前从可信通道补进去。

`Literal["售后","投诉","咨询"]` 会进 schema 变成枚举，模型只能从三个值里选。

---

## 六、执行链：注册、分发与容错

### 注册

`tool_calls` 里只有工具名这个字符串，一行字典按名索骥：

```python
TOOL_REGISTRY = {t.name: t for t in tools}
```

### 分发

把 `tool_call` 整个递给 `tool.invoke`，LangChain 会把 `arguments` 那层"字符串里的 JSON"解析成字典、执行函数、把返回值包成待回灌的 `ToolMessage`，连 `tool_call_id` 都替你对齐。

### 容错：工具执行失败分三种，处理各不相同

| 失败类型 | 例子 | 处理 |
|---|---|---|
| 参数不合法 | 让查订单一个参数都没给、手机号 8 位 | Pydantic 校验拦住，把校验错误**当执行结果回灌**，模型会回头追问用户 |
| 查询落空 | 订单号没查到、FAQ 没命中 | 业务上正常，**返回明确「未查到」**让模型跟用户周旋；当异常抛，前端只能给用户看「系统错误」 |
| 真故障 | 数据库连不上、查询报错 | 捕获住，包成「工具暂时不可用」回灌，模型会道歉、建议稍后再试或转人工 |

**坏消息也是有用输入**：把坏消息如实告诉模型，它一样能做体面应对，前提是服务进程自己不能跟着倒。

### 超时与重试

- **每个工具执行包超时**（`asyncio.wait_for` 几秒上限）：用户正盯着光标等回复，「查询超时了，请稍后再试」远好过转半分钟的圈
- **重试只留给暂时性故障**（网络抖一下）：业务性落空千万别重试，订单号错了查一百遍还是查不到
- **写操作不自动重试**：网络超时未必代表工单没建成，闷头重试就是两张重复工单。要么不重试、失败如实告知；要么带幂等键。本项目选不自动重试

---

## 七、结果回灌：把数据翻译给模型听

工具执行完手里是 ORM 对象，直接转字符串扔回去，token 的钱包和用户的隐私也一起扔出去了。回灌前三件事：

1. **挑字段**：只挑模型组织回答要用的（单号、状态、商品名、金额、时间）。它没拿到成本价，就永远不会把成本价念给用户听
2. **翻译语义**：数据库枚举码 `SHIPPED` / `REFUNDING` 翻译成「已发货」「退款中」，模型拿到的每个字段无歧义
3. **序列化**：`json.dumps(data, ensure_ascii=False)`，中文别转义成 `\u` 码；空结果写成明确的「未查询到」，别让模型对着空数组自行想象

`tool_call_id` 存在的理由：协议允许模型一条回复开出几张申请单（一句「帮我查下订单，顺便看看退货政策」同时唤起两个工具），结果逐个回灌全靠 id 对号入座。

---

## 八、单轮调用：全流程串起来

```python
async def chat_once(messages: list):
    ai_msg = await llm_with_tools.ainvoke(messages)
    if not ai_msg.tool_calls:                # 不需要工具，直接回答
        return ai_msg

    messages.append(ai_msg)                  # 申请单入档
    for tool_call in ai_msg.tool_calls:
        tool = TOOL_REGISTRY[tool_call["name"]]
        tool_msg = await tool.ainvoke(tool_call)   # 执行，容错做在工具内部
        messages.append(tool_msg)            # 结果单入档

    return await llm_with_tools.ainvoke(messages)  # 拿着数据组织最终回答
```

时序：模型第一次调用翻说明书 → 开申请单 → 我们按注册表执行 → 申请单和结果单一起追加进消息 → 模型第二次调用，手里有真数据了 → 组织最终回答。**两次模型调用，中间夹一次工具执行。**

**单轮边界（硬约束）**：模型拿到结果后的那次回复，万一还想再查一个？本章代码到此为止——收敛那一步故意**不 bind_tools**，模型想再申请也无从发起。这个"想接着调"的冲动，就是后面 Agent 的本质。

---

## 九、章尾翻车现场：query_faq 查了个空

faq 表里躺着「运费怎么算 → 单笔订单满 99 元包邮……」，用户问「**邮费**是多少」。

LIKE 认字面：「邮费」 vs 「运费」，字面对不上。模型只好老实说「未查询到相关信息」。「多少钱包邮」「快递费怎么收」照样落空，用户手滑打个错别字更别提。

**病根**：用户说法无穷无尽，同义词词表补到最后你维护的是一部《电商黑话大辞典》，还是补不完。下一章 RAG 用语义检索解决这个问题。

---

## 十、实战验收（本章验证方法）

1. **冒烟前置**（风险闸）：先验上游模型会不会返回结构化 `tool_calls`——绑一个 `add` 工具让模型算 23+19，`ai.tool_calls` 里有 `add` 且参数对才 GO，否则停下问用户，不自行换方案
2. **浏览器聊天页**：
   - 「订单 1001 的物流到哪了」→ 气泡出工具徽章「🔧 调用了 query_logistics」+ 按结果作答
   - 「退货政策是什么」→ query_faq 命中，答出 7 天无理由
   - 「邮费是多少」→ 徽章 query_faq 但答不出（漏召回）——**这是预期结果，如实记录留给 RAG 章**
3. **标注样例评估**（`eval_agent.py`）：「问法 → 期望工具」对照跑真实模型，如「订单 1001 的物流到哪了」→ {query_logistics}、「今天天气怎么样」→ 不调工具
4. **前端 SSE 帧约定**：`tool` 帧（徽章）→ `delta` 帧（逐字）→ `done` 帧（回传 conversation_id）→ `[DONE]`

### 编排核心设计（两个出口共用一个核心）

把「会话身份 + 落 user + turn1 定工具 + 落 assistant + 执行工具 + 落 tool」抽成共享 `_prepare_turn`：
- `stream_agent_turn`（流式）：供 `/api/chat` 前端主入口，收敛用 `astream` 逐 token 吐
- `run_agent_turn`（非流式）：供 `/api/agent` 程序化/测试出口，一次返回轨迹 + 答案

**跨轮上下文**：只回放 user 与「content 非空且无 tool_calls」的 assistant；带 tool_calls 的 assistant 常夹带 preamble，不跨轮回放避免污染续接。全部消息仍完整落库以备追溯。

---

## 十一、本章小结

- **机制**：模型出判断、代码出腿，靠说明书/申请单/结果单三份 JSON 协作；模型从头到尾没执行过代码
- **定义**：`@tool` 一份代码两份产出，docstring 就是提示词；InjectedToolArg 藏住模型不该碰的参数
- **执行**：注册表按名索骥，容错按「参数错/查落空/真故障」分级处理，超时兜底、写操作不重试
- **回灌**：挑字段、翻译语义、ensure_ascii=False 序列化
- **边界**：收敛不 bind_tools = 单轮；多轮循环是 Agent 的伏笔
- **留下的坑**：query_faq 字面匹配的语义鸿沟 → 第 3 章 RAG 的正例

---

## 附：本章踩坑记录

| 坑 | 现象 | 解法 |
|---|---|---|
| arguments 是字符串 | json 解析失败 | 记得 `arguments` 是字符串包着的 JSON，先解析再执行 |
| content 设 NOT NULL | 纯工具调用轮次插入失败 | messages.content 允许为空 |
| 中文 ENUM 乱码 | 建表后 ENUM 值乱码、插入报错指不到源头 | DDL/seed 自带 `SET NAMES utf8mb4` |
| 工具落空当异常 | 前端给用户「系统错误」 | 落空返回「未查到」结果，不是异常 |
| 写操作自动重试 | 重复工单 | create_ticket 进 NO_RETRY 集合 |
| mock 数据每次不同 | 断言没法写、文档对不上 | 随机种子用入参（`random.Random(f"order:{order_id}")`），同一入参结果稳定 |
