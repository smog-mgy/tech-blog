# 第 04 章：混合检索与评估体系（源码解析）

**日期**：2026-08-24
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 04 章：混合检索与评估体系（项目落地笔记）.md`
> 本解析逐段走读多策略检索、子句拆分合并与重排层。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/core/retrieval.py` | 检索总入口：四策略、子句拆分、轮转合并、首尾摆放 |
| `app/core/rerank.py` | Cross-Encoder 精排：直连上游 /rerank、退避重试 |
| `app/core/embeddings.py` | 嵌入：bge-m3 查询/文档向量化 |
| `app/kb/milvus_client.py` | Milvus 检索执行（vector / bm25 / hybrid） |

## retrieval.py 逐段走读

### split_clauses：一问多意图拆子句

```python
_CLAUSE = re.compile(r"[,，;；?？。]")
_MIN_CLAUSE = 4          # 太短的碎片(「怎么办」)当不了子查询

def split_clauses(query: str) -> list[str]:
    parts = [p.strip() for p in _CLAUSE.split(query) if len(p.strip()) >= _MIN_CLAUSE]
    return parts if len(parts) >= 2 else [query]
```

docstring 把动机说透：

- 「3号线的电机过热报警了怎么排查，顺便问下备件散热风扇有没有货」这种一句话问两件事，**整句去检索时向量会被主语义带跑，只有一个意图能挤进前排**
- 拆开各查一遍再轮转合并，每个意图都能占到名额
- **警告写在注释里**："这招得配精排：子句各自的第一名要够准，合并才有意义，没有精排的单路检索拆完反而更吵（评估集实测：重排 +0.02、其余三路 -0.04 到 -0.06）"

细节：`_MIN_CLAUSE = 4` 过滤碎片（"怎么办"这种 3 字残句当不了子查询）；拆不出两条就原样返回一条。

### _merge_round_robin：轮转合并

```python
def _merge_round_robin(lists: list[list[dict]]) -> list[dict]:
    out, seen_id, seen_sec, tail = [], set(), set(), []
    for i in range(max((len(x) for x in lists), default=0)):
        for lst in lists:
            if i >= len(lst):
                continue
            h = lst[i]
            key = h.get("id") or (h.get("section_path", ""), h.get("question", ""))
            if key in seen_id:
                continue
            seen_id.add(key)
            sec = h.get("section_path") or ""
            if sec in seen_sec:
                tail.append(h)
            else:
                seen_sec.add(sec)
                out.append(h)
    return out + tail
```

- **轮转**：每个子句轮流出一条（子句 A 的第 1 名、子句 B 的第 1 名、子句 A 的第 2 名……），保证每个意图都占名额
- **按 chunk id 去重**（无 id 时退化为 section_path+question 组合键）
- **同小节只留最靠前那条，重复的挪到尾部**：`seen_sec` 命中的进 tail 而不是丢弃——同一小节的块内容近似，保留一条在前，多余的排后面不干扰前排

### arrange_head_tail：对抗 lost-in-the-middle

```python
def arrange_head_tail(items: list) -> list:
    if len(items) <= 2:
        return items
    return [items[0], *items[2:], items[1]]
```

- 最相关放首、次相关放尾、其余按序居中
- 模型对上下文两端的注意力强于中间，把次相关放尾比放第二顺位更能被读到

### search_knowledge：四策略总入口

```python
async def search_knowledge(
    query: str, strategy: str = "hybrid_rerank", top_k: int | None = None,
    category: str | None = None, client=None, collection: str = "knowledge",
    bm25_text: str | None = None, split: bool = True,
) -> list[dict]:
```

**strategy 四档**：`vector`（纯向量）/ `bm25`（纯关键词）/ `hybrid`（混合不精排）/ `hybrid_rerank`（混合+精排，默认）。

关键设计逐点拆：

**1. dense query 与 bm25_text 分离**：

```python
bt = bm25_text or query  # BM25 检索文本;dense 始终用干净的 query
```

调用侧可以传「标准问法 + 同义词扩展」只作用于 BM25 一侧，**不污染 dense query**（docstring 引用 spec §2）。BM25 吃字面扩展（召回更多字面匹配），向量吃干净语义——各喂各的，不互相污染。

**2. 子句递归**：

```python
if split and settings.subquery_split:
    clauses = split_clauses(query)
    if len(clauses) >= 2:
        per = [await search_knowledge(c, strategy=strategy, ...split=False) for c in clauses]
        return _merge_round_robin(per)[:top_k]
```

- 子句递归调用时 `split=False`——防止子句再被拆
- 每路子句完整走一遍策略（含精排），再轮转合并

**3. 三路实现的分工**：

```python
if strategy == "bm25":
    def work():
        ...
        return milvus_client.bm25_search(c, bt, top_k, category, collection)
    return await milvus_client.acall(work)

if strategy == "vector":
    vec = await embeddings.embed_query(query)
    def work():
        ...
        return milvus_client.dense_search(c, vec, top_k, category, collection)
    return await milvus_client.acall(work)

# hybrid / hybrid_rerank
vec = await embeddings.embed_query(query)
def work():
    ...
    return milvus_client.hybrid_search(
        c, vec, bt, settings.recall_top_k, settings.recall_top_k, category, collection)
hits = await milvus_client.acall(work)
```

