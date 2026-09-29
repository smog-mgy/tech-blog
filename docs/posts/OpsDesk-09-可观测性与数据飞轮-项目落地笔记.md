# 第 09 章：可观测性与数据飞轮 —— 项目落地笔记

**日期**：2026-09-12
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及源码：`app/core/observability.py`、`app/core/flywheel.py`、`app/core/jobs.py`、`app/api/observability.py`、`app/api/rageval.py`、`app/api/admin.py`、`app/api/review.py`、`data/ch09/reports/eval_trend.txt`

## 这章解决两个问题

系统跑起来了，但两个问题憋了很久：

1. **它是黑盒**。模型为什么这么答？走了哪条链、检索到什么证据、意图分对了没？出了错你只能对着日志猜。排查问题全靠撞运气
2. **答不上来的问题白答不上来**。用户问的知识库里没有，系统兜底回一句"抱歉答不上来"，这个知识缺口**没人知道、没人补**——下次用户还会踩同一个坑

这章就是给系统装上"眼睛"（可观测）和"造血"（数据飞轮）。

## 眼睛：Langfuse 接入，业务代码零侵入

Langfuse 是 LLM 可观测平台（trace 追踪、成本统计、评估都在上面）。接入姿势非常优雅：**编译时挂一次回调，节点里一行不用动**。

```python
def attach_observability(graph):
    if not langfuse_enabled():
        return graph
    _init_client()
    graph.add_handler(_make_handler())   # 全图自动 trace
    return graph
```

但"零侵入"背后全是细节，踩了三个坑：

### 坑 1：run_inline 不设，标签写不进 trace

`CallbackHandler` 默认把回调丢进独立 task 跑，`OTel context.attach` 挂在别的 task 上——节点代码里**没有活动 span 上下文**，你想给当前 trace 打标签（比如"这条是报修意图"），`propagate_attributes` 写进去的是空气。

解决：子类强制 `run_inline = True`，让 LangChain **在调用方协程内联执行回调**，上下文才跟得上当前 trace。

### 坑 2：Langfuse 版本迁移，API 换名

实装时 SDK 是 langfuse 4.x：构造参数用 `base_url`（`host` 已弃用）；给运行中的 trace 补 metadata/tags 用 `propagate_attributes` 上下文管理器（v3 的 `update_current_trace` 已移除）。网上教程大半是旧 API，照抄就报错。

### 坑 3：没配 Langfuse，系统不该崩

本地没搭观测栈时，系统必须照常跑。所以**所有对外函数在未配置时都是安全 no-op**：

```python
def langfuse_enabled() -> bool:
    return bool(settings.langfuse_public_key and settings.langfuse_secret_key
                and settings.langfuse_base_url)
```

三个环境变量齐了才启用；没齐就不挂、不 import langfuse。**观测是增强，不是依赖。**

另外配置走 pydantic-settings（.env），不依赖 `os.environ`——这也是跟官方 README 姿势不同的地方，官方让你设环境变量，项目里统一走配置层。

### 成本账怎么算

第 1 章埋的流式 token 计量坑，在这里收账。成本统计按意图维度算（`cost-by-intent`），数据源是 Langfuse 的 `client.api` 查询。如果 token 用量还是那个"24 个 chunk 累加出 264"的虚高数，成本账就是错的——所以第 1 章的 `_CumulativeUsageChatOpenAI` 是这章成本准确的前提。

## 造血：数据飞轮

飞轮思路一句话：**把"答不上来的问题"变成"知识缺口清单"，人审核后补进知识库，下次就能答**。三件事：

### 入口：哪些问题会进池

三个来源：

1. **检索低置信**：知识路证据闸判定"证据弱"走兜底时，把用户的原始问题落池（`fallback_source="retrieval_low_conf"`）
2. **自检不过**：模型自检发现问题时落池
3. **用户 👎**：用户对回答点踩时落池

