# 学习笔记 01｜LLM 接入与 Prompt 工程

**日期**：2026-06-06
**标签**：AI Agent · LangChain · Prompt 工程

> 项目背景：我在做一个电商 AI 智能客服系统（后端 Python + FastAPI，AI 层 LangChain / LangGraph）。
> 本章是第一站：先把「跟大模型对话」这条通路打通——说得稳、说得专业、反应快、记得住上文。
> 本章不做工具调用、不做 Agent 循环，先跑通纯对话。

---

## 一、一次对话在网络上长什么样

大模型对外就是一个跑在机房里的 HTTP 服务：你 POST 一个 JSON 过去，它回一个 JSON 回来，和调一个天气接口没有本质区别。如今最通用的形态叫 **Chat Completions**。

### 请求长什么样

```json
{
  "model": "deepseek-v4-flash",
  "messages": [
    {"role": "system", "content": "你是喵购商城的智能客服"},
    {"role": "user", "content": "到手不喜欢能退吗？"}
  ]
}
```

核心是 `messages` 数组，每条消息带一个 `role`：

| role | 含义 |
|---|---|
| `system` | 开发者塞给模型的幕后指令，用户看不见，立人设、定规矩全靠它 |
| `user` | 用户说的话 |
| `assistant` | 模型自己说过的话（下一轮要由我们把它发回去） |

### 响应长什么样

```json
{
  "choices": [{
    "message": {"role": "assistant", "content": "可以的，本店支持七天无理由退货……"},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 28, "completion_tokens": 45, "total_tokens": 73}
}
```

- `message.content`：回答本体
- `finish_reason`：`stop` 是自然说完；`length` 是被长度上限硬掐断（回答可能说到一半就断了）
- `usage`：本次调用的账单，按 **token** 计费。注意 token ≠ 字数，中文里可能一个字算一个 token，也可能半个词算一个，各家切法不同

### 最关键的设定：Chat Completions 是「无状态」的

服务器不保存任何对话，每次调用都是全新的一单。多轮对话的"记忆"全靠调用方自己攒——后面多轮对话一节会展开讲。

---

## 二、OpenAI 协议就是"普通话"

各家模型服务（DeepSeek、Qwen、GLM）连同本地运行工具 Ollama，全都提供 OpenAI 兼容接口，业内叫 **OpenAI 协议**。换上游 = 改 `base_url` + 换 API key，代码一行不用动。

目前市面上有三套协议在流通：

| 协议 | 端点 | 现状 |
|---|---|---|
| Chat Completions | `/v1/chat/completions` | 覆盖面最广，几乎所有模型服务都支持 |
| Messages（Anthropic） | `/v1/messages` | Claude 原生协议，国内厂商（智谱/MiniMax/Kimi）陆续开了兼容端点 |
| Responses API | `/v1/responses` | OpenAI 2025 年主推，国内覆盖面还很薄 |

**我的项目统一用第一套 Chat Completions**——它是我换任何一家上游都能接上的那套，把 `base_url` 指向 DeepSeek、硅基流动、本地 Ollama 都能跑。

---

## 三、从裸调 API 到 LangChain 三件套

裸调能跑通 demo，但撑不起系统：prompt 散落在代码里改一处漏三处、模型输出解析逻辑到处重复、换模型要翻工。所以我选 LangChain（1.0 系列，本仓库钉 1.3.13）。

本章用到三个组件：

| 组件 | 职责 |
|---|---|
| `ChatOpenAI` | 管调模型，把 HTTP 收发、消息拼装、异常重试收进一个对象 |
| `PromptTemplate` / `ChatPromptTemplate` | 管话术模板，固定句式 + 变量槽 |
| `with_structured_output` | 结构化输出，把"格式要求 + 校验"焊进模型调用 |

### ChatOpenAI 最小用法

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="deepseek-v4-flash",
    base_url="https://api.deepseek.com/v1",
    api_key="sk-xxx",
)
reply = llm.invoke("到手不喜欢能退吗？")
print(reply.content)
```

---

## 四、配置管理：把上游收进 .env

生产系统里模型不止一个（聊天、嵌入、重排是三件不同的事），地址、模型名、密钥三样都是配置。我把它们从代码挪进 `.env`：

```bash
# 聊天上游
CHAT_BASE_URL=https://api.siliconflow.cn/v1
CHAT_MODEL=deepseek-ai/DeepSeek-V4-Flash
CHAT_API_KEY=sk-xxx

# 嵌入（第3章建知识库用）
EMBED_API_KEY=sk-xxx        # BAAI/bge-m3

# 重排（第4章用）
RERANK_API_KEY=sk-xxx       # BAAI/bge-reranker-v2-m3

