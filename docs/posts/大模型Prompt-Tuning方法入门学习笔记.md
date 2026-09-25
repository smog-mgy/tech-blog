# 大模型 Prompt-Tuning 方法入门学习笔记

**前置**：这篇承接 LLM 架构篇——你已经知道 BERT 是 Encoder（理解）、GPT 是 Decoder（生成）。这篇讲的是**怎么让预训练模型更好地适配下游任务**：传统做法是微调（Fine-Tuning），更省钱省力的做法是 Prompt-Tuning。

---

## 一、NLP 任务四种范式（先建立大局观）

学术界把 NLP 任务发展分为四个阶段（四范式）：

| 范式 | 代表方法 | 特点 |
|---|---|---|
| 第一范式 | 传统机器学习（TF-IDF + 朴素贝叶斯等） | 手工特征 + 简单算法 |
| 第二范式 | 深度学习（word2vec + LSTM 等） | 准确率提高，特征工程减少 |
| 第三范式 | 预训练模型 + Fine-Tuning（BERT + 微调） | **准确度显著提高**，小数据集就能训练出好模型 |
| 第四范式 | 预训练模型 + Prompt + 预测（BERT + Prompt） | **训练所需数据显著减少** |

**发展趋势**：精度更高、少监督甚至无监督。**Prompt-Tuning 是当前最新最火的研究成果。**

---

## 二、Fine-Tuning 回顾（为什么要换方法）

### 2.1 什么是 Fine-Tuning

**Fine-Tuning（微调）= 一种迁移学习方式**：采用已经在大量文本上训练的预训练语言模型，然后**在小规模的任务特定文本上继续训练它**。

### 2.2 痛点（三个）

1. **任务目标差距过大**：下游任务的目标和预训练的目标差距过大，**可能导致过拟合**
2. **依赖大量监督语料**：微调需要大量标注数据
3. 每次新任务都要重新微调整个大模型，成本高

### 2.3 解决方法：Prompt-Tuning

> **通过添加模板的方法来避免引入额外的参数，从而让模型可以在小样本（few-shot）或者零样本（zero-shot）场景下达到理想效果。**

**一句话对比**：
- Fine-Tuning：让**预训练模型去迁就下游任务**（改模型）
- Prompt-Tuning：让**下游任务去迁就预训练模型**（改输入，不改模型）

---

## 三、Prompt-Tuning 技术介绍

### 3.1 核心思想

**将 Fine-tuning 的下游任务目标，转换为 Pre-training（预训练）的任务**——比如把分类任务变成预训练时的"完形填空"。

### 3.2 以情感分析二分类为例，看执行步骤

任务：判断句子"I like the Disney films very much."是积极还是消极。

**传统 Fine-Tuning 做法**：
```
[CLS] I like the Disney films very much. [SEP]
→ BERT 获得 [CLS] 表征
→ 喂入新增加的 MLP 分类器 → 二分类（positive / negative）
→ 需要一定量的训练数据来训练
```

**Prompt-Tuning 做法（三步）**：

**① 构建模板（Template）**：生成含 `[MASK]` 的模板，拼接到原文本
```
[CLS] I like the Disney films very much. [SEP] It was [MASK]. [SEP]
→ 喂入 BERT，复用预训练好的 MLM 分类器
→ 直接得到 [MASK] 位置预测的各 token 概率分布
```

**② 标签词映射（Verbalizer）**：`[MASK]` 只对部分词感兴趣，建立映射关系
```
如果 [MASK] 预测出 "great" → 认为是 positive 类
如果 [MASK] 预测出 "terrible" → 认为是 negative 类
```

**③ 训练**：根据 Verbalizer 获得指定 label word 的概率分布，用交叉熵训练。此时**只微调预训练好的 MLM head**，避免了过拟合。

> **挑战**：不同的任务需要不同的 Template 和 label word。如何最大化找到最合适的模板和标签词，是 Prompt-Tuning 的重要研究点。

---

## 四、Prompt-Tuning 主要方法（发展脉络）

### 4.1 鼻祖：GPT-3（In-Context Learning）

- GPT-3 开创性地提出 **In-Context Learning**：**无须修改模型**即可实现 few-shot、zero-shot 学习
- 引入 **Demonstrate Learning**：让模型知道与标签相似的语义描述，提升推理能力

**问题**：
1. 依赖超大规模模型（参数超 100 亿），真实场景难应用
2. 小参数模型上效果下降明显
3. prompt 过于简单，泛化性能低

### 4.2 PET 模型（Pattern-Exploiting Training）

出自 EACL2021《Exploiting Cloze Questions for Few Shot Text Classification and Natural Language Inference》。**把分类任务转换为与 MLM 一致的完形填空**。

