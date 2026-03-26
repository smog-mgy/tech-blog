# 关于Agent开发的Python面向对象进阶

**日期**：2026-03-12
**标签**：Python · Agent · OOP

## 为什么Agent开发必须懂面向对象

> 在阅读LangChain/LangGraph源码时，你会看到满屏的`class Document`、`class BaseChatModel`、`class Runnable`。不懂类和对象，根本不知道框架在干什么。
>
> 这篇文章把我学Agent开发前必须补的面向对象知识梳理一遍。

---

## 一、类和对象是什么

### 关于类和对象

> **类（Class）**：一张设计图纸，定义了一类东西"应该有什么、能做什么"。
>
> **对象（Object）**：按照图纸造出来的具体实物。

**类比理解**：
- 图纸（类）："汽车有颜色、品牌，能跑"
- 实物（对象）："这辆红色的特斯拉 Model 3"

### 怎么定义类

```python
# 定义一个类（图纸）
class Dog:
    # 属性：这只狗有什么
    def __init__(self, name, age):
        self.name = name  # 名字
        self.age = age    # 年龄
    
    # 方法：这只狗能做什么
    def bark(self):
        print(f"{self.name} 汪汪叫！")

# 造一个具体的对象（实例化）
my_dog = Dog("旺财", 3)

# 使用对象
print(my_dog.name)   # 旺财
my_dog.bark()       # 旺财 汪汪叫！
```

---

## 二、__init__ 和 self 是什么

### 关于 __init__

> `__init__`：初始化方法，造对象的时候自动调用，用来给对象设置初始属性。
>
> **什么时候用**：每次创建新对象时，必须给它设置一些初始值（比如名字、年龄）。

### 关于 self

> `self`：代表"当前这个对象自己"。
>
> **类比理解**：就像每个人说"我"——"我的名字是XXX"里的"我"，就是 self。

**代码示例**：

```python
class Dog:
    def __init__(self, name, age):
        # self.name 就是"这个对象的名字属性"
        self.name = name
        self.age = age
    
    def bark(self):
        # self.name 访问当前对象的名字
        print(f"{self.name} 今年 {self.age} 岁了")

dog1 = Dog("旺财", 3)
dog2 = Dog("来福", 5)

dog1.bark()  # 旺财 今年 3 岁了
dog2.bark()  # 来福 今年 5 岁了
```

**关键点**：
- `self` 必须是实例方法的第一个参数
- 调用方法时不用手动传 self，Python 自动帮你传
- `dog1.bark()` 等价于 `Dog.bark(dog1)`

---

## 三、继承和方法重写

### 关于继承

> **继承**：子类可以复用父类的属性和方法，还能加自己的新东西。
>
> **为什么需要**：代码复用，不用重复写。比如"狗"和"猫"都有"动物"的共同特征，就可以把共同的写在父类里。

**代码示例**：

```python
# 父类（基类）
class Animal:
    def __init__(self, name):
        self.name = name
    
    def speak(self):
        print(f"{self.name} 发出声音")

# 子类（派生类）继承 Animal
class Dog(Animal):
    # 方法重写：子类重新定义父类的方法
    def speak(self):
        print(f"{self.name} 汪汪叫！")

class Cat(Animal):
    def speak(self):
        print(f"{self.name} 喵喵叫！")

# 使用
dog = Dog("旺财")
cat = Cat("咪咪")

dog.speak()  # 旺财 汪汪叫！
cat.speak()  # 咪咪 喵喵叫！
```

### 关于方法重写

> **方法重写（Override）**：子类重新定义父类已有的方法，实现自己的版本。
>
> **什么时候用**：父类的方法不适合子类，需要改一下。

**调用父类方法**：

```python
class Dog(Animal):
    def __init__(self, name, breed):
        super().__init__(name)  # 调用父类的初始化
        self.breed = breed     # 子类自己的属性
    
    def speak(self):
        super().speak()        # 先调用父类的方法
        print("汪汪汪！")      # 再加自己的内容

dog = Dog("旺财", "柴犬")
dog.speak()
# 旺财 发出声音
# 汪汪汪！
```

