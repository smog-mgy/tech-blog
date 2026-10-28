---
title: 故障案例、任务记录和模型追踪怎样协作
description: 按数据用途解释 Milvus、MySQL、Langfuse 和只读 MCP 的边界。
date: '2026-10-28'
updated: '2026-10-28'
category: 项目实战
tags:
- RepoLaunch
- RAG
- 可观测性
- MCP
---

# 故障案例、任务记录和模型追踪怎样协作

**记录阶段**：2026 年 10 月下旬 · 10 月 28 日整理

同时接入向量库、业务数据库和追踪系统之后，最先需要讲清楚的是：每一份数据应该放在哪里，以及系统怎样确认它真的被读写成功。

RepoLaunch 中，这几种集成承担不同职责。它们没有把部署流程变成多 Agent 系统，也没有替代执行器的方案校验。

## 诊断案例为什么可以检索

项目内置六条可检查的诊断案例，带有问题特征、处理建议和来源。小语料默认可以走本地词法检索；显式配置后，才使用 Milvus 向量检索。

真实集成验收使用 BAAI/bge-m3 生成 1024 维向量，写入六条案例并读回，再用缺模块问题查询。验证的重点是案例是否真正写入、查询是否命中预期类型，而不仅是“Milvus 端口能连”。

六条案例很容易覆盖少数固定故障。它们还不足以证明检索质量优良，更不能推出 RAG 提升了任意仓库部署成功率。后续需要独立问题集、无关问题和检索失败样例。

## 任务历史需要可读回

任务、方案、状态和验证结果是结构化记录，默认使用 SQLite，可选 MySQL。二者解决的是任务历史持久化，不是语义检索。

验收中先提交一条任务，再从独立连接读回；迁移只向空目标库执行，并保留原 SQLite 文件。与“写入函数没有抛错”相比，独立读回更接近用户实际需要的持久化结果。

## 追踪到达服务端了吗

启用 Langfuse SDK 只能说明代码准备发送追踪。要确认送达，需要在服务端查询对应追踪，而不能只看本地日志里出现 initialized。

这次验收使用唯一追踪名称，在服务端读回对应请求和五个观测节点，并检查载荷遮蔽标记。模型 API Key 不应出现在追踪返回、任务日志和导出报告中。

调用耗时、Token 和失败类型可以帮助排查模型请求，但仍要区分模型请求与整个任务：下载仓库、安装依赖和容器启动也消耗时间，它们不属于同一项计时。

## MCP 暴露了什么

当前 stdio MCP 服务只有三个只读工具：

| 工具 | 用途 |
| --- | --- |
| `list_tasks` | 查看任务列表摘要 |
| `task_status` | 查看指定任务状态 |
| `export_metadata` | 查看报告导出元数据 |

它没有部署、删除容器或修改数据库的工具。真实验收用 MCP SDK 完成握手、列举工具和调用，而不是仅在终端打印三个函数名。

## 从组件连通走到功能验收

我的检查顺序是：服务健康 → 凭据和配置有效 → 实际写入/调用 → 独立读回 → 核对内容与脱敏。每一层都回答不同的问题。

- [案例与 Milvus 集成](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/repolaunch/knowledge.py)
- [任务存储](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/repolaunch/storage.py)
- [只读 MCP 服务](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/repolaunch/mcp_server.py)
- [真实服务验收脚本](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/tools/verify_full_stack.py)