- bm25 路不吃向量（`bt`）；vector 路吃 `query` 的向量
- hybrid 路两路都跑，**recall_top_k 先混合召回**（多捞），hybrid 直接截 top_k；hybrid_rerank 对召回结果精排

**4. acall：固定单线程规避 gRPC 跨线程坑**：

```python
# 所有 Milvus 同步调用(建集合/检索)经 milvus_client.acall 固定到专用单线程执行,
# 客户端也在该线程惰性创建 —— 规避 gRPC 客户端跨线程共享在 async server 下的间歇空返回。
```

Milvus 客户端是同步 gRPC，在 async server 里跨线程共享会**间歇性空返回**（玄学 bug）——所有同步调用收口到一个专用线程执行，客户端在该线程惰性创建。

**5. 精排在 Milvus 线程之外**：

```python
docs = [f"{h['question']} {h['answer']}" for h in hits]
ranked = await rerank.rerank(query, docs, top_n=top_k)
out = []
for idx, score in ranked:
    h = dict(hits[idx]); h["rerank_score"] = score
    out.append(h)
```

- 精排走上游 async HTTP，**不进 Milvus 线程**（避免把同步线程卡在等待网络）
- 重排后按原始索引取回 hit 并附加 `rerank_score`——证据里可以带分

## rerank.py 逐段走读

### rerank：手写非 OpenAI 协议的请求

```python
async def rerank(query: str, docs: list[str], top_n: int | None = None) -> list[tuple[int, float]]:
    if not docs:
        return []
    payload = {"model": settings.rerank_model, "query": query, "documents": docs,
               "top_n": top_n or len(docs)}
    resp = await _post(_rerank_url(), payload,
                       {"Authorization": f"Bearer {settings.rerank_api_key}"}, 60)
    resp.raise_for_status()
    results = resp.json()["results"]
    ranked = sorted(((r["index"], float(r["relevance_score"])) for r in results),
                    key=lambda x: x[1], reverse=True)
    return ranked[:top_n] if top_n else ranked
```

- docstring 点破：**rerank 不是 OpenAI 协议里的东西**，这个接口走 Jina / Cohere 那套形状（query + documents，回 results 里的 index 与 relevance_score），所以手写请求、不用 openai 客户端
- 返回 `[(原始索引, 相关分)]` 按分降序截断 top_n——检索侧用索引回查原 hit

### _rerank_url：版本段兜底

```python
_VERSION_SEG = re.compile(r"/v\d+$")

def _rerank_url() -> str:
    base = settings.rerank_base_url.rstrip("/")
    if not _VERSION_SEG.search(base):
        base += "/v1"
    return base + "/rerank"
```

- 地址带不带版本段都收：硅基流动和 Jina 的 rerank 在 /v1 下，Cohere 在 /v2 下
- **"上游地址按字面理解很容易只填到域名"**——少了版本段会打成 `https://host/rerank` 上游回 404，而且只在查询时以 hybrid_rerank 失败形式冒出来，排障绕一大圈
- 每次现算，改配置不用重启

### _post：退避重试

```python
_RETRY_STATUS = {429, 500, 502, 503, 504}
_RETRIES = 3
_BACKOFF = 1.5

async def _post(url, json, headers, timeout):
    for i in range(_RETRIES + 1):
        try:
            async with httpx.AsyncClient() as c:
                resp = await c.post(url, json=json, headers=headers, timeout=timeout)
        except httpx.TransportError as e:
            last_exc = e
            if i < _RETRIES:
                await asyncio.sleep(_BACKOFF * (2 ** i))
                continue
        if resp.status_code not in _RETRY_STATUS:
            return resp
        last = resp
        if i < _RETRIES:
            await asyncio.sleep(_BACKOFF * (2 ** i))
    if last is None and last_exc is not None:
        raise last_exc
    return last
```

- **429/5xx 重试**：限流退避，指数退避（1.5s → 3s → 6s）
- **连接层抖动也要重试**（注释）：早先只判状态码，`c.post` 抛出来直接冒到顶——上游回 503 会重试，**上游把连接掐了反而一次都不试**，eval-rag 跑 200 多题被断一次，十几分钟整轮白跑
- 连试几次还不行才抛出去——评估脚本会把这一轮记成失败，不静默算低分

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| dense query 与 bm25_text 分离 | 同义词扩展只作用于 BM25，不污染向量语义 |
| 子句拆分 + 轮转合并 | 一问多意图，一个意图不占满前排名额 |
| `acall` 固定单线程 | gRPC 客户端跨线程共享的间歇空返回 |
| 精排不进 Milvus 线程 | 同步线程不被网络等待卡死 |
| 手写 rerank 请求 | rerank 非 OpenAI 协议，是 Jina/Cohere 形状 |
| 连接层抖动纳入重试 | 上游掐连接一次都不试 → 整轮评估白跑 |
| `_rerank_url` 版本段兜底 | 地址少 /v1 时 404 且排障绕圈 |
