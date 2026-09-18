# 用 Ollama 搭建本地 RAG 问答应用：从踩坑到重写

**日期**：2026-09-18
**标签**：Python · RAG · Ollama · Streamlit

## 背景

我想做一个本地的 PDF 问答应用：上传 PDF，然后向它提问，全程数据不出本机。最初基于 `embedchain` 框架快速搭了一个，但实际用起来发现**回答很"笨"、答非所问、还会编造内容**。这篇文章记录我从"能用"到"好用"的过程，重点是踩过的坑。

## 第一版：embedchain 快速搭建

第一版代码很短，核心就一个配置：

```python
from embedchain import App

app = App.from_config(config={
    "llm": {"provider": "ollama", "config": {"model": "llama3.2:latest", ...}},
    "vectordb": {"provider": "chroma", "config": {"dir": db_path}},
    "embedder": {"provider": "ollama", "config": {"model": "llama3.2:latest", ...}},
})
```

表面看一切正常，实际跑起来问题一堆。

## 坑 1：`ollama` Python 包缺失

!!! note "报错信息"
    `ImportError: Ollama requires extra dependencies. Install with pip install ollama`

embedchain 的 Ollama 提供方需要 `ollama` 这个 Python 库，但它**不会随 embedchain 自动安装**。Ollama 软件本身装好了也没用，这是 Python 层面的依赖缺失。

**解决**：`pip install ollama`

## 坑 2：用对话模型当嵌入模型

第一版把 `llama3.2:latest` 同时用作对话模型和嵌入模型（embedder）。实际上 **llama3.2 不支持 embedding**（Ollama 中它的能力只有 `completion`），调用嵌入接口直接超时，添加文档时失败。

**解决**：拉取专门的嵌入模型 `nomic-embed-text`，并在 embedder 配置中指定。

## 坑 3（最关键）：对话历史全局共享，幻觉被"回传强化"

这是最难发现的问题。表现为：提问越来越"笨"，且错误有延续性。

排查过程：把实际发给模型的 Prompt 打出来看，发现里面**混着大量无关的历史对话**——论文总结、漏洞报告、简历分析，全是之前不同会话里问过的内容。

```text
Context information:
------（当前 PDF 的检索片段）------

Conversation history:
------（10 轮历史问答，来自之前所有会话）------

Query: 当前问题
Answer:
```

**根因**：embedchain 把所有会话的问答统一存进全局 SQLite（`~/.embedchain/embedchain.db`），且都挂在同一个默认 `app_id` 下。每次提问，框架自动把最近 10 轮历史拼进 Prompt。更糟的是，**历史里 AI 曾经编造过的回答会被再次当作"参考"喂给模型**——幻觉形成自我强化的恶性循环。

例如：文档明明写着"杭州以西湖、龙井茶闻名"，模型却回答"杭州的文化名著包括《西游记》《三国演义》"——这段编造又进入历史，污染后续所有会话。

**解决思路**：不再依赖黑盒框架的"历史管理"，而是自己控制 Prompt——**只放检索片段和当前问题，不带任何历史**。

## 最终方案：重写一个精简 RAG

与其继续给 embedchain 打补丁，不如自己写一个完全可控的精简版，四个模块：

| 模块 | 职责 |
|---|---|
| `config.py` | 所有可配置项（模型、路径、分块参数） |
| `loader.py` | PDF 解析 + 文本分块（带重叠） |
| `store.py` | ChromaDB 封装（嵌入、存储、检索） |
| `qa.py` | 检索 → 组装 Prompt → 调用模型生成 |

关键设计决策：

1. **每份 PDF 独立 collection**——不同文档的问答互不干扰
2. **Prompt 只含检索片段 + 当前问题**——根治历史污染
3. **用 `qwen2.5:7b` 替代 3B 小模型**——中文回答质量明显提升
4. **用 `bge-m3` 替代英文嵌入模型**——中文检索更准

## 验证结果

在本地 Ollama（16G 内存）上，提问"杭州地铁1号线什么时候开通？"，模型能准确回答"2012年11月24日"——内容来自 PDF，不再是编造。

## 总结

- 用黑盒框架快速出活可以，但出问题时排查成本高，尤其是隐式的"历史管理"
- RAG 应用的核心三要素：**检索准、Prompt 干净、模型够强**
- 遇到"答非所问 + 编造内容"，优先检查三件事：检索到内容了吗？Prompt 里混入了什么？模型是不是太弱？

*下一篇预告：自己实现 ChromaDB 向量库的增删查，附完整代码。*
