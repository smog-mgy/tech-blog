# 第 02 章：Function Calling 工具链（源码解析）

**日期**：2026-08-16
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 02 章：Function Calling 工具链（项目落地笔记）.md`
> 本解析逐段走读工具注册中心、权限白名单与 mock 数据源。

## 涉及文件

| 文件 | 职责 |
|---|---|
| `app/tools/registry.py` | 工具注册中心：内置 + MCP 统一登记 ToolSpec |
| `app/tools/engine.py` | 执行引擎：分诊、重试、注入 |
| `app/tools/business.py` | mock 数据源：固定种子纯函数 + 归属判定 |
| `app/tools/builtin/` | 内置工具实现（注册即定义） |

## registry.py 逐段走读

### 权限白名单：我们侧独裁

```python
WRITE_TOOLS: set[str] = {"create_ticket"}
```

注释点明两件事：

- **写清单按名字定**；未登记（含所有 MCP 工具）一律按只读放行
- 生产环境接不受信 Server 时应默认拒绝未知写操作；本项目两台自建 Server 都是查询类，只读放行足够

### ToolSpec：工具的完整画像

```python
@dataclass
class ToolSpec:
    name: str
    description: str
    json_schema: dict            # 参数 JSON Schema(校验用;模型可见口径,不含注入参数)
    tool: BaseTool
    permission: str              # "read" | "write"
    source: str                  # "builtin" | "mcp"
    mcp_server: str | None = None
    timeout: float | None = None
    max_retries: int | None = None
    inject_conversation: bool = False
    inject_user_id: bool = False
    format_result: Callable[[dict], dict] | None = None
```

每个字段都有意义：

- **json_schema**：参数校验用，且注明"模型可见口径，不含注入参数"——注入参数对模型不可见（身份不是模型的输入）
- **permission**：由白名单推导（`permission_for(name)`）
- **source / mcp_server**：来源与归属，日志、权限判断的依据
- **timeout / max_retries**：`None → engine 按来源取默认`；`max_retries=0 = 不重试`（如 query_faq RAG 管线——重试整条 RAG 没意义）
- **inject_***：执行前注入（身份从可信通道来，不许模型填）

### _json_schema_of：两种工具的 Schema 口径统一

```python
def _json_schema_of(tool: BaseTool) -> dict:
    raw = getattr(tool, "args_schema", None)
    if isinstance(raw, dict):
        return raw                          # MCP 工具:args_schema 本就是 dict
    tcs = getattr(tool, "tool_call_schema", None) or raw   # 内置工具:pydantic 模型
    return tcs.model_json_schema()
```

- **MCP 工具**：`args_schema` 本来就是 dict，直接用
- **内置工具**：pydantic 参数模型，转 JSON Schema 时用 `tool_call_schema`——**它排除了 `InjectedToolArg`（注入参数），保证给模型看的口径里没有身份字段**。如果误用完整 args_schema，注入参数会暴露给模型

### register / scan_builtin：注册即定义

```python
def register(spec: ToolSpec) -> None:
    if spec.name in _BUILTIN:
        logger.warning("工具重名,丢弃后注册者 name=%s(先到者保留)", spec.name)
        return
    _BUILTIN[spec.name] = spec

def scan_builtin() -> None:
    global _scanned
    if _scanned:
        return
    _scanned = True
    from app.tools import builtin as pkg
    for m in pkgutil.iter_modules(pkg.__path__):
        try:
            importlib.import_module(f"{pkg.__name__}.{m.name}")
        except Exception:
            logger.exception("内置工具模块导入失败,跳过 module=%s", m.name)
    logger.info("内置工具注册完成:%s", sorted(_BUILTIN))
