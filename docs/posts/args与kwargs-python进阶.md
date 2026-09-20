# 关于Agent开发的Python进阶



**日期**：2026-09-19
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

