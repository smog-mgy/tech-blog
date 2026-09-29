# 第 09 章：可观测性与数据飞轮（源码解析）

**日期**：2026-09-13
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 09 章：可观测性与数据飞轮（项目落地笔记）.md`
> 本解析逐段走读 Langfuse 挂载层与飞轮流水线，讲清每个分支为什么这么写。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/core/observability.py` | Langfuse 挂载与 trace 标注，全部可选降级 |
| `app/core/flywheel.py` | 飞轮流水线：问题标准化 + 查重 → 待审队列 |
| `app/core/jobs.py` | 定时任务调度（评估、飞轮批处理） |
| `app/api/rageval.py` | 评估流水线 API |
| `app/api/observability.py` / `admin.py` / `review.py` | 观测查询、管理端、审核端 |
| `data/ch09/reports/eval_trend.txt` | 评估趋势（实测数据） |

## observability.py 逐段走读

### 启用条件：三个环境变量全齐才启用

```python
def langfuse_enabled() -> bool:
    return bool(settings.langfuse_public_key and settings.langfuse_secret_key
                and settings.langfuse_base_url)
```

- public_key / secret_key / base_url 三件套缺一不可
- 走 `settings`（pydantic-settings，.env 注入），不读 `os.environ`——项目配置统一走配置层，跟官方 README 的姿势不同，是刻意为之
- **未启用时所有对外函数必须安全 no-op**（模块 docstring 明说："观测是增强,不是依赖"）

### 单例初始化

```python
_client = None

def _init_client():
    global _client
    if _client is None:
        from langfuse import Langfuse
        _client = Langfuse(
            public_key=settings.langfuse_public_key,
            secret_key=settings.langfuse_secret_key,
            base_url=settings.langfuse_base_url,
        )
    return _client
```

- 懒加载单例，进程内复用
- 注意构造参数是 **`base_url` 而非 `host`**——实装 SDK 是 langfuse 4.x，`host` 已弃用（网上旧教程全写 host，照抄报错）
- import 放在函数内部：未启用时根本不 import langfuse，进程里不背这个依赖

### CallbackHandler：run_inline 是关键

```python
def _make_handler():
    from langfuse.langchain import CallbackHandler

    class _InlineCallbackHandler(CallbackHandler):
        """run_inline=True:让 LangChain 在调用方协程内联执行回调,而不是丢进独立 task。
        没有它,handler 的 OTel context.attach 挂在别的 task 上,节点代码里没有活动
        span 上下文,tag_intent 的 propagate_attributes 写不进当前 trace(实测踩坑)。"""
        run_inline = True

    return _InlineCallbackHandler()
```

这个子类是整个可观测层最容易踩的坑。LangChain 默认把回调调度到独立 task 异步执行，**但 OTel 的 context.attach 是协程绑定的**——挂到别的 task 上，节点代码里就没有活动 span 上下文。此时你调 `propagate_attributes` 想给"当前这条 trace"打标签，实际写不进去。强制 `run_inline=True` 让回调在调用方协程内联执行，上下文才对齐。

### attach_observability：编译时挂一次，节点零侵入

```python
def attach_observability(graph):
    if not langfuse_enabled():
        return graph
    _init_client()
    ...
    graph.add_handler(_make_handler())   # 全图自动 trace
    return graph
```

- 图编译后挂一次 handler，整条 LangGraph 的节点调用自动进 trace——**节点业务代码一行不用动**（README 原话："编译时挂一次，节点里一行不用动"）
- 未启用时原样返回 graph，不挂、不 import

### get_langfuse：成本脚本的查询入口

```python
def get_langfuse():
    if not langfuse_enabled():
        return None
    return _init_client()
```

成本统计脚本用 `client.api` 查 token 用量（`cost-by-intent`）。返回 None 时调用方要自己处理"没配观测栈就没有成本数据"。

## flywheel.py 逐段走读

### 一次模型调用干两件事

```python
class NormalizeResult(BaseModel):
    normalized_question: str = Field(description="FAQ 式标准问题")
    matched_question_id: int | None = Field(default=None, description="命中候选 id,无同类为 null")
    ai_suggested_answer: str = Field(default="", description="示例答案备查")

async def normalize_and_match(raw_question: str, candidates: list[dict]) -> NormalizeResult:
    cand_text = "\n".join(
        f"- id={c['id']}: {c['normalized_question']}" for c in candidates) or "(无候选)"
    return await _chain().ainvoke({"raw_question": raw_question, "candidates": cand_text})
```

- structured output 让模型一次输出三件事：**标准问法 + 命中哪个候选 + 示例答案**
- 候选以 `id=...: 标准问法` 的文本形式喂给模型，它就是"查重字典"
- 候选最多 200 条（下面讲截断判断）

