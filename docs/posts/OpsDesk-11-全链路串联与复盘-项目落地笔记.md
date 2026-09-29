# 第 11 章：全链路串联与复盘 —— 项目落地笔记

**日期**：2026-09-24
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及：`Makefile`、`tests/`（80+ 测试文件）、`app/graph/build.py`、`docker-compose.yml`

## 一张图把整个项目串起来

写到这里，项目已经是一个完整系统。回到最初那句话——用户说"VFD-3005 变频器过载报警了，帮我报修"，这一句话现在会走过多长一条链？

```
用户输入
 → resolve_reference  指代消解（第 6 章）：把半截话补全
 → classify_intent    意图分类（第 6 章）：识别出"报修"
 → route_by_intent    分流（第 6 章）：报修 → business 出口
 → fetch_ticket       工单子流程（第 6 章）：抽工单号 → 归属校验 → 没有就 interrupt 弹选择器
 → retrieve_policy    强制检索制度（第 3 章）：不让模型凭记忆答
 → main_agent ⇄ agent_tools  ReAct 环（第 5/2/8 章）：模型决策、框架执行、MCP 查备件
   → create_ticket 确认卡（第 2 章）：确认单写操作 → 前端确认 → 执行
 → log → Langfuse trace（第 9 章）：全程可观测
```

11 章建的东西在这一句话里全部上线。**每一章都不是孤立知识点，是这条链上的一环。**

## 技术栈全景

| 层 | 技术 | 用在哪 |
|---|---|---|
| 模型接入 | OpenAI 协议 + 模型工厂 | 对话/意图/摘要/消解各用各的模型（第 1 章） |
| 编排 | LangGraph 状态图 | 整条链的骨架（第 5 章） |
| 检索 | Milvus（向量）+ BM25 + bge-reranker | 知识库混合检索（第 3/4 章） |
| 工具 | 内置 registry + MCP（:8101/:8102） | 建单/查单/备件/工单流转（第 2/8 章） |
| 存储 | MySQL + Milvus + MinIO | 会话/工单/知识库/向量（第 3 章起） |
| 观测 | Langfuse 自部署 | trace/成本/评估（第 9 章） |
| 微调 | RoBERTa-wwm-ext + ONNX | 旁路主题分类器（第 10 章） |
| 工程 | uv + Makefile + Docker Compose | 依赖/编排/一键拉起 |

## Makefile：目标即文档

项目越建越大，命令越来越多，最后用 Makefile 把它们全部收编。三个设计值得说：

1. **目标带 `##` 注释，`make help` 自动列**：每条命令自带一句人话说明，不用翻 README 猜"eval-check 是干嘛的"
2. **`export PYTHONUTF8 = 1` 放在 Makefile 顶部**：中文 Windows 默认 GBK，读知识库/评估集这些带中文的 markdown/jsonl 会抛 UnicodeDecodeError——**必须 Python 启动前生效，所以设在这里而不是 .env**。这是 Windows 上跑项目的第一个坑
3. **`--group ml` 隔离重依赖**：ch10 的 torch/transformers 几个 G，只有训练/导出才需要，日常起应用不背这个包（Makefile 里 ch10-train/eval/export 都带 `uv run --group ml`）

## 测试体系：80+ 文件按模块分层

测试组织在 `tests/` 下，按模块分层，每个文件一个主题：

```
tests/
├── test_chat_api.py / test_agent_api.py / test_kb_api.py ...  # API 层（根目录 40+ 文件）
├── core/    # 核心逻辑：confidence / flywheel / rerank / retrieval / selfcheck / taxonomy
├── db/      # 数据库层：飞轮表 / 低置信池 / 工具审计 / 主题仓储
├── graph/   # 图编排：节点 / 路由 / 状态 / 中断 / 日志 / 强制RAG
├── kb/      # 知识库：混合检索 / 审核闸
└── tools/   # 工具层：引擎 / MCP客户端 / 归属校验 / 注册表
```

这套体系不是一次建成的，是跟着每一章长出来的：

- 第 1 章长出了 `test_llm.py`、`test_model_guard.py`（模型名守卫）
- 第 3 章长出了 `test_chunking_*.py`（切分/重叠/表格三个文件，一个机制拆开测）
- 第 4 章长出了 `test_retrieval_ch04.py`、`test_dualwrite_ch04.py`
- 第 6 章长出了 `test_ch06_nodes.py`、`test_routing.py`
- 第 9 章长出了 `test_observability.py`、`test_flywheel.py`、`test_confidence_gate.py`
- 第 10 章长出了 `test_ch10_corpus_lib.py`、`test_ch10_inference_lib.py`

**每个新机制都配了测试，才能做到改一处不炸一片**。测试打 mock 不打真实模型，CI 能跑、离线能跑。

## 这一路最值得说的三个工程教训

### 1. 配置治理：能不改代码就不改代码

模型名、地址、key、阈值、超时……全部收进 `.env`（pydantic-settings）。换上游只改配置不改代码；模型名写错启动时报 `Field required` 直接指出是哪一项。**配置外置 + 启动即校验**，比运行时 401 好排障一个量级。

### 2. 安全方向永远优先

贯穿全项目的选择：

- 归属校验宁可拦错不放行（空 user_id 一律不放行）
- 证据弱宁可兜底不说，不让模型硬编
- 裁到空宁可超预算回退原窗，不丢关键话
- 意图分不出来归"其他"，异常全兜底

**AI 系统里"答不上来"永远比"答错"便宜**——答错一次是事故，答不上来最多是遗憾。

### 3. 每个"为什么"都要有来路

回顾整个项目，几乎没有哪个设计是照抄最佳实践堆出来的：

- 锚点切窗 → 因为纯 token 裁剪把早期事实切没了
- RRF + 精排 → 因为混合不加精排反而掉点
- 归属校验放节点层 → 因为确定性子流程不经 agent_tools
- run_inline=True → 因为标签写不进 trace
- limit=201 拉候选 → 因为恰好 200 会误报截断

**面试官问"为什么这么设计"，答案都是"因为踩过这个坑"**——这是这个项目最值钱的部分。

## 现在的系统能做什么

- 对话 + 多轮指代 + 长程记忆（摘要层）
- 工单全流程：建单（确认卡）/查单（归属校验）/流转（MCP）
- 知识问答：混合检索 + 证据闸 + 拒答
- 备件查询：MCP 独立服务
- 投诉/闲聊：确定性出口
- 可观测：trace / 成本账 / 评估趋势
- 数据飞轮：问题池 → 标准化查重 → 待审队列 → 人工审核补知识
- 旁路分类器：主题归类 / 历史池分析

## 怎么验证

```bash
# 全量测试（离线可跑，不打真实模型）
& "D:\Pythonproject\mewhelp\.venv\Scripts\python.exe" -m pytest -q

# 一键拉起全套（MySQL/Milvus/MCP/应用）
make dev

# 一条 curl 走全链路
# {"user_id":"u1","message":"VFD-3005 变频器过载报警帮我报修"} → 建单确认流
# {"user_id":"u1","message":"电机过热报警怎么排查"} → 知识链路+证据闸
# {"user_id":"u1","message":"SP-1004 有货吗"} → MCP 备件查询
```
