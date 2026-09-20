# 关于Agent开发的Python模块化与工程结构

**日期**：2026-09-20
**标签**：Python · Agent · 模块化

## 为什么Agent开发必须懂模块化

> 刚开始写代码，所有东西都塞在一个 .py 文件里，几百行后自己都找不到北。
>
> LangChain / LangGraph 源码里，一个功能拆成十几个文件，每个文件各司其职。不懂模块化，根本不知道从哪看起。
>
> 这篇文章把我学Agent开发前必须补的模块化知识梳理一遍。

---

## 一、import 是怎么工作的

### 关于 import

> **import**：把别的文件里写好的代码拿过来用，不用重复造轮子。
>
> **本质**：Python 找到你导入的文件，执行一遍，把里面的变量、函数、类都拿过来。

**代码示例**：

```python
# 导入标准库
import os
import sys

# 导入第三方库
import requests

# 导入自己写的模块
from my_module import my_function
from my_package import my_class

# 导入并起别名
import numpy as np
import pandas as pd
```

### import 的几种写法

| 写法 | 作用 | 例子 |
|---|---|---|
| `import 模块名` | 导入整个模块 | `import os` |
| `from 模块名 import 函数/类` | 只导入需要的部分 | `from os import path` |
| `from 模块名 import *` | 导入所有（不推荐） | `from os import *` |
| `import 模块名 as 别名` | 起别名 | `import numpy as np` |

**关键点**：
- import 只会执行一次，重复 import 不会重复执行
- import 会把整个文件执行一遍，所以模块顶层的代码都会运行

---

## 二、什么是模块、什么是包

### 关于模块（Module）

> **模块**：一个 .py 文件就是一个模块。
>
> 文件名 `utils.py` → 模块名 `utils`

### 关于包（Package）

> **包**：一个文件夹，里面有多个 .py 文件，还有一个 `__init__.py` 文件。
>
> 文件夹名 `mypackage/` → 包名 `mypackage`

**目录结构示例**：

```
my_project/
├── main.py              # 主程序入口
├── config.py            # 配置模块
├── utils/               # 工具包
│   ├── __init__.py
│   ├── file_loader.py   # 文件加载工具
│   └── text_processor.py # 文本处理工具
└── models/              # 模型包
    ├── __init__.py
    ├── llm.py           # 大模型封装
    └── embedding.py      # 向量嵌入封装
```

**导入方式**：

```python
# 导入模块
import config

# 从包导入模块
from utils import file_loader

# 从模块导入函数/类
from utils.file_loader import load_pdf
```

---

## 三、if __name__ == "__main__": 的作用

### 关于 if __name__ == "__main__"

> 这行代码的意思是：**只有直接运行这个文件时，才执行下面的代码；被别人 import 时，不执行。**

**代码示例**：

```python
# my_module.py

def hello():
    print("你好！")

# 只有直接运行这个文件时，才执行下面的代码
if __name__ == "__main__":
    hello()
    print("这是直接运行时才会看到的")
```

**两种运行方式的区别**：

**方式1：直接运行这个文件**
```powershell
python my_module.py
```
输出：
```
你好！
这是直接运行时才会看到的
```

**方式2：被别人 import**
```python
# main.py
import my_module
# 不会执行 if __name__ 里的代码
```

**为什么需要它**：
- 写模块的时候，经常想测试一下自己的代码
- 但别人 import 你的模块时，不希望测试代码被执行
- 用 `if __name__ == "__main__":` 把测试代码包起来就行

---

## 四、实战：把零散代码整理成模块化项目

**原始问题**：所有代码都塞在一个 `chat_pdf.py` 里，几百行，又乱又难维护。

**整理思路**：按功能拆分，每个文件只干一件事。

### 模块化后的目录结构

```
chat_pdf/
├── main.py           # 主程序入口
├── config.py         # 配置（API Key、模型名等）
├── loader/          # 文档加载模块
│   ├── __init__.py
│   └── pdf_loader.py # 加载 PDF 文件
├── store/            # 向量存储模块
│   ├── __init__.py
│   └── vector_store.py # 向量数据库
├── qa/               # 问答模块
│   ├── __init__.py
│   └── chain.py      # RAG 问答链
└── requirements.txt   # 依赖列表
```

### 每个文件的内容

**1. config.py（配置模块）**

