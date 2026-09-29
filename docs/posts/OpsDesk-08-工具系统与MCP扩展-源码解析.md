# 第 08 章：工具系统（MCP 接入与动态扩展）（源码解析）

**日期**：2026-09-09
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 08 章：工具系统（MCP 接入与动态扩展）（项目落地笔记）.md`
> 本解析逐段走读 MCP 接入层与 Server 实现，讲清每个参数与分支为什么这么写。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/tools/mcp_client.py` | MCP 客户端：多 Server 接入、工具清单动态发现、结果格式化 |
| `app/tools/registry.py` | ToolSpec 统一模型、权限白名单 |
| `app/tools/engine.py` | 执行引擎：分诊、重试、回灌 |
| `mcp_servers/spare_part_server.py` | 备件库存 Server（:8101） |
| `mcp_servers/ticket_ops_server.py` | 工单流转 Server（:8102） |
| `app/tools/builtin/` | 本地内置工具（faq / tickets / tickets_query / ticket_confirm） |

## mcp_client.py 逐段走读

### 连接配置：两个独立进程

```python
def _connections() -> dict:
    return {
        "spare_part": {"transport": "streamable_http", "url": settings.mcp_spare_url},
        "ticket_ops": {"transport": "streamable_http", "url": settings.mcp_ticket_url},
    }
```

- `streamable_http`：MCP 的 HTTP 传输（Streamable HTTP），`url` 来自配置（`settings.mcp_spare_url` / `settings.mcp_ticket_url`）
- 两个 Server 用独立 key（`spare_part` / `ticket_ops`）标识，日志、权限判断都靠它
- 注释点明架构：**独立进程，由 make mcp-up 拉起**——不是主应用内的线程

### get_client：单例 + 错误处理策略

```python
_client: MultiServerMCPClient | None = None

def get_client() -> MultiServerMCPClient:
    global _client
    if _client is None:
        # handle_tool_errors=False:工具错误抛 ToolException,由执行引擎统一分诊/回灌
        _client = MultiServerMCPClient(_connections(), handle_tool_errors=False)
    return _client
```

- **懒加载单例**：首次调用才创建，进程内复用连接配置
- **`handle_tool_errors=False` 是本章最重要的一个参数**：默认 True 时 MCP 适配层会把工具错误包装成"工具返回了一段错误文本"继续流程，模型可能当成正常结果；设 False 后错误抛 `ToolException`，由执行引擎统一分诊（业务异常如实回灌、暂时性故障重试、审计记 log）——错误处理不散落在适配层

### 动态发现：现问现拿

```python
async def _get_tools_of(*, server_name: str):
    """薄壳:单测 monkeypatch 锚点。"""
    return await get_client().get_tools(server_name=server_name)

async def fetch_mcp_specs() -> list[ToolSpec]:
    specs: list[ToolSpec] = []
    for server in _connections():
        try:
            tools = await asyncio.wait_for(_get_tools_of(server_name=server),
                                           timeout=settings.mcp_tool_timeout)
        except Exception as e:
            logger.warning("MCP Server「%s」不可达,本轮跳过其工具:%s", server, type(e).__name__)
            continue
        for t in tools:
            specs.append(registry.spec_from_langchain_tool(
                t, source="mcp", mcp_server=server, format_result=FORMATTERS.get(t.name)))
    return specs
```

逐点拆：

1. **`_get_tools_of` 薄壳**：单独抽一层，就是为了单测里 monkeypatch 它，不用真的起 MCP Server——可测性设计，别小看
2. **每次调用都拉清单**（不缓存）：Server 侧加工具，主应用不重启即可见；代价是网络往返，所以：
3. **`asyncio.wait_for` 超时封顶**：`settings.mcp_tool_timeout`。注释里点破一个真实场景——"连接拒绝会快速失败，但 Server 假死（TCP 接了不回话）只受 adapters 默认超时保护"，默认超时往往太长（分钟级），对话不能等，必须我们侧封顶
4. **异常吞掉但告警**：单台 Server 不可达/假死，`logger.warning` 记录后 `continue`——**本轮跳过它的工具，对话继续**。绝不因为一个 Server 卡死拖垮整轮回复
5. **统一转 ToolSpec**：`spec_from_langchain_tool(t, source="mcp", mcp_server=server, ...)`，source 标记来源、mcp_server 标记归属，格式化函数从 FORMATTERS 按工具名取（取不到就是 None = 透传）

### 结果格式化：我们侧登记