提出两个重要组件（**PVP = Pattern-Verbalizer-Pair**）：

| 组件 | 含义 | 举例 |
|---|---|---|
| **Pattern（Template）T** | 额外添加的带 [mask] 标记的短文本 | "It was [mask]." |
| **Verbalizer V** | 标签词映射，把预测词映射到类标签 | "great"→positive，"terrible"→negative |

**人工设计 PVP 的缺陷**：
1. 成本高，需要领域先验知识
2. 不能保证最优解，训练不稳定、方差大（换一个模板结果差很多）
3. 与 MLM 预训练在语义和分布上存在差异

### 4.3 Prompt-Oriented Fine-Tuning（全参数微调）

- **本质**：Prompt-Tuning + Fine-Tuning 的结合体，**预训练模型参数是可变的**
- 流程：构建 prompt 文本"It was [MASK]." + 输入文本"The film is attractive." → 拼接输入 → 训练目标和 MLM 一致
- 适合：**Bert 类相对较小模型**
- 缺点：模型越来越大时，每次任务都更新全部参数，资源/时间成本高 → 于是提出**只针对 prompt 调优**的方法

### 4.4 Hard Prompt vs Soft Prompt（关键概念）

| | Hard Prompt（离散提示） | Soft Prompt（连续提示） |
|---|---|---|
| 定义 | 固定提示模板，把**真实文本字符串**嵌入文本 | **可参数化的提示模板**，模板参数可按任务调整 |
| 特点 | 模板固定，不能调整 | 模板参数可训练，达到最佳效果 |
| 缺陷/优点 | 依赖人工，改一个单词结果差巨大 | 不需要指定 token 具体是什么，只需在语义空间表示一个向量 |

### 4.5 Soft Prompt 理解（伪标记 Pseudo Token）

连续提示模板定义：`T = [x], [v1], [v2], ..., [vn], [MASK]`

- `[vn]` 是**伪标记**：仅代表抽象 token，没有实际含义，**本质上是一个向量**
- 不同任务、数据可自适应地在语义空间寻找合适的向量代表模板中的每个词

**核心总结**：Soft Prompt 把模板变成**可训练的参数**；预训练模型参数不变，变的是 **prompt token 对应的词向量（Word Embedding）表征**及其他引入的少量参数。

---

## 五、三种典型 Prompt-Tuning 方法

### 5.1 Prompt Tuning（谷歌 2021，面向 NLG 任务）

论文《The Power of Scale for Parameter-Efficient Prompt Tuning》，基于 **T5 模型**（最大 11B）。

**思想**：
```
n 个文本 token  → 预训练 embedding table → Xe (Rn×e)
p 个伪标记 vi   → 另一个 embedding table → Pe (Rp×e)   ← 可训练
拼接新输入      → [Pe : Xe] → (R(p+n)×e) → 喂入 MLP 获得新表征
只有 Pe 参数随训练更新，大模型参数冻结
```

**优缺点**：
- ✅ 大模型微调新范式；模型大了之后固定大模型参数、只调附加参数，性能基本和全参微调相当
- ❌ 小样本场景表现不好；收敛慢；调参复杂

### 5.2 P-Tuning V1（清华 2022，面向 NLU 任务）

论文《GPT Understands, Too》。**解决的问题：大模型的 Prompt 构造方式严重影响下游任务效果**。

**为什么不能直接优化 Embedding 参数？两个挑战**：
1. **Discretenes（不连续性）**：正常语料的 Embedding 已预训练，直接随机初始化训练 prompt embedding 容易陷入局部最优
2. **Association（关联性）**：无法捕捉 prompt embedding 之间的相关关系

**P-Tuning V1 解决方案**：
```
固定 LLM 参数
→ 用 MLP + LSTM 对 prompt embedding 进行编码
→ 编码后与其他向量拼接 → 正常输入 LLM
训练之后只保留 Prompt 编码后的向量，无需保留编码器
```

### 5.3 P-Tuning V2（升级版）

- 解决 P-Tuning V1 在**小参数量模型上表现差**的问题
- 核心：**在模型的每一层都应用连续的 prompts**，并对 prompts 参数更新优化
- 面向 NLU 任务优化

### 5.4 Prompt Tuning vs P-Tuning 对比（必考）

| 对比项 | Prompt Tuning | P-Tuning |
|---|---|---|
| 加的位置 | 额外 embedding 加在**开头**（像模仿 Instruction 指令） | 位置**不固定** |
| 参数初始化 | 不需要 MLP 初始化 | 通过 **LSTM + MLP** 初始化 |

