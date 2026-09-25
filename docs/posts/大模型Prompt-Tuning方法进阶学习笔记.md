# 大模型 Prompt-Tuning 方法进阶学习笔记

> 主题：超大规模模型的三种 Prompt 方法（ICL / Instruction-Tuning / CoT）+ PEFT 参数高效微调（Prefix / Adapter / LoRA）

**前置**：当模型超过 10 亿参数后，**只需要设计合适的模板或指令，就能免参数训练实现零样本学习**。

---

## 一、超大规模参数模型 Prompt-Tuning 方法（总览）

**为什么大模型上 Prompt-Tuning 比标准 Fine-tuning 增益高？**

> 根本原因：模型参数量足够大 + 训练使用了足够多的语料 + 设计的预训练任务足够有效。

面向超大规模模型的三种方法：

| 方法 | 核心思想 |
|---|---|
| **上下文学习 In-Context Learning（ICL）** | 直接挑选少量样本作为该任务的提示 |
| **指令学习 Instruction-Tuning** | 构建任务指令集，促使模型根据任务指令做出反馈 |
| **思维链 Chain-of-Thought（CoT）** | 给予或激发模型推理和解释的信息，以线性链式模式指导生成 |

---

## 二、上下文学习（In-Context Learning，ICL）

### 2.1 概念

- 最早在 **GPT-3** 中提出
- 目的：从训练集**挑选少量标注样本**，设计任务相关指令形成提示模板，指导测试样本生成结果
- **不修改模型参数**，把例子直接拼在输入前面

### 2.2 三种学习方式（必考区分）

| 方式 | 做法 |
|---|---|
| **Zero-shot**（零样本） | 只给出任务描述 + 测试数据，直接预测（不给例子） |
| **One-shot**（单样本） | 任务描述 + **插入 1 个示例** + 测试数据 |
| **Few-shot**（小样本） | 任务描述 + **插入 N 个示例** + 测试数据 |

### 2.3 代码示例：三种方式的 prompt 构造

```python
# 以"情感分类"为例，看三种方式的 prompt 长什么样
def build_zero_shot(text):
    return f"判断下面句子的情感是正面还是负面：\n{text}\n情感："

def build_one_shot(text):
    demo = "这家餐厅的菜很好吃。\n情感：正面\n"
    return f"判断下面句子的情感是正面还是负面：\n{demo}{text}\n情感："

def build_few_shot(text, n=2):
    demos = [
        "这部电影太无聊了。\n情感：负面",
        "服务态度非常好。\n情感：正面",
    ][:n]
    demo_str = "\n".join(demos) + "\n"
    return f"判断下面句子的情感是正面还是负面：\n{demo_str}{text}\n情感："

text = "这家餐厅环境不错但价格太贵了。"
print("=== Zero-shot ===")
print(build_zero_shot(text))
print("\n=== One-shot ===")
print(build_one_shot(text))
print("\n=== Few-shot(2) ===")
print(build_few_shot(text, 2))

# 实际调用：把 prompt 发给模型即可，模型权重完全不变
# response = model.generate(build_few_shot(text))
```

> 记忆：**"给几个例子"决定叫法**——0 个=zero-shot，1 个=one-shot，N 个=few-shot。

---

## 三、指令学习（Instruction-Tuning）

### 3.1 什么是指令

**Instruction-Tuning 本质上也是对下游任务的指令**——告诉模型"需要做什么任务、输出什么内容"。

**Prompt vs Instruction 对比**（同一句话的两种问法）：

```
Prompt（补全式）：带女朋友去了一家餐厅，她吃的很开心，这家餐厅太__了！
Instruction（判别式）：判断这句话的情感：带女朋友去了一家餐厅，她吃的很开心。
    选项：A=好，B=一般，C=差
```

> **做判别比做生成更容易**——所以 Instruction 用"选项式"提问。

### 3.2 电影评论二分类例子

- 简单模板（Prompt）：`. It was [mask].`
- 加上任务特性（Instruction）：`The movie review is . It was [mask].`——通过 mask 位置输出经 Verbalizer 映射到标签

### 3.3 如何实现 Instruction-Tuning？

- 为每个任务**设计 10 个指令模板**，测试时看平均表现
- 关键：**必须对模型精调**，让模型知道这种指令模式

