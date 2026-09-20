# 关于Agent开发的Python函数进阶



**日期**：2026-03-05 
**标签**：Python · Agent

## *arg/**kwargs

### 为什么Agent开发需要学习*arg与**kwargs

> 在阅读LangChain/LangGraph的官方示例与源码时，我们可以经常看到函数定义里带着`*arg`、`**kwarg`,或者函数头上挂着`@tool`、`@retry_decorator`这样的符号。一开始我以为这些是“高级语法，看不懂也没事”，后来发现：**不懂这些Python语法，根本看不懂Agent框架在干什么。**
>
> 这篇文章把我学Agent开发前必须补的几个Python进阶语法梳理一遍

### 关于`*args`

> `*args`:接收任意数量的位置参数
>
> **`args`是什么？**：当你写一个函数，但不确定用户会传几个参数时，用`*args`来接住所有多出来的参数，他会被打包成一个元组。
>
> **为什么需要它？**：比如你要写一个“把所有数字加起来”的函数，调用时用户可能传入2个、3个......或者更多的参数，你没有办法提前写死。这个时候就需要用到`*args`。

**代码示例**

```python
def add(*args):
    print(type(args))  #<class 'tuple'>
    return sum(args)   

print(add(1,2))      #3
print(add(1,3,4,5,6)) #19
```

### 关于`**kwargs`

> `**kwargs`:接受任意数量的关键字参数
>
> __`**kwargs`是什么__:当你写一个函数，不确定函数调用时会传入多少个__带名字的参数__，就用`**kwargs`接住全部参数，它会被打包成一个__字典dict__。
>
> __为什么需要他？__:比如调用大模型，Agent工具函数时，可选参数不固定，可能传`model`,`temperature`,`api_key`等命名参数，没办法提前写死所有形参，这时就用`**kwargs`。

**代码示例**

```python
def show_model_config(**kwargs):
    print(type(kwargs))   #<class 'dict'>
    print(kwargs)
    
if __name__ == '__main__':   
show_model_config(model = "llama3",temperature = 0.7)
#{'model':'llama3', 'temperature':0.7}
show_model_config(model = "gpt-4o",temperature = 0.5,max_tokens=1024)
#{'model':'gpt-4o', 'temperature':0.5, 'max_tokens':1024}
```

## Lambda匿名函数

### 关于Lambda

> **`lambda`**:一行就能写完的小函数，不用def命名
>
> **`lambda`写法**:`lambda 参数 ：返回值`,冒号左边是输入，右边是输出。
>
>  例如：
>
> ```python
> #普通函数
> def add(x, y):
>     return x + y
> 
> #lambda写法（等价，但是不用重新命名）
> add = lambda x, y: x + y
> 
> print(add(1, 2))  #3
> ```
>
> **什么时候用**：函数只用一次，写def太麻烦。最常见的场景是**sort排序**
>
> 例如：
>
> ```python
> students = [("王林",90),("李慕婉", 85),("拓森"， 97)，("申公虎":77)]
> #按分数（第二个元素）排序
> students.sort(key = lambda s : s[1])
> # 遍历students
> print(students)
> # [('申公虎', 77), ('李慕婉', 85), ('王林', 90), ('拓森', 97)]
> ```

## 闭包（Closure）

### 关于闭包

**闭包 = 内层函数 + 内层函数记住的外层函数的变量**

理解：

> 一个**内部函数**，跑到函数外面执行了，但它依然**记得外层函数里的变量**，就算外层函数已经执行结束了，变量也不会被销毁。

前提条件（必须同时满足这三条才叫闭包）：

1.有**嵌套函数**（函数里面再定义一个函数，内层，外层）

2.**内层函数引用了外层函数的变量**（不是全局变量）

3.**外层函数把内层函数return返回出去**

#### 为什么需要闭包？解决什么问题？

> 普通函数的痛点：
>
> 函数执行完，里面的局部变量就会被python回收销毁，下次调用函数，变量重新初始化，**没法保存中间状态。**
>
> 闭包作用：
>
> 1.可以**保存函数的状态、数据，**不需要用全局变量；
>
> 2.给函数“携带私有数据”，外部不能随便修改；
>
> 3.减少全局变量（全局变量乱改很容易出现bug）；
>
> 4.**装饰器底层就是闭包**（后面讲到装饰器）

#### 示例：

示例一：最简单的闭包