```

- **重名丢弃后注册者、先到者保留**：防两个模块注册同名工具互相覆盖
- **`scan_builtin` 幂等**（`_scanned` 标志）：服务启动（lifespan）调用一次
- **import 即注册**：builtin/ 包下每个模块被 import 时自己调 `register`——加一个文件就是加一个工具，删文件即插即用
- **坏文件跳过告警**：`except Exception` 后跳过该模块，不拖垮其余工具注册——工具系统对单点故障有容忍

## business.py 逐段走读

### ticket_snapshot：可复现的 mock

```python
def ticket_snapshot(ticket_id: str) -> dict:
    rng = random.Random(f"ticket:{ticket_id}")
    return {
        "ticket_id": ticket_id,
        "status": rng.choice(["待派单", "处理中", "待配件", "已解决", "已关闭"]),
        "priority": rng.choice(["P1", "P2", "P3"]),
        "fault_type": rng.choice(["电气故障", "机械故障", "程序故障", "通信故障"]),
        "device": rng.choice(["M-1001 三相异步电机", "PLC-2002 西门子S7-1200",
                              "VFD-3005 变频器", "TS-4001 温度传感器", "PU-1002 空压机"]),
        ...
    }
```

- **`random.Random(f"ticket:{ticket_id}")`**：以工单号为种子的独立随机源——同一工单号永远返回同一份快照（状态、优先级、故障类型、设备、产线、处理人整套稳定）
- **为什么可复现这么重要**：测试、评估、演示都要稳定对比；随机数据每次不一样，没法验证"改没改坏"
- 数据全部是运维域（电气/机械/程序故障、M-1001 电机、VFD-3005 变频器）——mock 也贴合业务

### owns_ticket：归属判断唯一一处

```python
def owns_ticket(user_id: str, ticket_id: str) -> bool:
    if not user_id or not ticket_id:
        return False
    return any(t["ticket_id"] == ticket_id for t in list_user_tickets(user_id))
```

- **空 user_id 一律不放行**：注释点破——"身份是注入进来的，注入没接上就是空串，那种情况下放行等于没做校验"
- **归属判断只有这一处**：工具和节点都调它，不各判各的（第 6 章 fetch_ticket 节点也走这里）
- 判定逻辑：这张工单在不在该用户的名下单里

### DEMO_TICKET_IDS 与 list_user_tickets

```python
DEMO_TICKET_IDS = ("WO-2026-0001", "WO-2026-0002")

def list_user_tickets(user_id: str) -> list[dict]:
    rng = random.Random(f"user_tickets:{user_id}")
    ids = list(DEMO_TICKET_IDS)
    for _ in range(rng.randint(2, 4)):
        oid = f"WO-2026-{rng.randint(1, 9999):04d}"
        if oid not in ids:
            ids.append(oid)
    out = []
    for tid in ids:
        s = ticket_snapshot(tid)
        out.append({"ticket_id": tid, "device": s["device"], "status": s["status"],
                    "priority": s["priority"], "fault_type": s["fault_type"]})
    return out
```

- **演示单固定**：文档、curl 例子、各章评估脚本到处写 WO-2026-0001/0002，每个账号名下都有这两笔，例子拿来即跑
- **想看归属校验拦人**：报 WO-2026-9999（不在任何用户名下）就被挡下
- **按 user_id 稳定**：同一用户每次返回同一批单子（`user_tickets:{user_id}` 种子）
- 每笔用 `ticket_snapshot` 同源——前端选中后回填 ticket_id 即可 query_ticket，数据一致

## engine 的衔接（要点）

- **分诊**：业务异常（如工单不存在）如实回灌给模型修正/如实相告，不编造；暂时性故障（超时/连接）重试
- **`_TRANSIENT` 重试清单**：`(asyncio.TimeoutError, TimeoutError, ConnectionError, httpx.TransportError)`——只有瞬时故障值得重试
- **注入**：执行前按 `inject_user_id` / `inject_conversation` 把身份、会话从可信通道注入
- **审计**：写操作落工具审计日志

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| `WRITE_TOOLS` 名字白名单 | 权限我们侧独裁，Server 自报不构成权限依据 |
| `tool_call_schema` 排除注入参数 | 给模型的 Schema 里没有身份字段 |
| import 即注册 + 幂等扫描 | 加文件即加工具，删文件即插即用 |
| 固定种子纯函数 mock | 测试/评估/演示可复现 |
| `owns_ticket` 唯一判定点 | 工具和节点不各判各的 |
| 空 user_id 不放行 | 注入没接上时放行等于没做校验 |
