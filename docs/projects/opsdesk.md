# OpsDesk 项目导读

OpsDesk 是一个围绕企业设备运维场景的个人练习项目，包含故障知识问答、报修确认和工单进度查询。工单和设备信息使用演示数据。

[查看 GitHub 仓库](https://github.com/smog-mgy/opsdesk) · 源码版本：`f95a24a`。

## 主要功能

- **知识问答**：检索候选、融合与重排、证据检查，再决定生成或拒答。先读第 3、4、9 章。
- **业务工具**：模型提出调用，程序校验身份与参数，写操作经过确认后执行。先读第 2、5、8 章。
- **多轮对话**：指代消解、历史裁剪与摘要、状态重置，服务于下一轮问题。先读第 6、7 章。

## 按章节对照


| 主题 | 先理解设计 | 再对照代码 |
| --- | --- | --- |
| 01 模型接入与提示词 | [项目复盘](../posts/OpsDesk-01-LLM接入与Prompt工程-项目落地笔记.md) | [源码解析](../posts/OpsDesk-01-LLM接入与Prompt工程-源码解析.md) |
| 02 工具调用与写操作确认 | [项目复盘](../posts/OpsDesk-02-FunctionCalling工具链-项目落地笔记.md) | [源码解析](../posts/OpsDesk-02-FunctionCalling工具链-源码解析.md) |
| 03 知识库构建与双写 | [项目复盘](../posts/OpsDesk-03-RAG基础与知识库构建-项目落地笔记.md) | [源码解析](../posts/OpsDesk-03-RAG基础与知识库构建-源码解析.md) |
| 04 混合检索与评估 | [项目复盘](../posts/OpsDesk-04-混合检索与评估体系-项目落地笔记.md) | [源码解析](../posts/OpsDesk-04-混合检索与评估体系-源码解析.md) |
| 05 工作流与 Agent 的职责 | [项目复盘](../posts/OpsDesk-05-Workflow与Agent混合架构-项目落地笔记.md) | [源码解析](../posts/OpsDesk-05-Workflow与Agent混合架构-源码解析.md) |
| 06 意图识别与工单分流 | [项目复盘](../posts/OpsDesk-06-意图识别与对话管理-项目落地笔记.md) | [源码解析](../posts/OpsDesk-06-意图识别与对话管理-源码解析.md) |
| 07 会话上下文与摘要 | [项目复盘](../posts/OpsDesk-07-会话上下文管理-项目落地笔记.md) | [源码解析](../posts/OpsDesk-07-会话上下文管理-源码解析.md) |
| 08 工具注册与 MCP | [项目复盘](../posts/OpsDesk-08-工具系统与MCP扩展-项目落地笔记.md) | [源码解析](../posts/OpsDesk-08-工具系统与MCP扩展-源码解析.md) |
| 09 调用追踪与反馈审核 | [项目复盘](../posts/OpsDesk-09-可观测性与数据飞轮-项目落地笔记.md) | [源码解析](../posts/OpsDesk-09-可观测性与数据飞轮-源码解析.md) |
| 10 旁路分类器与微调 | [项目复盘](../posts/OpsDesk-10-主题分类器与模型微调-项目落地笔记.md) | [源码解析](../posts/OpsDesk-10-主题分类器与模型微调-源码解析.md) |
| 11 全链路验证与复盘 | [项目复盘](../posts/OpsDesk-11-全链路串联与复盘-项目落地笔记.md) | [源码解析](../posts/OpsDesk-11-全链路串联与复盘-源码解析.md) |

## 测试记录

图编排、工具注册、检索和数据处理的入口可以在公开源码中检查。外部模型、MySQL、Milvus 和 Langfuse 的运行结果依赖当时环境，需要另行复现。

仓库保留了[历史评估趋势记录](https://github.com/smog-mgy/opsdesk/blob/f95a24a2a67d1d3ae5cb6c253537d3f373df7b00/data/ch09/reports/eval_trend.txt)和[44 条留出样本的分类报告](https://github.com/smog-mgy/opsdesk/blob/f95a24a2a67d1d3ae5cb6c253537d3f373df7b00/data/ch10/reports/eval_report.md)。评估结果来自当时的样例数据。

在 RepoLaunch 的独立部署尝试中，这个仓库曾因 setuptools 的平铺目录包发现配置失败。RepoLaunch 当前不改目标项目打包声明，所以这次尝试仍应记录为失败。

## 本地运行

先按仓库 README 核对依赖和外部服务，再运行本地测试与单条场景。先确认工具是否真的执行、证据是否来自检索，再检查界面上的回答是否看起来合理。