```python
def outer(num):
    #外层变量
    def inner():
        #内层函数，使用外层num变量
        print(f"外层传进来的值：{num}")
    # 返回内层函数（注意！不要加括号inner(),加括号是执行，不佳时返回函数本身）
    return inner

#调用外层函数，把内层函数拿出来，存到f
f = outer(100)

#重点！外层outer函数早就执行完了，但我们我们现在调用内层inner
f()
```

运行结果：

```plaintext
外层传进来的值：100
```

解析：

1.`outer(100)`执行 →创建变量`num=100`，然后返回`inner`函数对象，`outer`执行结束

2.正常情况下，outer结束，局部变量`num`应该销毁

3.但`inner`引用了`num`,形成闭包，`num`被保留下来

4.后面执行`f()`,也就是inner,依然能读取到`num=100`

我们再创建第二个闭包实例，互相独立：

```python
f2 = outer(200)
f2()
```

输出：`外传进来的值：200`

f和f2是两个独立的闭包，各自保存自己的num,互不干扰





示例2：用闭包保存累加状态（经典例子）

需求：做一个计数器，每次调用 +1， 记住上一次的数字

如果用全局变量，容易被意外修改；用闭包实现私有状态。

```python
def make_counter():
    count = 0 #外层变量，用来保存状态
    
    def counter():
        nonlocal count #nonlocal:声明这个变量不是内层本地变量，去外层找
        count += 1
        return count
    return counter

#创建一个计数器
c = make_counter()

print(c())  #1
print(c())  #2
print(c())  #3

#在创建另一个计数器
c2 = make_counter()
print(c2()) #1  和上面的c互不影响
```

解析：

·`make_counter()`执行完毕后，`count`不会销毁，被内层`counter`留住了。

·外部代码**不能直接访问count**，只能通过c()修改，保护数据

> 关键点：如果在内层**修改外层变量**必须写`nonlocal`;只是读取不用nonlocal



查看闭包保存的变量

每个闭包函数有个`__closure__`属性，可以看到它捕获保存的外层变量：

```python
print(c.__closure__)
print(c.__code__.co_freevars) # 查看捕获的变量名字

```

`co_freevars` 输出 `('count',)`，代表这个闭包捕获了 count 变量。



闭包 和 装饰器的关联

```python
import time

# 外层函数：接收被装饰的函数 func
def timer(func):
    # 内层函数wrapper
    def wrapper(*args, **kwargs):
        start = time.time()
        res = func(*args, **kwargs)
        end = time.time()
        print(f"运行耗时：{end-start}")
        return res
    return wrapper  # 返回内层函数

@timer
def test():
    time.sleep(1)
    print("函数执行完毕")

test()
#这个测试本质就是一个闭包
```

拆解：

1. `timer`是外层函数，接收`func`（被装饰的函数）
2. `wrapper`内层函数，引用外层变量`func`
3. 外层返回内层 wrapper 函数 → **完全符合闭包三要素** `@timer` 等价于 `test = timer(test)`，和前面`f=outer(100)`一模一样！



## 装饰器@（最常用）

装饰器：不修改原函数代码的前提下，给它 "套一层" 额外功能

例子：(计时装饰器)

```python
import time

def timer(func):
    def wrapper(*args, **kwargs):
        start = time.time()          # 调用前：记录开始时间
        result = func(*args, **kwargs)  # 调用原函数
        end = time.time()            # 调用后：记录结束时间
        print(f"{func.__name__} 花了 {end - start:.2f} 秒")
        return result
    return wrapper

@timer  # 这行等价于: slow_func = timer(slow_func)
def slow_func():
    time.sleep(1)
    print("做完了")

slow_func()
# 输出:
# 做完了
# slow_func 花了 1.00 秒

```

**关键理解**：

- `@timer` 只是语法糖，等价于 `slow_func = timer(slow_func)`
- 装饰器就是一个函数，接收原函数，返回一个新函数（wrapper）
- wrapper 里先做 "调用前" 的事，调用原函数，再做 "调用后" 的事

**Agent 框架里的例子**：

- LangChain 的 `@tool`：把普通函数标记成 Agent 可调用的工具
- `@retry`：自动重试失败的 API 调用

**三者关系**

```plaintext
lambda(最简单) → 闭包（升级） → 装饰器（应用）
```

- lambda 是小函数
- 闭包是函数 "记住" 变量
- 装饰器是闭包的实战：记住原函数，包一层加功能