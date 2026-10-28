# RepoLaunch 项目导读

RepoLaunch 面向“仓库已经找到，却卡在依赖安装、启动命令和环境报错”的本地开发场景。首版限定公开、CPU 运行的 Python Web 项目。

[查看 GitHub 仓库](https://github.com/smog-mgy/RepoLaunch)

## 项目文章

目前测试过三个公开仓库，并用一个故意缺少 requests 的样例验证了修复流程。测试记录见文末链接。

1. [RepoLaunch：从仓库到可验证的本地运行](../posts/repolaunch-overview.md) — 说明首版解决的部署问题、系统分工和目前的支持边界。
2. [RepoLaunch 的工作流：哪些决定交给模型](../posts/repolaunch-workflow.md) — 沿 retrieve、propose、validate 三个节点理解固定流程与模型建议的关系。
3. [模型提出补丁之后，程序还要检查什么](../posts/repolaunch-repair.md) — 从一次 requests 缺失故障解释补丁边界、依赖证据与重建验收。
4. [故障案例、任务记录和模型追踪怎样协作](../posts/repolaunch-integrations.md) — 按数据用途解释 Milvus、MySQL、Langfuse 和只读 MCP 的边界。
5. [三个仓库跑通之后，验证结论该怎么写](../posts/repolaunch-verification.md) — 区分 HTTP 就绪、内容探针、自动化测试与真实服务验收。

## 验证依据

- [项目验证记录](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/docs/VALIDATION.md)
- [三个真实仓库的固定提交与结果](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/docs/BENCHMARK.md)
- [端口占用排查](../til/repolaunch-port.md)
- [Langfuse 健康检查排查](../til/langfuse-health.md)

## 当前边界

支持单个 Python Web 项目的受控尝试。私有仓库、GPU、目标项目多服务编排、任意源码修改和自动注入目标密钥，都不在这一版的能力范围内。固定了仓库提交，并不等于已经锁定镜像和依赖的所有版本。