### 3.4 指令学习 vs 提示学习（必考区别）

| | Prompt | Instruction-Tuning |
|---|---|---|
| 激发能力 | 激发语言模型的**补全能力**（接下半句、完形填空） | 激发语言模型的**理解能力**（理解指令后做出正确 action） |
| 是否需要精调 | 未精调的模型也有一定效果 | **必须精调**，让模型学会指令模式 |

### 3.5 代码示例：指令 vs 提示 直观对比

```python
# 提示学习：让模型补全
prompt = "小明在考试中得了满分，他感到非常____。"

# 指令学习：让模型理解并判别
instruction = """请判断以下句子的情感倾向，只回答 A/B/C：
句子：小明在考试中得了满分。
A=开心  B=难过  C=平静
答案："""

print("Prompt 式：", prompt)
print("\nInstruction 式：")
print(instruction)

# 真实感受：补全式模型会接着写词，判别式模型会输出选项字母
```

---

## 四、思维链（Chain-of-Thought，CoT）

### 4.1 概念

- 首次提出于 Google 论文《Chain-of-Thought Prompting Elicits Reasoning in Large Language Models》
- **定义：改进的提示策略，提高 LLM 在复杂推理任务（算术、常识、符号推理）中的性能**
- 本质：**离散式提示学习**；相比传统上下文学习，**多了中间的推导提示**

> 传统 ICL：`x1,y1, x2,y2, ..., xtest → 补全 ytest`
> CoT：`x1, CoT1, y1, x2, CoT2, y2, ..., xtest → 模型自己生成推导 → ytest`

### 4.2 理解：数学题例子

**不给思路（错误）**：直接问"罗杰有 5 个球，又买了 2 盒 3 个装的网球，现在有几个球？"→ 模型答错

**给思维链（正确）**：
```
罗杰先有 5 个球，2 盒 3 个网球等于 6 个，5 + 6 = 11
→ 答案：11
```

就像数学考试**写出解题过程才能得分**——模型也需要"先想后答"。

### 4.3 CoT 分类（必考）

| 类型 | 做法 |
|---|---|
| **Few-shot CoT** | ICL 特殊情况：把每个演示扩充为 `<input, CoT, output>`（示例里带上推理步骤） |
| **Zero-shot CoT** | 不举例子，直接用提示激发推理：先用 **"Let's think step by step"** 生成推理步骤，再用 **"Therefore, the answer is"** 得出答案 |

> **涌现能力**：Zero-shot CoT 在模型规模超过一定阈值时大幅提高性能，但对小模型无效。

### 4.4 CoT 的四个特点

1. **逻辑性**：每个思考步骤应有逻辑关系，相互连接形成完整思考过程
2. **全面性**：尽可能全面细致考虑问题，不忽略任何可能因素
3. **可行性**：每个步骤应可实际操作和实施
4. **可验证性**：每个步骤应可通过实际数据和事实验证正确性

### 4.5 代码示例：Few-shot CoT 与 Zero-shot CoT

```python
# Few-shot CoT：示例里带上推理过程
few_shot_cot = """问：食堂原来有23个苹果，用了20个，又买了6个，现在有多少个？
答：23 - 20 = 3；3 + 6 = 9，所以答案是 9。

问：小明有3支笔，丢了1支，又买了4支，现在有几支？
答：3 - 1 = 2；2 + 4 = 6，所以答案是 6。

问：一箱牛奶有12瓶，喝了5瓶，又放进3瓶，现在有几瓶？
答："""

# Zero-shot CoT：用魔法提示词激发推理
zero_shot_cot = """问：一箱牛奶有12瓶，喝了5瓶，又放进3瓶，现在有几瓶？
答：让我们一步步思考（Let's think step by step）"""

print("=== Few-shot CoT ===")
print(few_shot_cot)
print("\n=== Zero-shot CoT ===")
print(zero_shot_cot)

# 提示词核心就两句：
#   "Let's think step by step"（先生成推理）
#   "Therefore, the answer is"（再给出答案）
```

---

## 五、PEFT：大模型参数高效微调方法

### 5.1 PEFT 介绍

**PEFT（Parameter-Efficient Fine-Tuning）= 参数高效微调**，目前大模型在工业界应用的主流方式。

