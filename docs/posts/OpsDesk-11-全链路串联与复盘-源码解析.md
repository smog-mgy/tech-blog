# 第 11 章：全链路串联与复盘（源码解析）

**日期**：2026-09-29
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 11 章：全链路串联与复盘（项目落地笔记）.md`
> 本解析走读 Makefile 编排层与 tests 测试组织，它们是"全链路"的工程骨架。

## 涉及文件

| 文件/目录 | 职责 |
|---|---|
| `Makefile` | 全项目命令编排（依赖/建库/评估/服务/测试） |
| `tests/` | 80+ 测试文件，按模块分层 |
| `app/graph/build.py` | 全链路骨架（第 5 章源码，这里回看整体） |

## Makefile 走读

### 顶部：Python 强制 UTF-8

```makefile
# Python 强制 UTF-8。中文 Windows 默认 GBK,读本仓库里带中文的 markdown / jsonl
# (知识库、评估集)会抛 UnicodeDecodeError。必须在 Python 启动前生效,所以设在这里而不是 .env。
export PYTHONUTF8 = 1
```

- 中文 Windows 的 Python 默认按 GBK 解码文件，读知识库 markdown / 评估 jsonl（全是中文）直接 `UnicodeDecodeError`
- **`export` 必须在 Python 启动前生效**，所以放在 Makefile 顶部而不是 .env——.env 是 Python 起来之后才读的，那时已经炸了
- 这是 Windows 跑中文数据项目的第一个拦路坑

### help 机制：目标即文档

```makefile
.PHONY: help kb-repatch dev test eval ... langfuse-up langfuse-down

help:  ## 列出带说明的目标
	@grep -E '^[a-z][a-z0-9-]*:.*?## ' $(MAKEFILE_LIST) \
	  | sed 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  %-22s %s\n", $$1, $$2}'
```

- 每个目标后面跟 `## 一句人话说明`，`make help` 用 grep/sed/awk 把它们抽出来排成表格
- 目标 20+ 个，没有 help 就全靠 README 和记忆——**让命令自己解释自己**

### 各章目标的分层组织

```makefile
# ch09: Langfuse 自部署观测栈(web:3000 + worker + postgres + clickhouse + redis + minio)
langfuse-up:
	docker compose -p opsdesk-langfuse -f docker-compose.langfuse.yml up -d
	@echo "Langfuse 起中: http://localhost:3000 (admin@opsdesk.local / opsdesk123)"
	@echo "首次就绪约 2-3 分钟;key 已 headless 预置,写 .env:"
	@echo "  LANGFUSE_PUBLIC_KEY=pk-lf-opsdesk-local"
	...
```

几个值得拆的设计：

1. **`-p opsdesk-langfuse` 独立 project 名**：注释点破原因——"不加会与主 compose 同落 opsdesk project，两边的 minio 服务同名相撞"。**两套 compose 的 minio 服务名相同，同 project 下 docker 会当成同一个服务**，直接冲突。独立 project 隔离
2. **账号/密钥在命令里 echo 出来**：`admin@opsdesk.local / opsdesk123` 和三个 key 都是 compose 预置的固定值，部署文档和命令输出共用同一真相，不各写各的
3. **ch10 重依赖走 `--group ml`**：

```makefile
ch10-train:  ## ch10 RoBERTa-wwm-ext 全参微调(MPS/CUDA/CPU 自适应,重依赖走 ml 组)
	PYTHONPATH=. uv run --group ml python scripts/ch10/train.py
```

torch/transformers 几个 G，只有训练/评估/导出需要——`uv` 的 optional group 机制把它们隔离，日常 `make dev` 不装这堆重包

4. **classifier-up 带自检**：

```makefile
classifier-up:  ## ch10 推理服务 :8110(ONNX 轻运行时)
	@mkdir -p log data
	@PYTHONPATH=. nohup uv run --group ml python scripts/ch10/serve.py > log/classifier.log 2>&1 & echo $$! > data/classifier.pid
	@sleep 2 && curl -sf http://127.0.0.1:8110/healthz >/dev/null && echo "分类器服务已拉起: :8110(pid 见 data/classifier.pid)" || echo "启动失败,看 log/classifier.log"
```

