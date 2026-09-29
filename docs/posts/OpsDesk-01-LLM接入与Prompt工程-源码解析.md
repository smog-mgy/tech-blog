# 第 01 章：LLM 接入与 Prompt 工程（源码解析）

**日期**：2026-08-12
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 01 章：LLM 接入与 Prompt 工程（项目落地笔记）.md`
> 本解析逐段走读模型工厂、流式用量修正与型号机械闸。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/core/llm.py` | 模型工厂（所有模型调用收口）、流式用量修正 |
| `app/core/model_guard.py` | 型号机械闸（答案里的型号必须逐字来自证据） |
| `app/core/prompts.py` | 系统 Prompt 集中管理 |
| `app/config.py` | 配置（.env → pydantic-settings） |

## llm.py 逐段走读

### _diff_usage：把累计用量换成增量

```python
def _diff_usage(cur: dict, prev: dict) -> dict:
    out: dict = {}
    for k, v in cur.items():
        p = prev.get(k)
        if isinstance(v, dict):
            out[k] = _diff_usage(v, p if isinstance(p, dict) else {})
        elif isinstance(v, (int, float)):
            out[k] = max(0, v - (p if isinstance(p, (int, float)) else 0))
        else:
            out[k] = v
    return out
```

- **递归**：`usage` 里可能有嵌套结构（`*_details` 等），逐层同样处理
- 数值：`当前值 - 上一个 chunk 的值`，`max(0, ...)` 防负
- 非数值字段原样透传

### _CumulativeUsageChatOpenAI：问题的根源与修法

```python
class _CumulativeUsageChatOpenAI(ChatOpenAI):
    _prev_usage: dict = PrivateAttr(default_factory=dict)

    def _convert_chunk_to_generation_chunk(self, chunk, default_chunk_class, base_generation_info):
        usage = chunk.get("usage") if isinstance(chunk, dict) else None
        if usage:
            prev = self._prev_usage
            if any(isinstance(v, (int, float)) and v < prev.get(k, 0)
                   for k, v in usage.items() if not isinstance(v, dict)):
                prev = {}
            chunk = {**chunk, "usage": _diff_usage(usage, prev)}
            self._prev_usage = usage
        return super()._convert_chunk_to_generation_chunk(
            chunk, default_chunk_class, base_generation_info)
```

docstring 把问题说透：

- **现象**：有些 OpenAI 兼容通道在**每个 chunk 上都重报一遍累计用量**，而 langchain-openai 把各 chunk 的用量**相加**——两件事凑一起，一次调用的 token 数被放大到 chunk 条数倍（实测 24 个 chunk、input 恒为 11，聚合出 264）
- **影响**：ch09 成本账按这个数统计整体虚高一个量级；ch05 早先的 token 预算闸因此第一步就跳闸，工具从没执行过
- **开关救不了**：`stream_usage=False` 时上游照发、库照加

修法三要素：

1. **入口拦截**：在 `_convert_chunk_to_generation_chunk`（chunk 转换入口）把累计值换成增量再交给上游逻辑去加——加完正好等于最后一个 chunk 的累计值
2. **`_prev_usage` 用 `PrivateAttr`**：pydantic 私有属性，不进序列化/不进 model dump，是纯运行态状态
3. **自愈逻辑**："任何一项变小 = 上一条流已结束，这是新一条流的第一个 chunk，基准清零"——同一实例被复用（结构化输出的链会多次 invoke）时不会把上一流的基数带过来算错

规范通道（只在末尾报一次用量）不受影响——增量就等于它本身。

### get_chat_model：所有模型调用的收口

```python
def get_chat_model(streaming: bool = False, model: str | None = None,
                   temperature: float | None = None) -> ChatOpenAI:
    return _CumulativeUsageChatOpenAI(
        model=model or settings.chat_model,
        base_url=settings.chat_base_url,
        api_key=settings.chat_api_key,
        streaming=streaming,
        stream_usage=True,
        temperature=0.3 if temperature is None else temperature,
        **_thinking_kwargs(),
    )
```

逐点拆：

