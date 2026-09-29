# 第 03 章：RAG 基础，跑通全链路（源码解析）

**日期**：2026-08-20
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 03 章：RAG 基础，跑通全链路（项目落地笔记）.md`
> 本解析逐段走读知识库切分与文档处理层，这是 RAG 质量的地基。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/kb/chunking.py` | 切分：结构感知 + 中文分隔符 + 句子级重叠 + 表格处理 |
| `app/kb/documents.py` | 文档处理：按节切 → 表格/文本分治 → Chunk 组装 + 关键条款打标 |
| `app/kb/milvus_client.py` | Milvus 集合与向量入库 |
| `app/core/retrieval.py` | 在线检索（本解析只涉及基础路） |

## chunking.py 逐段走读

### 中文优先的分隔符

```python
HEADERS = [("#", "h1"), ("##", "h2"), ("###", "h3"), ("####", "h4")]
# 中文无词边界,分隔符优先段落/换行,再句末标点,最后逐字
CJK_SEPARATORS = ["\n\n", "\n", "。", "！", "？", "；", "!", "?", ";", "，", " ", ""]
```

- 英文切分按空格/标点，**中文没有词边界**——所以分隔符顺序重排：段落（\n\n）→ 换行 → 句末标点（。！？；）→ 逗号 → 空格 → 逐字兜底
- `RecursiveCharacterTextSplitter` 按这个顺序从前往后试，越靠前优先级越高

### 结构感知切分：顺着标题切

```python
def split_sections(md: str) -> list[Document]:
    splitter = MarkdownHeaderTextSplitter(headers_to_split_on=HEADERS, strip_headers=True)
    return splitter.split_text(md)
```

- `headers_to_split_on`：按 # ~ #### 四级标题切
- `strip_headers=True`：标题本身从正文剥离，但保留进 metadata（h1/h2/h3/h4）——**标题路径就是后面 section_path 的来源**
- 为什么必须按标题切：安全规程从中间被硬切两半，检索命中前半句"停电、验电、挂牌上锁三步"，后半句"母线电容仍带电严禁开盖"就落到别的块——模型敢答"断完电直接开盖"。**顺着标题切保住语义完整性，这是 RAG 的安全底线**

### 句子级重叠：不切半截话

```python
_SENT_RE = re.compile(r"[^。！？!?…\n]*[。！？!?…\n]|[^。！？!?…\n]+$")

def _split_sentences(text: str) -> list[str]:
    return [m for m in _SENT_RE.findall(text) if m]

def _trailing_sentences(text: str, max_chars: int) -> str:
    out: list[str] = []
    total = 0
    for s in reversed(_split_sentences(text)):
        if out and total + len(s) > max_chars:
            break
        out.insert(0, s)
        total += len(s)
    return "".join(out)

def apply_sentence_overlap(chunks: list[str], overlap: int) -> list[str]:
    if not chunks:
        return []
    out = [chunks[0]]
    for i in range(1, len(chunks)):
        ov = _trailing_sentences(chunks[i - 1], overlap)
        out.append(ov + chunks[i] if ov else chunks[i])
    return out
```

- **`_SENT_RE`**：匹配「非句末标点序列 + 句末标点/换行」，结尾残留无标点也收（`[^...]+$`）
- **`_trailing_sentences`**：从结尾往前取若干**完整句**，总长尽量不超 max_chars；**单句超长则整句保留**（优先"不留半截话"）——半截句会让模型读到残缺语义
- **`apply_sentence_overlap`**：相邻两块，把上一块结尾的完整句补到下一块开头——一个问题证据落在上一块结尾时，检索到下一块也能带上上下文

### 表格处理：按行切 + 重贴表头

```python
_TABLE_SEP_RE = re.compile(r"^\s*\|?[\s:|-]+\|?\s*$")

def _find_table_header(lines: list[str]) -> int:
    for i in range(len(lines) - 1):
        if (lines[i].lstrip().startswith("|")
                and _TABLE_SEP_RE.match(lines[i + 1]) and "-" in lines[i + 1]):
            return i
    return -1
```

- **表格判定**：行以 `|` 开头，且下一行是 `---` 分隔行（`[\s:|-]+` 匹配 markdown 表分隔符）——这是 markdown 表格的结构特征
- **允许表头前有散文行**：不再要求首行即表头（注释：表格前可能有几句前言），`_find_table_header` 找到第一个"表头 + 分隔行"组合

```python
def split_table_rows(table_md: str, max_rows: int) -> list[str]:
    lines = [ln for ln in table_md.strip().splitlines() if ln.strip()]
    idx = _find_table_header(lines)
    if idx == -1:
        return [table_md.strip()]
    preamble, header, sep, rows = lines[:idx], lines[idx], lines[idx + 1], lines[idx + 2:]
    if len(rows) <= max_rows:
        return [table_md.strip()]
    out: list[str] = []
    for j, i in enumerate(range(0, len(rows), max_rows)):
        group = rows[i:i + max_rows]
        block = [*preamble, header, sep, *group] if j == 0 else [header, sep, *group]
        out.append("\n".join(block))
    return out
```

