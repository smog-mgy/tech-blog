# 第 08 章：工具系统（MCP 接入与动态扩展）—— 项目落地笔记

**日期**：2026-09-08
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及源码：`app/tools/mcp_client.py`、`app/tools/registry.py`、`app/tools/engine.py`、`app/tools/builtin/`、`mcp_servers/spare_part_server.py`、`mcp_servers/ticket_ops_server.py`

## 场景从哪来

系统走到这，内置工具已经够用（建单、查单、FAQ），但运维场景马上提出新需求：用户问"SP-1004 变频器散热风扇还有没有货""我的工单到哪个节点了"。这些数据**不在主应用库里**，也不该硬塞进主进程——备件库存是 ERP 的事，工单流转是另一个系统的事。正确做法是把它们做成**独立的工具服务**，主应用通过 MCP 协议调用。

MCP 的价值一句话：**工具系统从"写死在内"变成"可扩展接入"**。主应用不用知道备件 Server 内部怎么实现，只要它暴露了 MCP 工具，就能注册、能调用、能被模型发现。

## 第一个真问题：接一个新 Server 就要重启服务？

MCP Server 是独立进程，理论上它加个新工具，主应用不该重启才知道。但早期实现把工具清单**缓存在启动时拉一次**，Server 侧加了工具，主应用不重启就永远看不见。

解决：改成**现问现拿**——`fetch_mcp_specs()` 在每次需要工具清单时现拉，`MultiServerMCPClient` 的 adapters 每次调用新建 session。于是 Server 侧加工具，服务系统**不重启即可见**。代价是每次多一次网络往返，用超时封顶兜住（下面讲）。

## 第二个问题：Server 挂了，对话被拖垮

两个 Server 是独立进程，随时可能没起来、被占用、假死。如果拉工具清单时一个 Server 卡住，整个对话就卡在那——用户等半天没回复，这是不能接受的。

处理分两层：

1. **超时封顶**：`asyncio.wait_for(..., timeout=settings.mcp_tool_timeout)`。注释里有个真实洞察："连接拒绝会快速失败，但 Server 假死（TCP 接了不回话）只受 adapters 默认超时保护——现问现拿每步都拉清单，最坏延迟必须封住"
2. **单台不可达/假死 → 告警 + 跳过**：`except Exception: logger.warning(...); continue`——这一台的工具本轮不注册，对话继续。**宁可少几个工具，不能让用户干等**

## 第三个问题：Server 自报"我是只读的"，你信吗

这是第 2 章权限原则在 MCP 场景的延续。MCP Server 返回的工具描述里会写自己"只读"还是"可写"，**但描述只是给模型看的参考**，能不能调由我们侧说了算：

```python
# 权限/格式化只认我们侧:Server 自报的用途描述仅供模型参考,
# 能不能调按 registry.WRITE_TOOLS。
```

写操作白名单 `WRITE_TOOLS = {"create_ticket"}` 依然按名字生效——哪怕哪天接入一个自报可写的 Server，它也不在白名单里，写操作照样调不动。**外部 Server 的自我描述永远不构成权限依据。**

## 第四个问题：Server 返回的原始 JSON，模型不会组织

备件 Server 返回 `{"found": True, "spare_no": "SP-1004", "name": "变频器散热风扇", "stock": 2, "eta": "现货", "status": "在库"}` 这种结构，直接回灌给模型，它组织出来的话术往往啰嗦、还可能把内部字段（比如 `found` 标志）原样念出来。

解决：**结果格式化我们侧登记**。`FORMATTERS` 表里注册每个工具的格式化函数，只挑回答用得上的字段、把内部枚举码翻成人话：

```python
def _fmt_spare_part(data: dict) -> str:
    if not data.get("found"):
        return f"未找到备件 {data.get('spare_no')}"
    return (f"{data.get('name')}:库存 {data.get('stock')} 件,"
            f"{data.get('eta')},{data.get('status')}")

FORMATTERS = {
    "query_spare_part": _fmt_spare_part,
    "query_spare_list": _fmt_spare_list,
    "query_ticket_progress": _fmt_ticket_ops,
}
```

没登记的 MCP 工具透传原始结果。**格式化也是"我们侧"的职责，不指望 Server 输出就是人话。**

## 第五个问题：工具调用失败，谁说了算

`get_client()` 里有个关键参数：

```python
_client = MultiServerMCPClient(_connections(), handle_tool_errors=False)
```

`handle_tool_errors=False` 意味着工具错误会抛 `ToolException`，**由执行引擎统一分诊/回灌**，而不是 MCP 适配层悄悄处理掉。这和第 2 章的"框架负责执行"一脉相承：错误怎么归类、要不要重试、怎么回给模型，全在一个地方定。

## Server 侧怎么写：FastMCP 最小实现

MCP Server 本身不复杂，核心就是装饰器 + 暴露 HTTP 端点：

```python
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("spare_part")

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

三个要点：

- **docstring 就是工具描述**：FastMCP 把函数 docstring 转成工具 Schema 的 description，喂给模型——所以 docstring 要写"传什么、返回什么、给个例子"，这是给模型看的，不是写给人看的
- **返回统一结构**：`found` 标志 + 数据字段，让我们侧格式化函数好判断
- **固定台账数据**：目前是模拟数据（SP-1001~SP-1005），注释写明"接入真实 ERP 时替换为查询逻辑"——改造时数据边界要留好

## 内置工具和 MCP 工具怎么共存

`app/tools/builtin/` 下是本地内置工具（faq、tickets、tickets_query、ticket_confirm），MCP 的是外部服务。它们最终都统一转成同一种 `ToolSpec`：

```python
registry.spec_from_langchain_tool(t, source="mcp", mcp_server=server, format_result=FORMATTERS.get(t.name))
```

模型看到的是统一格式的工具清单，**不需要区分内置还是 MCP**；执行引擎按 ToolSpec 统一调度。差别只在 source 标签（内置/MCP）和归属的 server，方便日志与权限判断。

## 这章埋过的坑

1. **工具清单启动时缓存** → Server 加工具不重启看不见 → 现问现拿
2. **Server 假死拖垮对话** → 超时封顶 + 单台不可达告警跳过
3. **信任 Server 自报的只读/可写** → 权限只认我们侧白名单
4. **原始 JSON 直接回灌** → 我们侧格式化登记，挑字段翻人话
5. **工具错误被适配层悄悄吞掉** → `handle_tool_errors=False`，错误归执行引擎统一分诊

## 怎么验证

```bash
# 工具/MCP 相关测试
& "D:\Pythonproject\mewhelp\.venv\Scripts\python.exe" -m pytest tests/tools/ -q

# 起全套（make dev 会拉起 :8101 / :8102 两个 MCP Server）
# 实测：
# "SP-1004 变频器散热风扇有货吗" → MCP 备件查询
# "我的工单 WO-2026-0001 到哪个节点了" → MCP 工单流转
# 停掉一个 MCP Server 再问 → 应跳过该工具正常回复，不卡死
```
