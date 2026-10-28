---
title: Langfuse unhealthy：先找到失败发生在哪一层
description: 记录 Windows 本地集成部署中的存储与监听地址问题，以及验证方法。
date: '2026-10-28'
updated: '2026-10-28'
category: 排错与 TIL
tags:
- Docker Compose
- Langfuse
- Windows
---

# Langfuse unhealthy：先找到失败发生在哪一层

**记录阶段**：2026 年 10 月下旬 · 10 月 28 日整理

部署可选集成时，etcd、ClickHouse、MinIO 和 Redis 都显示 Healthy，但 `langfuse-web` 仍然 unhealthy。这个状态只说明健康检查没有通过，还不能直接确定根因。

项目保留的验收记录包含两处实际修正：ClickHouse 的 Windows 绑定目录问题，以及 Langfuse 的监听地址问题。它们属于这次本地环境的排查结果，不能把所有同类报错都归成相同原因。

## 先保留诊断，不急着删数据

首先读取当前 Compose 项目的容器状态、健康检查和相关日志。诊断脚本的作用是读出信息，不应该顺手停止或删除其他服务。

这一步能把问题分开：是应用进程没有正常启动，还是依赖连接失败，或者健康检查根本没有访问到实际监听地址。

## 存储层的一处问题

验收记录中，ClickHouse 在 Windows NTFS 绑定目录上出现原子重命名失败。修正使用 Docker 管理的 Linux 命名卷保存相应数据，同时保留旧目录。

更换存储位置之后，还要确认服务实际读写新卷并恢复健康。不能因为 Compose 配置语法通过，就认为数据层问题已经解决。

## 应用层的另一处问题

Langfuse web 和 worker 显式配置 `HOSTNAME=0.0.0.0`，使应用在容器内按预期监听。这个地址描述容器内绑定，和宿主机发布端口是两件事。

项目仍把宿主机发布地址限制在 `127.0.0.1`。因此“容器内监听所有接口”和“向外网公开服务”不能混为一谈，需要同时看容器和宿主机两层配置。

## 健康之后还需要检查实际功能

这次验收继续检查 Langfuse 健康接口、项目接口认证，并在服务端读回唯一模型追踪。追踪到达之后，再核对观测节点和载荷遮蔽。

这样，结论从“容器正在运行”逐步变成“应用健康、接口可用、追踪确实送达”。每次扩大结论，都要有对应的验证步骤。

## 下次遇到同样状态

先取最近的健康检查失败信息，再沿应用日志、依赖服务、存储和网络逐层缩小范围。保留原始错误，避免一次改很多配置之后失去因果关系。

- [当前固定版本 Compose 配置](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/infra/compose.yaml)
- [集成部署说明与本地环境限制](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/infra/README.md)
- [验证记录](https://github.com/smog-mgy/RepoLaunch/blob/97128d84e3a5f6c28e0ab99315bf9fff8544574b/docs/VALIDATION.md)