# 历史裁剪 token 预算
TOKEN_BUDGET=2000
```

**踩坑提醒**：`CHAT_MODEL` 必须写上游认的真实模型名，没有别名这一层。同一个 DeepSeek V4 Flash，官方叫 `deepseek-v4-flash`，硅基流动上叫 `deepseek-ai/DeepSeek-V4-Flash`，写错了上游回一句 `Model does not exist`。

用 pydantic-settings 加载：

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # 跟着账号走的必填，故意不给默认值：缺了在启动就报 Field required，直接指向 .env
    chat_model: str
    chat_base_url: str
    chat_api_key: str
    # 跟着代码走的调优常量，给默认值留在代码里
    token_budget: int = 2000

settings = Settings()  # 模块级单例
```

要点：`extra="ignore"` 让 `.env` 里多出来的键不炸启动；字段分"跟着账号走（必填）/跟着代码走（默认值）"两类，把配置缺失的报错时机提前到启动那一刻。

---

## 五、Prompt 工程化：把话术当资产管

真人客服团队有一整套家当：培训手册、话术库、工单表单。Prompt 工程化就是把这套管理搬进代码：

| 真人客服 | 代码对应 |
|---|---|
| 培训手册 | System Prompt |
| 话术库 | PromptTemplate |
| 工单表单 | with_structured_output |

### System Prompt 三层结构

一份像样的客服 System Prompt 至少交代三层：**我是谁、管什么、什么不能碰**。

```text
你是「喵喵优选」电商平台的智能客服「小喵」。

## 角色
- 语气亲切专业，回答简洁，中文作答，适度使用礼貌用语，不卖萌刷屏。

## 职责范围
- 解答商品咨询、订单、物流、售后（退款/换货/维修/投诉）相关问题。
- 与购物无关的话题（写代码、闲聊时政等），礼貌说明职责范围并引导回购物相关问题。

## 行为约束（必须遵守）
- 不臆造任何订单、物流、库存、价格信息；查不到就明说，并引导用户提供订单号。
- 本阶段没有查询系统的权限，涉及具体订单状态时，告知用户会转人工核实，不编造进度。
- 不承诺无法保证的赔偿或时效；退款政策表述统一为「以平台售后规则为准」。
- 用户情绪激动时先安抚再处理问题，不与用户争执。
```

关键认知：
- 模型训练时被教成**优先遵从 system 消息**，这一条等于攥在开发者手里的岗前培训
- 行为约束每条都要**反着写**（不许做什么），别指望模型自己懂分寸
- 红线必须立在 system 里、别混进用户消息——这到后面讲历史裁剪时还有第二层用意
- 但 System Prompt 说到底在"劝"，劝不住的那一小撮拦不住，事实兜底要靠后面章节的检索和拒答

### PromptTemplate：模板与业务分离

```python
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder

CUSTOMER_SERVICE_PROMPT = ChatPromptTemplate.from_messages(
    [
        ("system", CUSTOMER_SERVICE_SYSTEM),
        MessagesPlaceholder("history"),   # 多轮历史整段展开成多条消息
    ]
)
```

- 花括号是变量槽，`invoke` 时用字典填；漏填当场抛错，不会揣着空槽发请求
- `MessagesPlaceholder("history")` 是多轮对话接口：传一个消息列表进去整段展开，**而不是拼成字符串**。后面工具调用、工具结果都是消息，只有保持消息结构才装得下
- 竖线 `|` 是 LangChain 组合语法，把模板和模型串成链，数据从左往右淌

### 结构化输出：模型说人话，系统要字段

```python
from pydantic import BaseModel, Field

class AfterSalesTicket(BaseModel):
    """从用户售后描述中提取的结构化工单。"""
    order_id: str | None = Field(
        default=None, description="订单号，原文未出现则为 null，禁止编造"
    )
    request_type: RequestType = Field(description="用户诉求类型")  # 枚举兜底
    expected_solution: str = Field(description="用户期望的处理方案，一句话概括")

structured_llm = llm.with_structured_output(AfterSalesTicket)
chain = prompt | structured_llm
```

- `description` 不是注释！它会被翻译成模型看到的 schema，属于提示词的一部分
- 模型支持原生结构化输出的（OpenAI/Claude）走原生能力；不支持的自动改走工具调用方式
- 老代码里的 `PydanticOutputParser` 效果类似，但格式说明要手动拼进 prompt、文本要自己解析校验；`with_structured_output` 把两步收成一步

**一个真实的模型坑**：原文没有订单号时，模型偶尔会传字符串 `"null"` 或 `"无"` 进来。除了在提示词里写"千万不要传占位文本"，我在 pydantic 里加了一道 validator 兜底：

```python
@field_validator("order_id", mode="before")
@classmethod
def _normalize_missing_order_id(cls, v):
    if isinstance(v, str) and v.strip().lower() in {"", "null", "none", "n/a", "无"}:
        return None
    return v
```