**核心思想**：**仅微调少量或额外的模型参数，固定大部分预训练参数**，大大降低计算和存储成本；最先进的 PEFT 技术能实现与全量微调相当的性能。

**优势**：让大模型高效适配各种下游任务，无需微调全部参数；让**大模型在消费级硬件上微调成为可能**。

### 5.2 PEFT 三种方法总览

| 方法 | 思路 |
|---|---|
| **Prefix/Prompt-Tuning** | 在输入或隐层添加 k 个额外可训练的**前缀伪 tokens**，只训练这些前缀参数 |
| **Adapter-Tuning** | 在预训练模型**每一层内部插入小网络模块（适配器）**，只训练适配器参数 |
| **LoRA** | 学习**低秩矩阵**近似模型权重矩阵 W 的参数更新，只优化低秩矩阵参数 |

### 5.3 Prefix-Tuning（2021）

论文《Prefix-Tuning: Optimizing Continuous Prompts for Generation》。

- 做法：**在输入 token 之前构造任务相关的 virtual tokens 作为 Prefix**，训练时只更新 Prefix 参数，Transformer 其他参数固定
- 输入形式：`z = [Prefix, x, y]`，Prefix 长度 |Pidx|，对应参数化向量矩阵 Pθ（维度 |Pidx|×dim(hi)）
- **坑**：直接更新 Prefix 参数训练不稳定 → 作者在 Prefix 层前加 **MLP 结构**（把 Prefix 分解为小维度 Input 与 MLP 组合的输出），**训练完成后只保留 Prefix 参数**

### 5.4 Adapter-Tuning（2019）

论文《Parameter-Efficient Transfer Learning for NLP》，**拉开 PEFT 研究序幕**。

- 做法：在**预训练模型内部的网络层之间**添加新网络层/模块（adapter），训练时固定原模型参数，只微调 Adapter
- **Adapter 内部结构**（三个组件）：
  1. **down-project**：高维特征 → 低维特征（降维）
  2. **非线性层**：激活
  3. **up-project**：低维特征 → 高维特征（升维）
  - 外加 **skip-connection**（残差结构）：最差情况可退化为 identity

```python
# Adapter 结构伪代码（理解用）
class Adapter(nn.Module):
    def __init__(self, hidden_dim=768, bottleneck=64):
        super().__init__()
        self.down = nn.Linear(hidden_dim, bottleneck)   # 高维 → 低维
        self.act = nn.ReLU()
        self.up = nn.Linear(bottleneck, hidden_dim)     # 低维 → 高维
        # skip-connection：输出 = 原特征 + adapter(原特征)

    def forward(self, x):
        return x + self.up(self.act(self.down(x)))      # 残差结构
```

### 5.5 LoRA（低秩适应，当前最通用效果最好）

**为什么提出 LoRA**（前两个方法的痛点）：
- Adapter-Tuning：添加适配器层引入**额外计算，带来推理延迟**
- Prefix-Tuning：**难以优化**，性能随可训练参数规模非单调变化；且**占用序列长度**，减少处理下游任务的序列空间

**LoRA 原理**：
```
冻结预训练模型权重
→ 在每个 Transformer 块的 Linear 层旁加"旁支" A 和 B
→ A：d 维降到 r 维（r = LoRA 的秩，重要超参数）
→ B：r 维升到 d 维，B 初始化为 0
→ 训练只更新 A、B
→ 训练结束：A+B 的参数与原大模型参数合并使用（不增加推理开销）
```

**代码**：

```python
import torch
import torch.nn as nn
import math

input_dim = 768   # 预训练模型的隐藏大小
output_dim = 768  # 层的输出大小
rank = 8          # 低秩适应的等级 'r'
alpha = 1.0       # 缩放因子

W = torch.randn(input_dim, output_dim)   # 预训练权重（冻结）

W_A = nn.Parameter(torch.empty(input_dim, rank))   # LoRA 权重 A
W_B = nn.Parameter(torch.empty(rank, output_dim))  # LoRA 权重 B

# 初始化：A 用 Kaiming，B 全 0（保证初始时旁支输出为 0，等于没加）
nn.init.kaiming_uniform_(W_A, a=math.sqrt(5))
nn.init.zeros_(W_B)

def regular_forward_matmul(x, W):
    h = x @ W
    return h

def lora_forward_matmul(x, W, W_A, W_B):
    h = x @ W                    # 常规矩阵乘法（原模型路径）
    h += x @ (W_A @ W_B) * alpha # 旁支路径（LoRA 更新量）
    return h
```