```python
def _fmt_spare_part(data: dict) -> str:
    if not data.get("found"):
        return f"未找到备件 {data.get('spare_no')}"
    return (f"{data.get('name')}:库存 {data.get('stock')} 件,"
            f"{data.get('eta')},{data.get('status')}")

def _fmt_spare_list(data: dict) -> str:
    items = data.get("items") or []
    if not items:
        return "备件清单为空"
    rows = [f"{it.get('spare_no')} {it.get('name')}:库存 {it.get('stock')} 件,{it.get('eta')},{it.get('status')}"
            for it in items]
    return "；".join(rows)

def _fmt_ticket_ops(data: dict) -> str:
    if not data.get("found"):
        return f"未找到工单 {data.get('ticket_id')}"
    return (f"工单 {data.get('ticket_id')} 当前{data.get('node')},"
            f"处理人 {data.get('assignee')},预计 {data.get('eta')}")

FORMATTERS: dict = {
    "query_spare_part": _fmt_spare_part,
    "query_spare_list": _fmt_spare_list,
    "query_ticket_progress": _fmt_ticket_ops,
}
```

设计要点：

- **只挑回答用得上的字段**：原始返回里可能有 count、message 等内部字段，格式化只保留 name/stock/eta/status 这类模型组织话术要用的
- **内部标志翻人话**：`found=False` → "未找到备件 xxx"，比让模型解读布尔标志强
- **`；` 连接列表**：清单工具逐条拼成一行（备件数量少，一行够用，省 token）
- **未登记的工具透传**：FORMATTERS 取不到就是 None，spec 的 format_result 为空，engine 原样回灌

## spare_part_server.py 逐段走读

### FastMCP 最小骨架

```python
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("spare_part")

SPARE_PARTS = { ... }  # 固定模拟台账

@mcp.tool()
def query_spare_part(spare_no: str) -> dict:
    """查询备件库存:传入备件编号(如 SP-1001),返回库存余量、到货时间与领用状态。"""
    p = SPARE_PARTS.get(spare_no.upper())
    if not p:
        return {"found": False, "spare_no": spare_no, "message": "未找到该备件,请核对编号"}
    return {"found": True, "spare_no": spare_no.upper(), **p}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(mcp.streamable_http_app(), host="127.0.0.1", port=8101)
```

逐点拆：

- **`@mcp.tool()` 装饰器**：把函数注册成 MCP 工具；**docstring 即工具描述**，FastMCP 自动转成 Schema 的 description——这就是给模型看的"使用说明"，写清"传什么、返回什么、例子"
- **入参就是 Schema**：`spare_no: str` 自动成为必填参数定义；带默认值的 `keyword: str = ""` 成为可选参数
- **`spare_no.upper()` 归一**：用户可能报小写，Server 侧兜底转大写，避免大小写不一致查不到
- **返回统一结构**：`found` 布尔标志 + 业务字段 + message——这是我们侧格式化函数判断的契约
- **`mcp.streamable_http_app()`**：把 FastMCP 应用包装成 ASGI app，uvicorn 托管在 :8101
- **固定台账**：`SPARE_PARTS` 是模拟数据（注释写明"接入真实 ERP 时替换为查询逻辑"），改造时的数据边界清晰

### 第二个工具：按关键词过滤清单

```python
@mcp.tool()
def query_spare_list(keyword: str = "") -> dict:
    kw = keyword.strip()
    items = []
    for no, p in SPARE_PARTS.items():
        if not kw or kw in p["name"]:
            items.append({"spare_no": no, **p})
    return {"count": len(items), "items": items}
```

- 可选参数 `keyword`（空 = 全量）
- 匹配逻辑：`kw in p["name"]` 子串包含（中文场景够用）
- 返回 `count + items`，让格式化函数能判断空清单

## 与 registry / engine 的衔接

内置工具与 MCP 工具最终汇流到**同一种 ToolSpec**：

```python
# registry.py 里（示意）
spec_from_langchain_tool(t, source="mcp", mcp_server=server, format_result=...)
```

- 模型看到的工具清单不区分内置/MCP——统一 Schema、统一描述
- 权限判断统一按 `registry.WRITE_TOOLS`（按名字），MCP Server 自报的描述不构成权限依据
- 执行统一走 engine：错误分诊（ToolException）、暂时性故障重试、结果格式化、审计 log

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| 现问现拿（不缓存工具清单） | Server 加工具，主应用不重启即可见 |
| `asyncio.wait_for` 超时封顶 | Server 假死（TCP 接了不回话）不拖垮对话 |
| 单台不可达告警跳过 | 一个 Server 挂了，其余工具照常可用 |
| `handle_tool_errors=False` | 工具错误抛 ToolException，执行引擎统一分诊/回灌 |
| FORMATTERS 我们侧登记 | 原始 JSON 挑字段、翻人话，模型好组织话术 |
| 统一 ToolSpec + source 标记 | 内置/MCP 共存，日志与权限有据可查 |