### process_pending：批处理主体

```python
async def process_pending(limit: int = 50) -> dict:
    rows = await repository.fetch_unmatched_low_conf(limit)
    stats = {"processed": 0, "merged": 0, "created": 0, "skipped": 0}
    for row in rows:
        # 每条现拉:同批新建的行进得了候选;多拉 1 条用于判断是否真被截断(恰好 200 不误报)
        fetched = await repository.list_review_candidates(limit=201)
        truncated = len(fetched) > 200
        candidates = fetched[:200]
        try:
            r = await normalize_and_match(row.raw_question, candidates)
        except Exception:
            logger.warning("flywheel 标准化失败 lcq=%s(跳过,下轮重试)", row.id, exc_info=True)
            stats["skipped"] += 1
            continue
        mid = r.matched_question_id
        if mid is not None:
            if not any(c["id"] == mid for c in candidates):
                logger.warning("flywheel 幻觉 id=%s lcq=%s(候选里不存在,跳过下轮重试)", mid, row.id)
                stats["skipped"] += 1
                continue
            await repository.increment_occurrence(mid)
            review_id = mid
            stats["merged"] += 1
        else:
            review_id = await repository.insert_review_item(
                r.normalized_question, r.ai_suggested_answer or None)
            stats["created"] += 1
        await repository.set_matched_review(row.id, review_id)
        stats["processed"] += 1
```

逐点拆：

1. **游标**：`fetch_unmatched_low_conf` 只拉 `matched_review_id IS NULL` 的行——处理完回写，**天然幂等可重跑**
2. **每条现拉候选（limit=201）**：两个意图——(a) 同批新建的行要进得了候选（串行逐条，第二条能命中第一条刚建的）；(b) **多拉 1 条判断真截断**：`len(fetched) > 200` 才是真截断，恰好 200 条不误报。截断时打日志"查重覆盖不全"
3. **标准化失败**：跳过 + 告警，游标留在原地下轮重试——绝不静默丢弃
4. **幻觉 id 防御**：模型报的 `matched_question_id` 必须真存在于候选列表，否则视为幻觉——模型会编 id，不信它，跳过下轮重试
5. **命中 → 累加 occurrence_count**：模块 docstring 写明"命中任何状态的候选都只累加（驳回即终审，不复活）"——被驳回的缺口不再复活成新待审
6. **未命中 → 新建待审条目**：带 `ai_suggested_answer`（示例答案备查），人工审核时参考
7. **回写归并落点**：`set_matched_review(row.id, review_id)`，游标推进

### 批处理语义（模块 docstring 原文要点）

- 定时批处理，不做近实时（用户拍板）
- 串行逐条：同批同义问题第二条能命中第一条刚建的行，不重复建缺口
- 命中任何状态的候选都只累加 occurrence_count
- 解析失败/幻觉 id：该条跳过并告警，游标留在原地下轮重试

## rageval 与评估趋势

评估流水线（`app/api/rageval.py`）产出四个指标，落 `eval_runs` 表连趋势：

- **Recall@5**：检索召回
- **MRR**：排序质量
- **Faithfulness**：回答忠实度（具体事实主张可被证据支撑）
- **拒答率**：库外问题必须被拒

`data/ch09/reports/eval_trend.txt` 实测数据：

```
# 5 08-06 10:20 手动   Recall@5=0.986  MRR=0.897  Faithfulness=1.000  拒答率=0.983
# 4 08-06 10:16 定时   0.986           0.897 ⚠↓  1.000               0.983 ⚠↓
# 2 07-17 10:11 定时   —               0.972      1.000               1.000
# 1 07-17 10:10 手动   —               0.972      1.000               1.000
```

读法：**轮次 5 相对轮次 4 四指标持平——飞轮写回没把质量拉下来**；`⚠↓` 标注的是指标相对上一轮的小幅回落（0.897 相对 0.972），用趋势而非单点判断质量。触发方式有手动和定时两种（jobs.py 调度）。

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| 三环境变量全齐才启用 + 全函数 no-op | 没配观测栈系统照常跑，观测是增强不是依赖 |
| `run_inline=True` | OTel context 与当前 trace 对齐，标签写得进去 |
| `base_url` / `propagate_attributes`（4.x API） | 版本迁移后 API 正确，不踩旧教程坑 |
| `matched_review_id IS NULL` 游标 | 批处理幂等可重跑 |
| 每条现拉候选 + limit=201 | 同批新建可见 + 恰好 200 不误报截断 |
| 幻觉 id 防御 | 模型编的候选 id 不落库 |
| 评估趋势连飞轮 | 每次补知识都在指标上验证，不让质量悄悄退化 |