**记忆点**：
- A 负责**降维**（d→r），B 负责**升维**（r→d）
- **B 初始化为 0**：保证刚开始训练时旁支不干扰原模型
- 训练完**必须合并** `W + W_A @ W_B * alpha`，推理时零额外开销

---

## 六、动手实验：用 peft 库一行代码做 LoRA 微调

> 工业界最常用的是 HuggingFace 的 `peft` 库，实际微调只需几行配置（需 `pip install peft transformers`）。

```python
from peft import LoraConfig, get_peft_model, TaskType
from transformers import AutoModelForCausalLM

model = AutoModelForCausalLM.from_pretrained("Qwen/Qwen2.5-7B-Instruct")

# LoRA 配置：r=8 就是上面说的"秩"
lora_config = LoraConfig(
    task_type=TaskType.CAUSAL_LM,   # 任务类型：因果语言模型
    r=8,                             # 秩（核心超参数，越小省得越多，但别太小）
    lora_alpha=32,                   # 缩放因子（对应伪代码里的 alpha）
    lora_dropout=0.1,                # 丢弃率
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],  # 给哪些 Linear 加旁支
)

# 一行代码把模型变成"LoRA 版"：只训练旁支参数，原参数冻结
lora_model = get_peft_model(model, lora_config)

# 看看到底训练了多少参数（通常 <1%）
lora_model.print_trainable_parameters()
# 输出示例: trainable params: 8,388,608 || all params: 7,000,000,000 || trainable%: 0.12
```

> **感受一下**：7B 模型全参微调要几百 GB 显存，LoRA 只训练 0.1% 的参数，一张消费级显卡就能跑——这就是 PEFT 的意义。

---

## 结尾 · 自测题（PPT 原版思考总结）

| 问题 | 答案 |
|---|---|
| 什么是指令学习？ | 通过给出更明显的指令/指示，让模型理解并做出正确的 action |
| 指令学习和 Prompt 的区别？ | 指令学习激发理解能力（判别式）；Prompt 激发补全能力（生成式）；指令学习必须精调 |
| 什么是思维链方法？ | 相比传统上下文学习（x1,y1,x2,y2...→ytest），多了中间的推导提示 |
| 思维链的分类？ | Few-shot CoT 和 Zero-shot CoT |
| 什么是 Prefix-Tuning？ | 输入 token 前构造任务相关的 virtual tokens 作为 Prefix，只更新 Prefix 参数 |
| Prefix-Tuning 和 P-Tuning 区别？ | ①Prefix 加在开头，P-Tuning 位置不固定；②Prefix 每层添加、MLP 初始化，P-Tuning 只在输入加 embedding、LSTM+MLP 初始化 |
| Prefix-Tuning 和 Prompt-Tuning 区别？ | Prompt Tuning 是 Prefix Tuning 的简化，只在输入层加 prompt tokens，不需 MLP |
| 什么是 Adapter-Tuning？ | 在预训练模型内部的网络层之间添加新网络层/模块适配下游任务 |
| 什么是 LoRA？ | 对大型模型权重矩阵进行隐式低秩转换的参数高效微调方法 |
| LoRA 原理？ | 冻结预训练权重，注入秩分解矩阵 A/B 旁支；A 降维、B 升维且初始为 0；训练后合并 |

**一张图记住进阶篇脉络**：

```
超大规模模型 Prompt 方法
├── In-Context Learning（零样本/单样本/小样本，不改模型）
├── Instruction-Tuning（指令判别式，需精调）
└── Chain-of-Thought（Few-shot CoT / Zero-shot CoT "Let's think step by step"）

PEFT 参数高效微调（只训少量参数）
├── Prefix-Tuning（输入前加可训练前缀 + MLP 初始化）
├── Adapter-Tuning（每层内插小模块：down→激活→up + 残差）
└── LoRA（Linear 旁支 A/B：降维+升维，B 初始 0，训练后合并）★ 最常用
```