```python
# 所有配置集中在这，改的时候只改这里

# 大模型配置
LLM_MODEL = "llama3.2"
EMBEDDING_MODEL = "nomic-embed-text"

# 向量数据库配置
CHROMA_PATH = "./chroma_db"

# 文档配置
PDF_PATH = "./data/test.pdf"
CHUNK_SIZE = 500
CHUNK_OVERLAP = 50
```

**2. loader/pdf_loader.py（文档加载模块）**

```python
# 只负责：加载 PDF，切成小块

from langchain.document_loaders import PyPDFLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
import config

def load_and_split_pdf(pdf_path):
    """加载 PDF 文件，切分成小块"""
    loader = PyPDFLoader(pdf_path)
    documents = loader.load()
    
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=config.CHUNK_SIZE,
        chunk_overlap=config.CHUNK_OVERLAP
    )
    chunks = splitter.split_documents(documents)
    return chunks
```

**3. store/vector_store.py（向量存储模块）**

```python
# 只负责：创建和管理向量数据库

from langchain.vectorstores import Chroma
from langchain.embeddings import OllamaEmbeddings
import config

def create_vector_store(chunks):
    """用文档块创建向量数据库"""
    embeddings = OllamaEmbeddings(model=config.EMBEDDING_MODEL)
    vector_store = Chroma.from_documents(
        documents=chunks,
        embedding=embeddings,
        persist_directory=config.CHROMA_PATH
    )
    return vector_store

def load_vector_store():
    """加载已有的向量数据库"""
    embeddings = OllamaEmbeddings(model=config.EMBEDDING_MODEL)
    vector_store = Chroma(
        persist_directory=config.CHROMA_PATH,
        embedding_function=embeddings
    )
    return vector_store
```

**4. qa/chain.py（问答模块）**

```python
# 只负责：创建 RAG 问答链

from langchain.chat_models import ChatOllama
from langchain.chains import RetrievalQA
import config

def create_qa_chain(vector_store):
    """创建问答链"""
    llm = ChatOllama(model=config.LLM_MODEL)
    qa_chain = RetrievalQA.from_chain_type(
        llm=llm,
        chain_type="stuff",
        retriever=vector_store.as_retriever(),
        return_source_documents=True
    )
    return qa_chain

def ask_question(qa_chain, question):
    """提问，返回答案和来源"""
    result = qa_chain({"query": question})
    return result["result"], result["source_documents"]
```

**5. main.py（主程序入口）**

```python
# 只负责：把所有模块串起来

from loader.pdf_loader import load_and_split_pdf
from store.vector_store import create_vector_store, load_vector_store
from qa.chain import create_qa_chain, ask_question
import config

def main():
    # 1. 加载文档（如果向量库已存在，跳过这步）
    chunks = load_and_split_pdf(config.PDF_PATH)
    
    # 2. 创建向量数据库
    vector_store = create_vector_store(chunks)
    
    # 3. 创建问答链
    qa_chain = create_qa_chain(vector_store)
    
    # 4. 问答循环
    print("RAG 问答系统已启动，输入问题开始对话（输入 q 退出）")
    while True:
        question = input("\n问题：")
        if question.lower() == "q":
            break
        answer, sources = ask_question(qa_chain, question)
        print(f"\n答案：{answer}")
        print(f"来源：{sources[0].metadata.get('source', 'unknown')}")

if __name__ == "__main__":
    main()
```

---

## 五、为什么 Agent 框架都是模块化的

> LangChain 为什么拆成几十个包？
>
> - 每个功能独立，可以单独替换
> - 比如你想换向量数据库，只需要改 store 模块，其他模块不用动
> - 多人协作，各写各的模块不冲突
> - 代码复用，loader 模块可以被多个项目用

**模块化的好处**：

| 好处 | 说明 |
|---|---|
| 易维护 | 改一个功能只改一个文件 |
| 易复用 | 模块可以被多个项目 import |
| 易协作 | 多人各写各的模块不冲突 |
| 易测试 | 每个模块可以单独测试 |

**完成标准**：项目目录结构清晰，每个文件职责单一，能独立 import。

---

**三者关系**：

```plaintext
函数（封装动作）→ 类（封装数据+动作）→ 模块/包（组织代码）
```

- 函数：把一段代码打包
- 类：把数据和操作数据的方法打包
- 模块：把相关的类和函数打包成一个文件
- 包：把相关的模块打包成一个文件夹