---

## 六、动手实验：用代码感受 Fine-Tuning vs Prompt-Tuning

**理解"模板+标签词映射"到底是怎么回事**。下面这个例子用 BERT 做情感分析，分别演示两种方式（需安装 `transformers`、`torch`）。

### 6.1 方式一：传统 Fine-Tuning 思路（新增分类头）

```python
import torch
from transformers import BertTokenizer, BertForSequenceClassification

# 加载 BERT + 新增分类头（2 分类）
tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
model = BertForSequenceClassification.from_pretrained('bert-base-uncased', num_labels=2)

text = "I like the Disney films very much."
inputs = tokenizer(text, return_tensors='pt')
# 模型内部：BERT 编码 → [CLS] → 全连接分类头 → logits
outputs = model(**inputs)
logits = outputs.logits  # shape [1, 2]
pred = logits.argmax(-1).item()
print("Fine-Tuning 式分类结果:", "positive" if pred == 1 else "negative")
```

### 6.2 方式二：Prompt-Tuning 思路（模板 + 标签词映射）

```python
import torch
from transformers import BertTokenizer, BertForMaskedLM

tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
model = BertForMaskedLM.from_pretrained('bert-base-uncased')  # 复用 MLM 头，不新增分类器

def prompt_predict(text):
    # 构建模板：It was [MASK].
    prompt = f"{text} It was [MASK]."
    inputs = tokenizer(prompt, return_tensors='pt')
    mask_idx = inputs['input_ids'][0].tolist().index(tokenizer.mask_token_id)

    with torch.no_grad():
        logits = model(**inputs).logits  # [1, seq_len, vocab_size]

    # 取 [MASK] 位置概率最高的词
    pred_token = logits[0, mask_idx].argmax(-1).item()
    word = tokenizer.decode(pred_token)
    return word

# 标签词映射（Verbalizer）
def verbalizer(word):
    return "positive" if word in ("great", "good", "wonderful") else "negative"

# 用同一个 MLM 模型直接做情感分类，模型参数没动！
print("MASK 预测词:", prompt_predict("I like the Disney films very much."))
print("映射标签:", verbalizer(prompt_predict("I like the Disney films very much.")))
```

> **看懂区别了吗**：方式二里**没有新增任何分类器**，就是让 BERT 做它预训练时最擅长的完形填空，再用标签词映射变成分类——这就是"让下游任务迁就预训练模型"。

### 6.3 Hard Prompt vs Soft Prompt 直观理解

```python
# Hard Prompt：模板是写死的真实文本（改一个词效果可能天差地别）
hard_prompt = "这部电影很好看，我的评价是：好"

# Soft Prompt：模板位置是"可训练向量"（伪标记 [v1]），不用人工指定具体词
# 用代码表示：伪标记就是一个随机初始化、可训练的向量
import torch.nn as nn
soft_prompt = nn.Parameter(torch.randn(5, 768))  # 5 个伪标记，每个 768 维
# 训练时只更新 soft_prompt，模型其他参数冻结
```

---

## 结尾 · 自测题（思考总结）

| 问题 | 答案 |
|---|---|
| NLP 任务四范式？ | 1.传统机器学习 2.深度学习 3.预训练+fine-tuning 4.预训练+prompt+预测 |
| 什么是 Fine-Tuning？ | 采用预训练语言模型，在小规模任务特定文本上继续训练 |
| Prompt-Tuning 的实现？ | 1.构建模板 2.标签词映射 3.训练 |
| 什么是 Prompt-Tuning？ | 通过添加模板避免引入额外参数，让模型在 few-shot / zero-shot 下达到理想效果 |
| PET 模型的主要组件？ | Pattern（模板）与 Verbalizer（标签词映射） |
| P-Tuning V1 的核心思想？ | 固定 LLM 参数，用 MLP+LSTM 编码 prompt，拼接后输入 LLM；训练后只保留 prompt 向量 |

**一张图记住发展脉络**：

```
Fine-Tuning（改模型，任务迁就模型）
  └→ 痛点：目标 gap、过拟合、依赖数据
      └→ Prompt-Tuning（改输入，模型迁就任务）
          ├→ Hard Prompt（写死的文本模板，人工依赖强）
          ├→ Soft Prompt（可训练向量/伪标记）
          │    ├→ Prompt Tuning（谷歌：T5，前缀式，NLG）
          │    ├→ P-Tuning V1（清华：MLP+LSTM 编码，NLU）
          │    └→ P-Tuning V2（每层都加，解决小模型问题）
          └→ 进阶篇预告：ICL / Instruction-Tuning / CoT / PEFT(LoRA)
```