统一进 `low_confidence_questions` 表，这就是"问题池"。

### 流水线：标准化 + 查重 → 待审队列

`process_pending` 是飞轮主体，逐条处理池内问题：

1. 拉候选：`list_review_candidates(limit=201)`——多拉 1 条用于判断是否真被截断（恰好 200 不误报）
2. **一次模型调用**标准化 + 查重：输出 `{normalized_question, matched_question_id, ai_suggested_answer}`——把"原问题整理成 FAQ 式标准问法"和"有没有同类已有条目"一次搞定
3. **幻觉防御**：模型报的 `matched_question_id` 必须真在候选里，不在就跳过告警、下轮重试——模型会编 id，不信它
4. 命中 → 累加 `occurrence_count`（**驳回即终审不复活**：命中任何状态的候选都只累加次数）；没命中 → 新建待审条目（带示例答案备查）
5. 回写归并落点 `matched_review_id`，游标推进

### 批处理语义：幂等可重跑

几个设计保证它不会跑乱：

- **游标 = `matched_review_id IS NULL`**：处理完回写，天然幂等——重跑只会处理没处理过的
- **串行逐条**：同批同义问题，第二条能命中第一条刚建的行，不重复建缺口
- **解析失败/幻觉 id**：该条跳过并告警，游标留在原地下轮重试——绝不静默跳过
- **批处理，不做近实时**：用户拍板的方案，定时任务跑（`jobs.py`）

### 待审队列和人工审核

新建的条目进待审队列（`review` 表），人工在管理端审核（`admin.py` / `review.py`），通过的问题补进知识库——**飞轮的最后一跳是人的判断**，AI 只负责把缺口整理好、把重复归并掉，补不补、怎么补由人定。

## 怎么知道飞轮没把质量拉低：评估流水线

飞轮写回知识库是有风险的——万一补进去的知识是错的，检索质量就降了。所以有评估流水线（`rageval`）盯四个指标：

- **Recall@5**：检索召回质量
- **MRR**：排序质量
- **Faithfulness**：回答忠实度（回答里的具体事实主张能否被证据支撑）
- **拒答率**：库外问题必须被拒（不说胡话）

评估结果落 `eval_runs` 表连成趋势线。当前趋势文件实测：

```
# 5 08-06 10:20 手动   Recall@5=0.986  MRR=0.897  Faithfulness=1.000  拒答率=0.983
# 4 08-06 10:16 定时   0.986           0.897 ⚠↓  1.000               0.983 ⚠↓
# 2 07-17 10:11 定时   —               0.972      1.000               1.000
# 1 07-17 10:10 手动   —               0.972      1.000               1.000
```

趋势文件的读法很关键：**轮次 5 相对轮次 4 四个指标完全没动——飞轮写回没把质量拉下来**，最近通过的审核不用翻。这就是"评估连着飞轮"的意义：每一次补知识都要在指标上验证，不让质量悄悄退化。

## 这章埋过的坑

1. **run_inline 不设 → 标签写不进当前 trace**（OTel context 挂错 task）
2. **Langfuse API 版本迁移**（base_url 替代 host、propagate_attributes 替代 update_current_trace）
3. **没配观测栈就崩** → 全部可选降级，观测是增强不是依赖
4. **模型会编 id** → matched_question_id 必须真在候选里，幻觉防御
5. **候选恰好 200 被误报截断** → limit=201 多拉一条判断
6. **游标不清 → 重复处理** → matched_review_id IS NULL 幂等游标

## 怎么验证

```bash
# 起 Langfuse 观测栈 + 配 .env 三行 → 应用内走一轮对话，:3000 看 trace
make langfuse-up

# 飞轮流水线 + 评估
make flywheel            # 问题池 → 标准化查重 → 待审队列
make eval-flywheel       # 评估流水线，落 eval_runs 连趋势
make cost-report         # 按意图统计 token 花销
```
