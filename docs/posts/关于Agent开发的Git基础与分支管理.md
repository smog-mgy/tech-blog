# 关于Agent开发的Git基础与分支管理

**日期**：2026-03-26
**标签**：Git · 版本控制 · Agent

## 为什么Agent开发必须学 Git

> 你在 GitHub 上看到的 LangChain、LangGraph 这些 Agent 框架，全都是 Git 管理的开源项目。
>
> 想给开源项目提 PR？想和团队协作开发 Agent？想记录自己项目的迭代过程？不懂 Git 根本玩不转。
>
> 这篇文章把我学 Agent 开发前必须补的 Git 基础梳理一遍。

---

## 一、Git 是什么？为什么需要它

### 关于 Git

> **Git**：一个版本管理工具，帮你记录项目的每次修改，随时可以回退到任意历史版本。
>
> **类比理解**：就像游戏存档，你打了个 Boss 存个档，打错了可以读档重来。

**没有 Git 的痛点**：
- 项目改坏了，找不到原来的版本
- 同时改多个功能，互相冲突
- 想回退到上周的版本，不知道改了啥
- 多人协作，不知道谁改了什么

**有 Git 之后**：
- 每次修改都有记录，随时回退
- 不同功能在不同分支上开发，互不干扰
- 所有人改了什么一目了然
- 出问题了一键回滚

---

## 二、分支是什么？

### 关于分支（Branch）

> **分支**：从主线（master/main）分叉出来的一条独立开发线，在分支上改代码不会影响主线。
>
> **为什么需要分支**：开发新功能时不想搞乱主线的稳定版本，做完了再合并回去。

**类比理解**：
- 主线（master）：稳定版，能正常运行的版本
- 新分支：你在上面瞎改，改坏了直接删掉分支就行
- 合并：改好了，把新分支的代码合并回主线

---

## 三、常用分支命令

### 1. 查看所有分支

```bash
git branch
```

输出：
```
* main
  dev
  feature/login
```

前面带 `*` 的是当前所在分支。

### 2. 创建新分支

```bash
git branch 分支名
```

例子：
```bash
git branch feature/rag
```

### 3. 切换分支

```bash
git checkout 分支名
```

或者新版本 Git 用：
```bash
git switch 分支名
```

例子：
```bash
git checkout feature/rag
```

### 4. 创建并切换到新分支（最常用）

```bash
git checkout -b 新分支名
```

**等价于**：先 `git branch` 创建，再 `git checkout` 切换。

例子：
```bash
git checkout -b feature/embedding
```

**关键点**：`-b` 就是 "branch" 的意思，创建+切换一步完成。

### 5. 合并分支

```bash
git checkout main          # 先切回主分支
git merge feature/rag      # 把 feature/rag 合并进来
```

**流程**：
1. 在 feature 分支上开发新功能
2. 开发完了切回 main 分支
3. 把 feature 分支合并到 main

### 6. 删除分支

```bash
git branch -d 分支名
```

例子：
```bash
git branch -d feature/rag
```

---

## 四、commit message 规范

### 为什么要写规范的 commit message

> 写得好的 commit 信息，几个月后你一眼就知道这次改了什么。
>
> 写得烂的（"update"、"fix"、"改了点东西"），过两天自己都忘了改了啥。

### 常用的 commit 类型

| 前缀 | 含义 | 例子 |
|---|---|---|
| `feat:` | 新功能 | `feat: 添加 PDF 文档上传功能` |
| `fix:` | 修 bug | `fix: 修复向量数据库加载失败的问题` |
| `docs:` | 文档修改 | `docs: 更新 README 安装说明` |
| `style:` | 代码格式 | `style: 调整代码缩进` |
| `refactor:` | 重构 | `refactor: 拆分 loader 模块` |
| `test:` | 测试 | `test: 添加 PDF 加载单元测试` |
| `chore:` | 杂项 | `chore: 更新依赖版本` |

### 好的 vs 烂的 commit message

**烂的**：
```
"改了点东西"
"update"
"fix bug"
"提交"
```

**好的**：
```
feat: 添加 RAG 问答链模块
fix: 修复 Ollama 连接超时问题
docs: 补充模块化项目目录说明
```

**记忆口诀**：`<类型>: <做了什么事>`

---

## 五、合并冲突（Merge Conflict）

### 什么是合并冲突

> 当两个分支修改了同一个文件的同一行，Git 不知道该用哪个版本，就会报冲突。

**常见场景**：
- 你和同事同时改了同一段代码
- 你在两个分支上都改了同一行

### 怎么解决冲突

**第 1 步：Git 提示冲突**

```
CONFLICT (content): Merge conflict in config.py
```

**第 2 步：打开冲突文件**

Git 会在文件里标记出冲突的地方：

```python
<<<<<<< HEAD
CHUNK_SIZE = 500
=======
CHUNK_SIZE = 1000
>>>>>>> feature/embedding
```

**第 3 步：手动选择保留哪个**

删掉标记，改成你想要的版本：

```python
CHUNK_SIZE = 500
```

**第 4 步：标记冲突已解决**

```bash
git add config.py
git commit -m "merge: 解决 CHUNK_SIZE 配置冲突"
```

**关键点**：
- 冲突不可怕，就是 Git 让你做个选择
- 打开文件，删掉 `<<<<<<<` 和 `=======` 和 `>>>>>>>` 这些标记
- 保留你想要的代码就行

---

## 六、完整的分支工作流

**开发新功能的标准流程**：

```bash
# 1. 切回主分支，拉最新代码
git checkout main
git pull

# 2. 创建新功能分支
git checkout -b feature/new-tool

# 3. 在新分支上开发，多次提交
git add .
git commit -m "feat: 添加新工具函数"

# 4. 开发完了，切回主分支
git checkout main

# 5. 合并新分支
git merge feature/new-tool

# 6. 推送到远程
git push origin main

# 7. 删除本地功能分支
git branch -d feature/new-tool
```

---

## 七、为什么 Agent 开发必须懂 Git

> LangChain 这样的开源 Agent 项目，每天都有几百个 PR 提交：
>
> - 有人加了个新工具
> - 有人修了个 bug
> - 有人更新了文档
>
> 不懂分支、不懂 commit 规范、不懂合并冲突，根本没法参与开源贡献。

**实际工作中**：
- 每个功能开一个分支，不搞乱主线
- 代码评审时看 commit message 就知道改了啥
- 出问题了，快速定位是哪次提交引入的 bug

**三者关系**：

```plaintext
写代码 → 提交 → 分支 → 合并 → 发布
```

- 函数/类：写代码
- 模块化：组织代码
- Git：管理代码版本