- **`model or settings.chat_model`**：显式覆盖模型名（意图识别可配更大模型求准），None 回落配置
- **`stream_usage=True`**：docstring 点破——"流式也回传 token（等效 `stream_options.include_usage`），否则 Langfuse 按意图统计只有非流式调用的账，主力 Agent 全漏"。**主力 Agent 是流式的，不把 usage 收进来，成本账就是残缺的**
- **`temperature=0.3` 默认**：答用户的话要有点人味；但 docstring 记了一个关键例外——"**当评委用的链路要显式传 0**：同一份证据+同一份答案，0.3 下重放四次给出过 5/6、5/6、6/6、6/6 三种结果，量出来的分数里就混进了采样噪声。评估要的是可复现，不是多样性"。**评估链路 temperature=0 是硬规则**
- **`_thinking_kwargs()`**：把三项思考链配置拼成参数，留空的不传（交给上游默认）——配置与代码解耦

## model_guard.py 逐段走读

### 为什么这道闸是机械闸

docstring 开头就定调：

```
ch04 评估里判出的唯一一条真幻觉是型号:库里是 MH-AC30,答案写成了 MH-CAD1——
一个不存在的型号。这类错误的特点是机械可判:型号是封闭集合,答案里的每个型号
串要么在证据里出现过,要么就是模型自己拼的。判它不需要再调一次大模型,正则就够,
所以别把这件事交给忠实度裁判(裁判贵、还会漏)。
```

- **型号是封闭集合**：答案里的每个型号要么在证据里，要么是编的——正则就能判，不需要再调一次大模型
- 和 ch09 读图小注里的数字校验是同一手法：**能机械校验的，就不要用模型校验**（裁判贵、还会漏）

### 三个函数

```python
MODEL_RE = re.compile(r"MH-[A-Za-z]{1,4}\d{1,4}")

def models_in(text: str) -> list[str]:
    seen: dict[str, None] = {}
    for m in MODEL_RE.findall(text or ""):
        seen.setdefault(m, None)
    return list(seen)

def unsupported_models(answer: str, evidence: str) -> list[str]:
    allowed = set(models_in(evidence))
    return [m for m in models_in(answer) if m not in allowed]

def repair_hint(bad: list[str]) -> str:
    return (
        "上一版回答里这些型号在给你的证据里找不到:" + "、".join(bad) + "。"
        "请重写回答:型号必须逐字复制证据里出现过的型号串,证据里没有的型号一个都不要写,"
        "拿不准就不提型号。其余内容与引用编号保持不变。"
    )
```

- **`MODEL_RE`**：只认「MH-字母-数字」一种编号形态（MH-AC30 / MH-W40 / M-1001），这是本项目设备型号的写法——封闭集合的前提是格式收拢
- **`models_in`**：按出现顺序去重（dict 当有序 set 用）
- **`unsupported_models`**：答案里有、证据里没有的型号；空列表 = 这一关过了——**这一关的判定逻辑就是集合差，零模型调用**
- **`repair_hint` 不替它猜**：只告诉它哪几个型号没依据，不替它猜正确型号——"猜是幻觉的来源"。重写指令精确：型号必须逐字复制、没有就不写、拿不准不提，其余内容保持不变（防止重写把别的地方也改坏）

## 与 prompts.py / config.py 的衔接

- **prompts.py**：三个系统 Prompt（对话行为约束 / 提取 / 意图）集中管理，模型行为怪癖先在 Prompt 里堵源头（不传 "null"、不承诺时效、不代转交），代码兜底是第二道防线
- **config.py**：base_url / model / api_key 全从 `.env` 来（pydantic-settings），换上游只改配置不改代码；选型认 OpenAI 协议（各家兼容的"普通话"）

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| `_diff_usage` 入口换增量 | 兼容通道每 chunk 重报累计用量，token 放大到 chunk 条数倍 |
| 用量变小 = 新流开始，基准清零 | 同一实例被复用时不自愈算错 |
| `stream_usage=True` 收口 | 流式主力 Agent 的 token 不进成本账就残缺 |
| 评估链路 temperature=0 | 消除采样噪声，评估可复现 |
| 型号机械闸（正则集合差） | 能机械校验的不调模型，裁判贵还会漏 |
| `repair_hint` 不猜型号 | 猜是幻觉的来源 |
