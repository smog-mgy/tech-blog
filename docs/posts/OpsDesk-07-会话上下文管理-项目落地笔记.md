# 第 07 章：会话上下文管理 —— 项目落地笔记

**日期**：2026-09-04
**标签**：AI Agent · OpsDesk · 项目落地笔记


> 涉及源码：`app/core/memory.py`、`app/core/summarizer.py`、`app/graph/nodes.py`、`app/graph/state.py`

## 先搞清楚问题本身

上一章指代消解已经用到历史了，但这章要解决的问题更基础也更难：**模型是无状态的，每轮对话它都"失忆"，而它能塞进上下文窗口的内容是有限的**。运维客服场景里，用户可能隔十几轮才问"那我最开始报修的那台设备修好了吗"——这时候早期信息早就滑出窗口了。

最朴素的做法是把全部历史每次全喂给模型：token 很快撑爆、费用暴涨、模型注意力被无关旧消息稀释。所以这章的目标拆成两个：

1. **近期原文要留**：滑窗内最近几轮完整保留，供指代消解、意图分类读细节
2. **早期事实要存**：最早的关键事实（报修了什么设备、工单号多少、承诺过什么）不能丢，压缩成摘要长期带着

于是有了"**摘要层 + 滑窗层**"的双层结构。

## 第一次尝试：纯 token 裁剪，把关键信息切没了

早期实现简单粗暴：`trim_history` 直接按 token 上限从后往前留（`strategy="last"`，`start_on="human"` 保证窗口从用户消息开始、`allow_partial=False` 不切半条消息）。

问题很快暴露：**窗口一滑，早期事实就丢了**。"最开始那个工单"这种指代，模型翻遍滑窗都找不到——上一章的摘要行兜底也就兜了个寂寞，因为根本没有摘要。对话一长，前面说的全白说。

## 双层结构的核心：锚点切窗

解决思路：**摘要不是随便什么时候做，而是有明确边界的**。每条消息入库时带上 MySQL 消息 id（约定 `HumanMessage.id = f"db-{msg_id}"`），state 里记一个 `summary_upto_msg_id` 边界——**边界之前的消息已被压缩进摘要，滑窗只从边界之后的第一条用户消息开始取**：

```python
def build_window(messages, summary_upto_msg_id, max_tokens):
    start = 0
    if summary_upto_msg_id:
        for i, m in enumerate(messages):
            if isinstance(m, HumanMessage):
                did = _db_msg_id(m)
                if did is not None and did > summary_upto_msg_id:
                    start = i
                    break
    window = messages[start:]
    trimmed = trim_history(window, max_tokens=max_tokens)
    return trimmed or window
```

两个细节值得说：

- **锚点缺失（旧会话）或边界为 0**：整段进 trim，退化回纯 token 裁剪——新老数据兼容，不崩
- **裁到空宁可超预算回退原窗**：`return trimmed or window`——宁可多用点 token 也不能把刚说的关键话裁没。安全方向优先

配合 `summary_line`（"早前对话摘要:..."单行前缀，喂给指代消解/意图分类）和 `summary_system`（"## 早前对话摘要(更早轮次已压缩,其中事实可信)" SystemMessage，喂给主力 Agent），摘要和原文各就其位。

## 摘要怎么做：后台滚动，不阻塞回复

摘要本身是 LLM 调用，如果同步做会拖慢当轮回复。所以设计成**轮结束后异步跑**：

- **触发**：`maybe_schedule_summary(conversation_id)` 在每轮回复完成后调用，新增消息数达到阈值且没有在跑任务才 `create_task` 后台跑，**不 await，不阻塞**
- **防抖**：`_running: dict[int, asyncio.Task]`，同一会话在跑就不重复起
- **失败只 log 不重试**：触发条件仍然满足，下一轮自然重触发——没必要在用户回复路径上做重试
- **原子更新**：summary 和 boundary 两个字段只在成功后一起更新，绝不出现"摘要写了、边界没动"的中间态

`run_summary` 的任务流水线：

```
读会话 → 读全部消息 → 算新边界 → 边界没推进就放弃
→ 取 (old_upto, boundary] 之间的消息当新滑出段
→ 旧摘要 + 新滑出段 → LLM 滚动重写 → 新摘要
→ 原子更新 summary + summary_upto_msg_id
```

## 边界怎么算

`compute_boundary`：新摘要边界 = 倒数第 `keep_turns` 轮用户消息的**前一条消息 id**（滑窗从其后接原文）。不足 `keep_turns` 轮 / 边界落在会话开头 → 放弃本次：

```python
user_idx = [i for i, m in enumerate(messages) if m.role == "user"]
if len(user_idx) <= keep_turns:
    return None
cut = user_idx[-keep_turns]
if cut == 0:
    return None
return messages[cut - 1].id
```

为什么取"前一条 id"而不是用户消息本身？因为滑窗要从**边界之后的第一条用户消息**开始，边界指向倒数第 keep_turns 轮用户消息之前的位置，正好保住最近 keep_turns 轮完整原文。

## 摘要的质量怎么保证

`summarize_dialog` 用结构化输出，约束摘要**只含事实与诉求**：

```python
class _Summary(BaseModel):
    summary: str = Field(description="早期对话滚动摘要,只含事实与诉求")
```

- **滚动重写**：不是把全部历史重新总结（越滚越长），而是"旧摘要 + 新滑出段"合成新摘要，摘要长度有界
- **只留事实**：报修了什么、工单号、承诺、诉求——情绪化内容、寒暄一律不要，摘要保持干净
- 摘要模型可以单独指定（`settings.summary_model`），跟对话模型解耦

## 这章埋过的坑

1. **纯 token 裁剪把早期事实切没** → 锚点切窗，按边界分段
2. **同步摘要拖慢回复** → 后台异步 + 计数触发 + 防抖
3. **摘要/边界分开更新会有中间态** → 两字段原子更新，只在成功后落库
4. **摘要越滚越长** → 滚动重写，长度有界
5. **裁到空** → 宁可超预算回退原窗，安全优先

## 怎么验证

```bash
# 上下文管理相关测试
& "D:\Pythonproject\mewhelp\.venv\Scripts\python.exe" -m pytest tests/test_memory.py tests/test_summarizer.py -q

# 起应用后长对话实测：
# 连续聊十几轮（中间穿插无关话题），再问"我最开始报修的那个工单现在什么状态"，
# 应能靠摘要层回答出来，而不是失忆
```