- 后台起服务（nohup + pid 文件）+ **sleep 2 后 curl healthz 自检**，起没起来当场知道，不用猜
- `classifier-down` 用 pid 文件 kill，配套完整

## tests 组织走读

### 目录结构与命名规律

```
tests/
├── 根目录 40+ 文件          # API 层：test_chat_api / test_agent_api / test_kb_api ...
├── core/                    # 核心逻辑：confidence / flywheel / rerank / retrieval / selfcheck / taxonomy
├── db/                      # 数据库层：飞轮表 / 低置信池 / 工具审计 / 主题仓储
├── graph/                   # 图编排：节点 / 路由 / 状态 / 中断 / 日志 / 强制RAG / 置信闸
├── kb/                      # 知识库：混合检索 / 审核闸
└── tools/                   # 工具层：引擎 / MCP客户端 / 归属校验 / 注册表
```

命名规律三条：

1. **API 层用 `test_<module>_api.py`**：test_chat_api / test_agent_api / test_kb_api / test_review_api / test_topics_api——一眼看出测的是哪个端点
2. **机制按粒度拆文件**：chunking 拆成 `test_chunking_split.py`（切分）/ `test_chunking_overlap.py`（重叠）/ `test_chunking_table.py`（表格）三个——**一个机制一个文件，失败时定位精确**
3. **按章标注**：`test_ch06_nodes.py`、`test_ch08_confirm_ticket.py`、`test_ch09_confidence_gate.py`、`test_dualwrite_ch04.py`——测试跟项目演进的章节对应，README 里能说清"第 6 章的节点行为有测试兜底"

### 分层测试的边界

- **API 层**：测 HTTP 端点（参数校验、响应结构、错误码），打 mock 不打真实模型
- **core/ graph/**：测核心逻辑（置信度计算、路由分流、中断帧 payload），纯确定性
- **db/**：测 SQL 层（表结构、游标语义、审计落库）
- **tools/**：测工具层（MCP 客户端薄壳、归属校验、引擎分诊）

**分层的好处**：改检索逻辑只需跑 core/ + kb/，不用背整个 API 层；每层都能离线跑（不打真实模型、不起外部服务）。

### conftest.py 与公共 fixture

`tests/conftest.py` 提供跨文件共享的 fixture（数据库连接、测试会话、mock 模型），各层复用——80+ 文件不各自造轮子。

## 全链路数据流（回看 build.py）

第 5 章源码这里回看整体，把 11 章的位置标出来：

```
START
 → resolve_reference    # 第 6 章 指代消解（coref.py）
 → classify_intent      # 第 6 章 意图分类（intent.py）
 → route_by_intent 条件边   # 第 6 章 映射表（routing.py）
   ├─ escalate → complaint_reply     # 第 6 章 确定性出口
   ├─ fallback_script → script_reply # 第 6 章
   ├─ knowledge → retrieve_knowledge → confidence_check → main_agent / fallback_reply
   │                                    # 第 3 章 检索 / 第 4 章 混合检索 / 第 9 章 置信闸
   └─ business → fetch_ticket → retrieve_policy → main_agent
                   # 第 6 章 中断选择器 / 第 3 章 强制检索制度
 → main_agent ⇄ agent_tools（ReAct）  # 第 2 章 引擎 / 第 8 章 MCP
 → log → END                          # 第 9 章 观测
```

每个节点都有对应章节的源码支撑，这张图就是整份学习笔记的目录。

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| `export PYTHONUTF8 = 1`（Makefile 顶部） | 中文 Windows GBK 读中文数据文件报 UnicodeDecodeError |
| `-p opsdesk-langfuse` 独立 project | 两套 compose 的 minio 同名服务不冲突 |
| 目标带 `##` 注释 + make help | 命令自己解释自己，不用翻文档 |
| `--group ml` 隔离重依赖 | 日常起应用不装 torch 几个 G |
| classifier-up 起服务后 curl healthz 自检 | 起没起来当场知道 |
| 测试按模块分层 + 按章标注 | 定位精确、离线可跑、演进可追溯 |