---

## 四、常用魔术方法

### 什么是魔术方法

> **魔术方法**：Python 内置的特殊方法，名字前后都有双下划线 `__xxx__`。
>
> **特点**：不需要你手动调用，在特定场景自动触发。

### 1. `__init__`（最常用）

创建对象时自动调用，初始化属性。

```python
class Person:
    def __init__(self, name, age):
        self.name = name
        self.age = age
```

### 2. `__str__`（打印对象时显示什么）

> **`__str__`**：当你 `print(对象)` 或 `str(对象)` 时，自动调用这个方法，返回一个字符串。

```python
class Person:
    def __init__(self, name, age):
        self.name = name
        self.age = age
    
    def __str__(self):
        return f"Person(name={self.name}, age={self.age})"

p = Person("小明", 20)
print(p)  # Person(name=小明, age=20)
```

### 3. `__repr__`（调试时显示什么）

> **`__repr__`**：当你在终端里直接输入对象名回车时，自动调用。
>
> 和 `__str__` 的区别：
> - `__str__`：给人看的，友好可读
> - `__repr__`：给开发者看的，准确还原对象

```python
class Person:
    def __init__(self, name, age):
        self.name = name
        self.age = age
    
    def __str__(self):
        return f"{self.name}今年{self.age}岁"
    
    def __repr__(self):
        return f"Person(name='{self.name}', age={self.age})"

p = Person("小明", 20)
print(p)       # 小明今年20岁（调用 __str__）
p              # Person(name='小明', age=20)（在终端里直接输入，调用 __repr__）
```

**简单记忆**：
- `__str__`：给用户看的简介
- `__repr__`：给程序员看的完整信息

---

## 五、实战：写一个 Document 类

**需求**：写一个 Document 类，有 text、metadata 属性，__str__ 返回文档内容预览。

这就是 LangChain 里 `Document` 类的简化版！

```python
class Document:
    def __init__(self, text, metadata=None):
        # 文档内容
        self.text = text
        # 元数据（来源、页码等），默认空字典
        self.metadata = metadata or {}
    
    def __str__(self):
        # 返回内容预览（前100个字符）
        preview = self.text[:100]
        if len(self.text) > 100:
            preview += "..."
        return f"Document(内容预览: {preview}, 元数据: {self.metadata})"
    
    def __repr__(self):
        return f"Document(text='{self.text[:50]}...', metadata={self.metadata})"


# 使用
doc = Document(
    text="这是一段很长的文档内容，用来测试Document类的__str__方法返回预览效果。"
         "在Agent开发中，文档是最常见的数据类型之一，RAG系统里到处都是Document对象。",
    metadata={"source": "test.pdf", "page": 1}
)

print(doc)
# Document(内容预览: 这是一段很长的文档内容，用来测试Document类的__str__方法返回预览效果。在Agent开发中，文档是最常..., 元数据: {'source': 'test.pdf', 'page': 1})
```

---

## 六、为什么 Agent 开发必须懂 OOP

> LangChain / LangGraph 里全是类和对象：
>
> - `Document`：文档对象，有 text、metadata 属性
> - `BaseChatModel`：大模型基类，所有模型都继承它
> - `Runnable`：可运行对象，LangChain 核心接口
> - `Tool`：工具类，Agent 可调用的工具
>
> 不懂类和继承，看源码就像看天书。

**三者关系**：

```plaintext
函数（封装动作）→ 类（封装数据+动作）→ 框架（大量类的组合）
```

- 函数：把一段代码打包
- 类：把数据和操作数据的方法打包
- 框架：成千上万的类组合在一起，形成完整系统

**Agent 开发里常见的类**：
- `Document`：文档
- `ChatMessage`：聊天消息
- `Tool`：工具
- `Agent`：智能体本身
