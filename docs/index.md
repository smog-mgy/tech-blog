# 苗国艺的工程笔记

我在学习和实践 AI Agent 应用开发。这里记录 Python 基础、检索与工具调用，也记录把项目部署起来时遇到的具体问题。

## 项目笔记

- [RepoLaunch：从仓库到可验证的本地运行](posts/repolaunch-overview.md) — 项目解决什么问题，做到了哪一步。
- [模型提出补丁之后，程序还要检查什么](posts/repolaunch-repair.md) — 一次缺失依赖故障的排查与修复。
- [OpsDesk 项目导读](projects/opsdesk.md) — 设备运维问答、报修和工单查询的实现。

## 我在做的项目

| 项目 | 主要关注 | 项目记录 |
| --- | --- | --- |
| **RepoLaunch** | 仓库分析、方案确认、容器执行、日志诊断与修复验证 | [专题](projects/repolaunch.md) · [GitHub](https://github.com/smog-mgy/RepoLaunch) |
| **OpsDesk** | 设备运维问答、报修与查单、混合检索、业务工具和会话状态 | [专题](projects/opsdesk.md) · [GitHub](https://github.com/smog-mgy/opsdesk) |

## 文章分类

- [Python 与大模型学习笔记](learning/index.md)
- [项目实战](projects/index.md)
- [排错与 TIL](til/index.md)
- [全部文章](archive.md)
- [技术博客与文章](reading.md)

## 最近更新

2026 年 10 月下旬：RepoLaunch 项目复盘

- [工作流和模型各自负责什么](posts/repolaunch-workflow.md)
- [从真实失败日志到受控修复](posts/repolaunch-repair.md)
- [故障案例、任务记录与模型追踪怎样协作](posts/repolaunch-integrations.md)
- [三个仓库跑通之后，验证结论该怎么写](posts/repolaunch-verification.md)
- [端口被占用，和浏览器页面有什么关系](til/repolaunch-port.md)
- [Langfuse unhealthy 的两处排查](til/langfuse-health.md)

<!-- revision: wording-20261029 -->
