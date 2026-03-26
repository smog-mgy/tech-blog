# 写 Todo 命令行项目的收获

**日期**：2026-04-02
**标签**：Python · 项目实战 · OOP

## 为什么做这个项目

> 阶段 0 学了 Python 基础、面向对象、模块化、Git，但都是零散的知识点，没有完整做过一个项目。
>
>  Todo 清单项目虽然小，但五脏俱全——有需求、有代码、有数据存储、有命令行交互，完整走了一遍从 0 到 1 的开发流程。
>

---

## 一、项目回顾

**功能**：命令行 Todo 清单
- `python todo.py add "买牛奶"` → 添加任务
- `python todo.py list` → 列出所有任务
- `python todo.py done 1` → 标记任务完成
- 任务存到 JSON 文件，关掉再开还在

**项目结构**：
```
todo/
├── todo.py       # 主程序
├── README.md     # 项目说明
└── tasks.json    # 任务数据
```

---

## 二、用到的知识点

### 1. 面向对象（OOP）

把所有任务操作封装成 `TaskList` 类：
- `__init__`：初始化时加载已有任务
- `add`：添加新任务
- `list_tasks`：列出所有任务
- `done`：标记任务完成
- `save` / `load`：JSON 持久化

**理解加深**：
- 类就是把数据和操作数据的方法打包在一起
- `self` 就是"这个对象自己"，调用方法时自动传
- 之前学的 `__init__`、`self`、实例方法，在这个项目里全用上了

### 2. 文件读写（JSON 持久化）

```python
# 写文件
with open(self.filename, "w", encoding="utf-8") as f:
    json.dump(self.tasks, f, ensure_ascii=False, indent=2)

# 读文件
with open(self.filename, "r", encoding="utf-8") as f:
    self.tasks = json.load(f)
```

**踩的坑**：
- 一开始忘了 `ensure_ascii=False`，中文都变成 `\u4e70\u725b\u5976` 这种编码
- 后来加上 `ensure_ascii=False` 才正常显示中文

### 3. 命令行参数解析

```python
import sys

# 用户输入：python todo.py add "买牛奶"
# sys.argv = ['todo.py', 'add', '买牛奶']
```

**理解加深**：
- `sys.argv[0]` 是脚本名本身
- `sys.argv[1]` 是第一个参数（命令）
- `sys.argv[2]` 是第二个参数（任务内容）

### 4. 错误处理

```python
try:
    task_index = int(sys.argv[2])
    todo.done(task_index)
except ValueError:
    print("❌ 任务 ID 必须是数字")
```

**为什么要加**：如果用户输入 `done abc`，程序会直接崩溃，加了 try/except 就友好多了。

---

## 三、踩过的坑

### 坑 1：第一次运行时文件不存在

**问题**：`__init__` 里直接读文件，第一次运行 `tasks.json` 不存在，报错。

**解决**：

```python
if os.path.exists(self.filename):
    with open(...) as f:
        self.tasks = json.load(f)
```

**教训**：写文件操作前，先判断文件存不存在。

### 坑 2：任务 ID 重复

**问题**：每次 add 都从 1 开始，新任务会覆盖旧任务。

**解决**：
```python
new_id = max([t["id"] for t in self.tasks], default=0) + 1
```

**教训**：ID 要自动递增，不能写死。

### 坑 3：中文乱码

**问题**：存到 JSON 里的中文变成了 Unicode 编码。

**解决**：`json.dump(..., ensure_ascii=False)`

**教训**：处理中文一定要加 `ensure_ascii=False`。

---

## 四、这个项目的意义

> 虽然这个项目很小，但它完整走了一遍开发流程：
>
> 1. **需求分析**：搞清楚要做什么功能
> 2. **设计类结构**：想清楚 TaskList 类要有哪些方法
> 3. **写代码**：一个方法一个方法地实现
> 4. **测试**：自己用一遍，看有没有 bug
> 5. **写 README**：让别人知道怎么用
> 6. **推到 GitHub**：有版本记录了

**能力的提升**

- "写了一个命令行 Todo 工具，用类组织代码，JSON 持久化存储"
- "遇到过中文乱码的问题，用 ensure_ascii=False 解决了"
- "用 sys.argv 解析命令行参数，支持 add/list/done 三个命令"

---

## 五、下一步可以做什么

这个项目还有很多可以扩展的地方：
- 加 `delete` 命令，删除任务
- 加 `edit` 命令，编辑任务
- 加 `clear` 命令，清空所有已完成任务
- 换成用 SQLite 存储，而不是 JSON 文件
- 加个简单的 Web 界面