prompt 那道是劝，validator 这道是兜，两道防线一前一后。

---

## 六、流式输出：别让用户盯着转圈

模型天生是边想边说的（一个 token 一个 token 往外蹦），非流式接口只是攒齐了才交货。流式要做的事：**生成一个就递一个**，用户看到文字逐字往外冒。

三个方案对比：

| 方案 | 特点 | 结论 |
|---|---|---|
| 轮询 | 前端每秒问一次，请求满天飞 | 聊天场景基本不考虑 |
| WebSocket | 全双工长连接，能推能收 | 我们的数据方向是单向的，没必要为单向流搭双向架子 |
| **SSE** | HTTP 原生单向推送，一条迟迟不关闭的响应 | **正合适** |

SSE 格式很简单：响应头 `text/event-stream`，正文一行行 `data:` 打头的消息、空行隔开，最后以 `data: [DONE]` 结束：

```
data: {"delta": "您"}

data: {"delta": "好"}

data: [DONE]
```

顺带一提：OpenAI/Anthropic 协议自己的流式响应本来就是 SSE 格式，从上游收到的、推给前端的本来就是一路东西。

### 流式接口的错误处理（重点）

响应头在第一帧发出去那一刻就定了，之后改不了状态码——**错误只能以帧的形式发出去，不能抛 HTTP 500**。前端靠 `event: error` 这一帧知道出事了：

```python
def _sse(payload: dict) -> str:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"  # ensure_ascii=False 不能省，否则中文变转义序列

def _sse_error(message: str):
    yield "event: error\n"
    yield _sse({"message": message})
```

---

## 七、多轮对话：每次请求都是一位新客服

**真相**：模型没有记忆，所谓上下文全是调用方自己攒的。每次请求把 system、历次 user、历次 assistant 按顺序码进 `messages`，模型现场通读一遍，才接得住"那它多少钱？"里的"它"。

assistant 的话必须发回去——不发，模型连自己上一轮说了什么都没法接。

### 历史不能无限长：两笔账

1. **钱的账**：每次请求重发全部历史，`prompt_tokens` 随轮次涨，越聊越贵
2. **容量的账**：上下文窗口有硬上限，塞爆直接报错；历史里混着噪声还会搅浑当前问题

### 裁剪：按 token 预算裁

```python
def trim_history(messages: list, budget: int) -> list:
    system, history = messages[0], messages[1:]
    while history and count_tokens(system, *history) > budget:
        history = history[2:]   # 掐掉最老的一问一答
    return [system, *history]
```

两个留神点：
- **扔要成对扔**：一问一答一起掐，留半截会打乱 user/assistant 交替节奏，有的模型服务对顺序挑剔得很
- **数 token 用 tokenizer 实算**，别拿字数瞎估

用 LangChain 现成的 `trim_messages` 更省心：

```python
from langchain_core.messages.utils import count_tokens_approximately, trim_messages

def trim_history(messages, max_tokens):
    return trim_messages(
        messages,
        strategy="last",          # 从后往前保留，最近的通常最相关
        token_counter=count_tokens_approximately,  # 近似计数，省一次真实分词
        max_tokens=max_tokens,
        start_on="human",         # 裁完从一条用户消息开头，不出现开局就是模型回话的怪结构
        allow_partial=False,      # 不切半条消息，宁可少留一轮
    )
```

`system` 永远原样保留——这就是前面说"规矩必须立在 system 里"的第二层用意：人设和红线不能跟着历史一起被裁掉。

---

## 八、代码实现走读（项目结构）

第 1 章最终的项目骨架：

```
app/
  main.py              # FastAPI 入口（装配路由）
  config.py            # pydantic-settings 读 .env
  api/chat.py          # POST /api/chat（SSE 流式对话）
  api/extract.py       # POST /api/extract（结构化提取）
  core/llm.py          # ChatOpenAI 工厂（get_chat_model）
  core/prompts.py      # Prompt 模板集中管理
  core/memory.py       # 会话存储 + token 预算裁剪
  schemas/             # pydantic 请求/响应/结构化提取模型
scripts/dev.sh         # 单入口启动脚本
tests/                 # pytest 单测
```

### 模型工厂

```python
def get_chat_model(streaming: bool = False) -> ChatOpenAI:
    """直连聊天上游。地址、模型名、密钥全从 .env 来，换上游不动这里。"""
    return ChatOpenAI(
        model=settings.chat_model,
        base_url=settings.chat_base_url,
        api_key=settings.chat_api_key,
        streaming=streaming,
        temperature=0.3,
    )
```

### SSE 对话接口