- 大表格按 `max_rows` 行切
- **每块重贴表头 + 分隔行**：块独立可读（模型不会因为缺表头不知道列是什么）
- **表头前的散文行作为前言保留在首块**：不丢，后续块只带表头

## documents.py 逐段走读

### 关键条款打标：公共名导出

```python
_KEY_TERMS = ("报修", "工单", "故障", "时效", "巡检", "维保", "备件", "安全", "合同", "设备")
KEY_TERMS = _KEY_TERMS   # ch09 起跨模块复用(confidence 关键条款信号 / review 写回打标),导出公共名

def _is_key(title: str, body: str) -> int:
    head = title + body[:40]
    return int(any(t in head for t in _KEY_TERMS))

is_key = _is_key   # ch09 起跨模块复用,导出公共名
```

- **判定范围**：标题 + 正文前 40 字——关键条款通常在开头声明（"报修时效 P1 4 小时"这种句式）
- **为什么导出公共名**：ch09 置信度信号（关键条款命中）、审核写回打标都用它——**一个判断逻辑只写一处**，各模块 import `KEY_TERMS` / `is_key`

### Chunk：入库单元

```python
@dataclass
class Chunk:
    category: str        # 政策/手册用上级标题路径
    questions: str       # 小节标题（当检索的问题字段）
    answer: str          # 正文
    section_path: str    # 完整标题路径（"常见故障排查手册 / 电机过热报警怎么排查"）
    content_type: str
    is_key_clause: int = 0
```

- **questions = 小节标题**：检索时"问题"字段匹配——标题本身就是最好的问题表达
- **section_path**：完整标题路径，检索结果的引用展示用（前端可点、回答标来源编号）

### build_chunks：总调度

```python
def build_chunks(md, content_type, chunk_size=400, overlap=60, table_max_rows=10) -> list[Chunk]:
    out: list[Chunk] = []
    for sec in chunking.split_sections(md):
        path = [sec.metadata[k] for k in ("h1", "h2", "h3", "h4") if sec.metadata.get(k)]
        section_path = " / ".join(path)
        title = path[-1] if path else content_type
        category = " / ".join(path[:-1]) if len(path) > 1 else (path[0] if path else content_type)
        body = sec.page_content.strip()
        if not body:
            continue
        if chunking.is_table_block(body):
            pieces = chunking.split_table_rows(body, table_max_rows)
        else:
            base = chunking.recursive_split(body, chunk_size, chunk_overlap=0)
            pieces = chunking.apply_sentence_overlap(base, overlap)
        for piece in pieces:
            out.append(Chunk(category=category, questions=title, answer=piece,
                             section_path=section_path, content_type=content_type,
                             is_key_clause=_is_key(title, piece)))
    return out
```

处理流水线：

1. **按节切**：split_sections 得到带标题 metadata 的节
2. **提取路径**：h1~h4 拼成 section_path；title = 末级标题；category = 上级路径（政策/手册按上级归类，顶层无上级用 content_type）
3. **空节跳过**（`if not body: continue`）
4. **表格/文本分治**：表格走按行切 + 重贴表头；文本走递归切分（重叠 0）→ 句子级重叠补 60 字符
5. **组装 Chunk**：每个 piece 带齐 category/questions/answer/section_path/content_type/is_key_clause

**这个函数是 RAG 的"出厂配置"**：最终入库的每一块，都带着标题路径、问题字段、关键条款标记——后面检索、证据、引用、置信度全在这套结构上工作。

## 与 retrieval / milvus 的衔接

- `milvus_client`：按 `content_type` 建集合/分区，Chunk 向量化入库（bge-m3 嵌入，第 4 章详细）
- `retrieval.search_knowledge`（基础路）：查询向量化 → Milvus 召回 → 按 score 排序 → 拼编号证据（`[1]`、`[2]`）→ 注入 Prompt，模型按证据回答并标来源编号

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| CJK_SEPARATORS 中文优先 | 中文无词边界，英文分隔符会切烂 |
| 按标题层级切分 | 安全规程被硬切两半 → 模型答出"断完电直接开盖" |
| 句子级重叠（单句超长整句保留） | 块间丢上下文，且不切半截话 |
| 表格按行切 + 重贴表头 | 大表格进向量库丢失列语义 |
| is_key_clause 标题+正文前 40 字 | 关键条款（时效/费用/安全）可被下游识别复用 |
| Chunk 带 questions/section_path | 检索、引用、证据展示的数据结构一次建好 |