```python
@router.post("/api/chat")
async def chat(req: ChatRequest, model: BaseChatModel = Depends(get_model)):
    history = [*store.get(req.session_id), HumanMessage(req.message)]
    history = trim_history(history, max_tokens=settings.token_budget)
    messages = CUSTOMER_SERVICE_PROMPT.format_messages(history=history)

    async def event_stream():
        chunks = []
        try:
            async for chunk in model.astream(messages):
                text = chunk.content if isinstance(chunk.content, str) else ""
                if not text:
                    continue
                chunks.append(text)
                yield f"data: {json.dumps({'delta': text}, ensure_ascii=False)}\n\n"
        except Exception:
            logger.exception("上游 LLM 流式调用失败")
            yield "event: error\n"
            yield f"data: {json.dumps({'message': '上游模型暂时不可用，请稍后重试'}, ensure_ascii=False)}\n\n"
            return
        store.append(req.session_id, HumanMessage(req.message), AIMessage("".join(chunks)))
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
```

### 结构化提取接口

```python
def get_extractor() -> Runnable:
    model = get_chat_model()
    return EXTRACT_PROMPT | model.with_structured_output(AfterSalesTicket)

@router.post("/api/extract", response_model=AfterSalesTicket)
async def extract(req: ExtractRequest, extractor: Runnable = Depends(get_extractor)):
    try:
        return await extractor.ainvoke({"text": req.text})
    except Exception as exc:
        logger.exception("结构化提取失败")
        raise HTTPException(status_code=502, detail="上游模型暂时不可用，请稍后重试") from exc
```

设计细节：
- `Depends(get_extractor)` 让链每次请求现建，测试时能整条替换（`app.dependency_overrides`），不用打补丁
- 上游异常翻译成 502 + 一句人话，原始异常只进日志——上游报错文本常带内部地址和模型名
- 单测用 `FakeListChatModel` / `RunnableLambda` 替身，不打真实模型

---

## 九、实战验证（本章验收）

启动：`make dev`（uvicorn :8000）

**1. 流式对话**

```bash
curl -sN http://localhost:8000/api/chat -H 'Content-Type: application/json' \
  -d '{"session_id": "s1", "message": "你们卖猫粮吗?"}'
```
看到逐 token 的 `data: {"delta": ...}` 帧，最后 `[DONE]`。

**2. 两轮上下文**

```bash
SID="demo-1"
# 第一轮
curl -sN http://localhost:8000/api/chat -H 'Content-Type: application/json' \
  -d "{\"session_id\": \"$SID\", \"message\": \"我叫王小明，昨天买了你们的智能猫砂盆\"}"
# 第二轮：考上下文
curl -sN http://localhost:8000/api/chat -H 'Content-Type: application/json' \
  -d "{\"session_id\": \"$SID\", \"message\": \"还记得我叫什么、买了什么吗?\"}"
```
第二轮回复能复述出"王小明"和"智能猫砂盆"即通过。

**3. 结构化提取 + 标注样例评估**

预置 5 条标注好的售后样例（覆盖：有订单号退款、换货、订单号缺失、投诉、闲聊兜底），跑评估脚本：

```bash
uv run python scripts/eval_extract.py
# 期望 5/5 通过；expected_solution 人工目检合理
```

调不到 5/5 时先调 `EXTRACT_SYSTEM`（prompt 调优允许迭代），连续 3 次调不好就停下来对着样例看输出。

---

## 十、本章小结

- **协议**：Chat Completions 是"普通话"，换上游就是改 `base_url` + 模型名
- **工程化**：LangChain 三件套（ChatOpenAI / ChatPromptTemplate / with_structured_output）把调用、话术、解析收拾服帖
- **体验**：SSE 流式让回答逐字蹦到用户眼前；记住错误只能发帧、不能抛 500
- **记忆**：模型无状态，上下文靠调用方攒；历史裁剪按 token 预算、成对扔、system 永不裁
- **配置**：跟着账号走的必填无默认值，跟着代码走的留默认值；报错时机提前到启动

客服从"会聊天"到"能办事"，就差让模型学会使工具——那是第 2 章 Function Calling 的戏份，顺带要把项目骨架和数据库搭起来。

---

## 附：本章踩坑记录

| 坑 | 现象 | 解法 |
|---|---|---|
| 模型名写错 | 启动正常，第一次调用报 `Model does not exist` | `CHAT_MODEL` 写上游认的真实名，无别名层 |
| 中文变转义 | SSE 帧里中文变成 `\uXXXX` | JSON 序列化必须 `ensure_ascii=False` |
| 模型传占位符 | order_id 填了字符串 "null" | prompt 劝 + pydantic `field_validator` 兜 |
| 日志看不到 | `logger.info` 不输出 | uvicorn 默认不给应用 logger 配 handler，手动加 StreamHandler，`propagate=False` 隔离访问日志 |
| 中文编码 | Windows 下读带中文的 md/jsonl 抛 UnicodeDecodeError | 启动脚本 `export PYTHONUTF8=1`，在 Python 启动前生效 |
