# PyTorch 框架学习笔记

**日期**：2026-04-09
**标签**：深度学习 · PyTorch · 学习笔记

**安装**：

```bash
pip install torch -i https://pypi.tuna.tsinghua.edu.cn/simple
```

---

## 1. 什么是 PyTorch

**PyTorch 是一个基于 Python 语言的深度学习框架，把数据封装成张量（Tensor）来处理。**

- 提供灵活且高效的工具，用于构建、训练和部署机器学习和深度学习模型
- 广泛应用于：计算机视觉、自然语言处理、强化学习等领域

---

## 2. PyTorch 特点

| 特点 | 说明 |
|---|---|
| 类似 NumPy 的张量计算 | 会 NumPy 就赢了一半 |
| 自动微分系统 | 梯度自动算，不用手推公式 |
| 深度学习库 | 神经网络模块、优化器一条龙 |
| 动态计算图 | 想到哪写到哪，调试方便 |
| GPU 加速（CUDA 支持） | 跑车 vs 自行车 |
| 支持多种应用场景 | CV / NLP / 强化学习 |
| 跨平台支持 | Windows / Linux / Mac |

---

## 3. 什么是张量

**张量 = 元素为同一种数据类型的多维矩阵。**

- 一维张量 → 向量（vector）
- 二维张量 → 矩阵（matrix）
- 张量在 PyTorch 中以"类"的形式封装，运算方法都封装在类里
- 和 NumPy 类似，但支持 GPU 加速（CUDA）

```python
import torch

# 0维：标量
s = torch.tensor(5)
print(s.ndim)   # 0

# 1维：向量
v = torch.tensor([1, 2, 3])
print(v.ndim)   # 1

# 2维：矩阵
m = torch.tensor([[1, 2], [3, 4]])
print(m.ndim)   # 2
print(m.shape)  # torch.Size([2, 2])
```

---

## 4. 张量的基本创建方式

### 方式1：torch.tensor() 根据指定数据创建张量

```python
import torch
import numpy as np

# 1. 创建标量
data = torch.tensor(10)
print(data)            # tensor(10)

# 2. 从 numpy 数组创建
data = np.random.randn(2, 3)
data = torch.tensor(data)
print(data)            # dtype 默认 float64（继承 numpy）

# 3. 从列表创建（默认元素类型 float32）
data = torch.tensor([[10., 20., 30.], [40., 50., 60.]])
print(data)            # tensor([[10., 20., 30.], [40., 50., 60.]])
```

### 方式2：torch.Tensor() 根据指定形状创建张量

```python
# 1. 创建 2 行 3 列的张量，默认 dtype 为 float32
data = torch.Tensor(2, 3)
print(data)

# 2. 注意：如果传列表，则创建包含指定元素的张量
data = torch.Tensor([10])
print(data)            # tensor([10.])

data = torch.Tensor([10, 20])
print(data)            # tensor([10., 20.])
```

### 方式3：指定类型的张量

```python
# 创建 2 行 3 列，dtype 为 int32 的张量
data = torch.IntTensor(2, 3)
print(data)            # tensor([[0, 1610612736, ...]], dtype=torch.int32)

# 注意：传的元素类型不正确，会自动做类型转换
data = torch.IntTensor([2.5, 3.3])
print(data)            # tensor([2, 3], dtype=torch.int32)  （小数被截断成整数）

# 其他类型
data = torch.ShortTensor()    # int16
data = torch.LongTensor()     # int64
data = torch.FloatTensor()    # float32
data = torch.DoubleTensor()   # float64
```

> 记两个常用：`torch.tensor(数据)` 传内容、`torch.Tensor(形状)` 传形状，别搞混。

---

## 5. 创建线性和随机张量

### 线性张量

```python
# torch.arange(start, end, step)：在指定区间按步长生成元素（含 start 不含 end）
data = torch.arange(0, 10, 2)
print(data)   # tensor([0, 2, 4, 6, 8])

# torch.linspace(start, end, steps)：在指定区间按元素个数生成
data = torch.linspace(0, 9, 10)
print(data)   # 从 0 到 9 均匀生成 10 个数
```

### 随机张量

```python
# torch.randn(行, 列)：标准正态分布随机浮点张量
data = torch.randn(2, 3)
print(data)

# torch.rand(行, 列)：均匀分布 [0, 1)
data = torch.rand(2, 3)

# torch.randint(low, high, size=())：随机整数张量
data = torch.randint(0, 10, [2, 3])
print(data)
```

### 随机种子（可复现）

```python
# 查看当前随机种子
print('随机数种子:', torch.initial_seed())

# 设置随机种子
torch.manual_seed(100)
data = torch.randn(2, 3)
print(data)

# 种子相同 → 结果相同（训练模型可复现的关键）
torch.manual_seed(100)
data2 = torch.randn(2, 3)
print(data2.equal(data))   # True
```

---

## 6. 创建 0、1、指定值张量

```python
# 全 0 张量
data = torch.zeros(2, 3)
print(data)                       # tensor([[0., 0., 0.], [0., 0., 0.]])

# 根据已有张量形状创建全 0 张量
data = torch.zeros_like(data)
print(data)

# 全 1 张量
data = torch.ones(2, 3)
print(data)                       # tensor([[1., 1., 1.], [1., 1., 1.]])

data = torch.ones_like(data)

# 全为指定值张量
data = torch.full([2, 3], 10)
print(data)                       # tensor([[10, 10, 10], [10, 10, 10]])

data = torch.full_like(data, 20)  # 根据形状创建指定值的张量
print(data)                       # tensor([[20, 20, 20], [20, 20, 20]])
```

> 规律：`xxx(形状)` 创建新张量，`xxx_like(张量)` 按已有张量的形状创建。

---

## 7. 张量元素类型转换

### 方式1：data.type(torch.XXTensor)

```python
data = torch.full([2, 3], 10)
print(data.dtype)               # torch.int64

# 将元素类型转换为 float64 类型
data = data.type(torch.DoubleTensor)
print(data.dtype)               # torch.float64

# 其他转换
# data = data.type(torch.ShortTensor)
# data = data.type(torch.IntTensor)
# data = data.type(torch.LongTensor)
# data = data.type(torch.FloatTensor)
# data = data.type(dtype=torch.float16)
```

### 方式2：data.xxx() 简写

```python
data = torch.full([2, 3], 10)
print(data.dtype)               # torch.int64

# 转换为 float64
data = data.double()
print(data.dtype)               # torch.float64

# 其他转换
# data = data.short()   # int16
# data = data.int()     # int32
# data = data.long()    # int64
# data = data.float()   # float32
# data = data.half()    # float16
```

---

## 附：张量与 NumPy 互相转换（PDF 第二章内容）

### 张量 → NumPy 数组

```python
data_tensor = torch.tensor([2, 3, 4])

# 转换为 numpy 数组（共享内存！改一个另一个也变）
data_numpy = data_tensor.numpy()
print(type(data_numpy))        # <class 'numpy.ndarray'>

data_numpy[0] = 100
print(data_tensor)             # tensor([100, 3, 4])  ← 也变了！

# 用 copy() 避免共享内存
data_numpy = data_tensor.numpy().copy()
data_numpy[0] = 100
print(data_tensor)             # tensor([2, 3, 4])  ← 不变了
```

### NumPy 数组 → 张量

```python
data_numpy = np.array([2, 3, 4])

# 方式1：torch.from_numpy() —— 共享内存
data_tensor = torch.from_numpy(data_numpy)
data_tensor[0] = 100
print(data_numpy)              # [100 3 4]  ← 也变了！

# 方式2：torch.tensor() —— 不共享内存
data_tensor = torch.tensor(data_numpy)
data_tensor[0] = 100
print(data_numpy)              # [2 3 4]  ← 不变了
```

### 标量张量和数字转换

```python
# 只有一个元素的张量，用 item() 提取数值
data = torch.tensor([30, ])
print(data.item())     # 30

data = torch.tensor(30)
print(data.item())     # 30
```

---

## 8. 张量基本运算

### 加减乘除取负号

```python
data = torch.randint(0, 10, [2, 3])
print(data)
# tensor([[3, 7, 4],
#         [0, 0, 6]])

# 1. 不修改原数据
new_data = data.add(10)   # 等价 new_data = data + 10
print(new_data)

# 2. 直接修改原数据（注意：带下划线的是修改原数据本身）
data.add_(10)             # 等价 data += 10
print(data)

# 3. 其他函数
print(data.sub(100))      # 减
print(data.mul(100))      # 乘
print(data.div(100))      # 除
print(data.neg())         # 取负
```

> 记忆：`add / sub / mul / div / neg` 不修改原数据；`add_ / sub_ / mul_ / div_ / neg_` 修改原数据。

### 点乘运算（Hadamard）

```python
# 点乘 = 相同形状的张量，对应位置元素相乘
data1 = torch.tensor([[1, 2], [3, 4]])
data2 = torch.tensor([[5, 6], [7, 8]])

# 方式1：torch.mul
data = torch.mul(data1, data2)
print(data)   # tensor([[ 5, 12], [21, 32]])

# 方式2：运算符 *
data = data1 * data2
print(data)   # tensor([[ 5, 12], [21, 32]])
```

### 矩阵乘法运算

```python
# 要求：第一个矩阵 shape (n, m)，第二个 (m, p)，结果 (n, p)
data1 = torch.tensor([[1, 2], [3, 4], [5, 6]])   # 3x2
data2 = torch.tensor([[5, 6], [7, 8]])            # 2x2

# 方式1：运算符 @
data3 = data1 @ data2
print(data3)   # tensor([[19, 22], [43, 50], [67, 78]])  # 3x2

# 方式2：torch.matmul（对形状更宽容，最后的维度符合矩阵规则即可）
data4 = torch.matmul(data1, data2)
print(data4)
```

> **核心区别**：`*` / `mul` 是对应位置相乘；`@` / `matmul` 是矩阵乘法。神经网络的 `y = Wx + b` 用的是矩阵乘法。

---

## 9. 张量运算函数（常见运算函数）

```python
data = torch.randint(0, 10, [2, 3], dtype=torch.float64)
print(data)

# 1. 计算均值（注意：tensor 必须为 Float 或 Double 类型）
print(data.mean())           # 全部元素的均值
print(data.mean(dim=0))      # 按列计算均值
print(data.mean(dim=1))      # 按行计算均值

# 2. 计算总和
print(data.sum())
print(data.sum(dim=0))       # 按列求和
print(data.sum(dim=1))       # 按行求和

# 3. 计算平方
print(torch.pow(data, 2))

# 4. 计算平方根
print(data.sqrt())

# 5. 指数计算（e 的 n 次方）
print(data.exp())

# 6. 对数计算
print(data.log())            # 以 e 为底
print(data.log2())           # 以 2 为底
print(data.log10())          # 以 10 为底
```

> 注意：`mean()` 要求张量是 float/double 类型，整数张量会报错。

---

## 10. 张量的索引操作

### 准备数据

```python
data = torch.randint(0, 10, [4, 5])
print(data)
# tensor([[0, 7, 6, 5, 9],
#         [6, 8, 3, 1, 0],
#         [6, 3, 8, 7, 3],
#         [4, 9, 5, 3, 1]])
```

### 1. 简单行列索引

```python
print(data[0])      # 第 0 行：tensor([0, 7, 6, 5, 9])
print(data[:, 0])   # 第 0 列：tensor([0, 6, 6, 4])
```

### 2. 列表索引

```python
# 返回 (0,1)、(1,2) 两个位置的元素
print(data[[0, 1], [1, 2]])   # tensor([7, 3])

# 返回 0、1 行的 1、2 列共 4 个元素
print(data[[[0], [1]], [1, 2]])
# tensor([[7, 6],
#         [8, 3]])
```

### 3. 范围索引

```python
# 前 3 行的前 2 列数据
print(data[:3, :2])

# 第 2 行到最后的前 2 列数据
print(data[2:, :2])
```

### 4. 布尔索引

```python
# 第三列大于 5 的行数据
print(data[data[:, 2] > 5])

# 第二行大于 5 的列数据
print(data[:, data[1] > 5])
```

### 5. 多维索引

```python
data = torch.randint(0, 10, [3, 4, 5])

# 获取 0 轴上的第一个数据
print(data[0, :, :])

# 获取 1 轴上的第一个数据
print(data[:, 0, :])

# 获取 2 轴上的第一个数据
print(data[:, :, 0])
```

---

## 11. 张量的形状操作

### reshape()：改变维度

```python
data = torch.tensor([[10, 20, 30], [40, 50, 60]])

# 用 shape 属性或 size() 方法获得形状
print(data.shape, data.shape[0], data.shape[1])   # torch.Size([2, 3]) 2 3
print(data.size(), data.size(0), data.size(1))    # torch.Size([2, 3]) 2 3

# 使用 reshape 修改张量形状
new_data = data.reshape(1, 6)
print(new_data.shape)   # torch.Size([1, 6])
```

### squeeze() 和 unsqueeze()：降维 / 升维

```python
mydata1 = torch.tensor([1, 2, 3, 4, 5])
print('mydata1--->', mydata1.shape, mydata1)   # torch.Size([5])

# 在 0 维度上扩展维度 → 1*5
mydata2 = mydata1.unsqueeze(dim=0)
print(mydata2.shape)   # torch.Size([1, 5])

# 在 1 维度上扩展维度 → 5*1
mydata3 = mydata1.unsqueeze(dim=1)
print(mydata3.shape)   # torch.Size([5, 1])

# 在 -1 维度上扩展维度 → 5*1（-1 表示最后一个维度）
mydata4 = mydata1.unsqueeze(dim=-1)
print(mydata4.shape)   # torch.Size([5, 1])

# squeeze()：压缩维度（删除形状为 1 的维度）
mydata5 = mydata4.squeeze()
print(mydata5.shape)   # torch.Size([5])
```

### transpose() 和 permute()：交换维度

```python
import numpy as np

data = torch.tensor(np.random.randint(0, 10, [3, 4, 5]))
print('data shape:', data.size())   # torch.Size([3, 4, 5])

# transpose：交换指定的两个维度（3 和 4 交换 → (2, 4, 3)）
mydata2 = torch.transpose(data, 1, 2)
print(mydata2.shape)   # torch.Size([3, 5, 4])

# 要变成 (4, 5, 3) 需要交换多次
mydata3 = torch.transpose(data, 0, 1)
mydata4 = torch.transpose(mydata3, 1, 2)
print(mydata4.shape)   # torch.Size([4, 5, 3])

# permute：一次交换更多维度（更省事）
mydata5 = torch.permute(data, [1, 2, 0])
print(mydata5.shape)   # torch.Size([4, 5, 3])

# 等价写法（张量对象直接调用）
mydata6 = data.permute([1, 2, 0])
print(mydata6.shape)   # torch.Size([4, 5, 3])
```

> 区别：`transpose` 只能交换两个维度；`permute` 可以一次排列所有维度。

### view() 和 contiguous()：连续性

```python
data = torch.tensor([[10, 20, 30], [40, 50, 60]])
print('data--->', data, data.shape)

# 1. 判断张量是否连续
print(data.is_contiguous())   # True

# 2. view 修改形状
mydata2 = data.view(3, 2)
print(mydata2, mydata2.shape) # tensor([[10, 20], [30, 40], [50, 60]])

# 3. 使用 transpose 后就不连续了
mydata3 = torch.transpose(data, 0, 1)
print(mydata3.shape)                    # torch.Size([3, 2])
print(mydata3.is_contiguous())          # False  ← 不连续！

# 4. 先用 contiguous() 变成连续，再用 view
print(mydata3.contiguous().is_contiguous())   # True
mydata4 = mydata3.contiguous().view(2, 3)
print(mydata4.shape, mydata4)
```

> **重点坑**：张量经过 `transpose` 或 `permute` 之后，内存不连续，**不能用 view()**，要先 `.contiguous()` 再 `.view()`。`reshape()` 没有这个限制。

---

## 12. 张量的拼接操作

### torch.cat()：按指定维度拼接（不改变维度数）

```python
data1 = torch.randint(0, 10, [1, 2, 3])
data2 = torch.randint(0, 10, [1, 2, 3])

# 按 0 维度拼接 → [2, 2, 3]
new_data = torch.cat([data1, data2], dim=0)
print(new_data.shape)

# 按 1 维度拼接 → [1, 4, 3]
new_data = torch.cat([data1, data2], dim=1)
print(new_data.shape)

# 按 2 维度拼接 → [1, 2, 6]
new_data = torch.cat([data1, data2], dim=2)
print(new_data.shape)
```

### torch.stack()：在新维度上拼接（增加一个新维度）

```python
data1 = torch.randint(0, 10, [2, 3])
data2 = torch.randint(0, 10, [2, 3])

# 在 0 维度上拼接 → [2, 2, 3]
new_data = torch.stack([data1, data2], dim=0)
print(new_data.shape)

# 在 1 维度上拼接 → [2, 2, 3]
new_data = torch.stack([data1, data2], dim=1)
print(new_data.shape)

# 在 2 维度上拼接 → [2, 3, 2]
new_data = torch.stack([data1, data2], dim=2)
print(new_data.shape)
```

> **区别**：`cat` 不改变维度数（在已有维度上拼）；`stack` 增加一个新维度（叠罗汉），且要求所有输入张量形状完全相同。

---

## 13. 自动微分模块

训练神经网络最常用的算法是**反向传播**。参数（模型权重）会根据损失函数关于对应参数的梯度进行调整。PyTorch 内置了名为 `torch.autograd` 的微分模块，支持任意计算图的自动梯度计算。

### 核心概念

- `requires_grad=True`：自动计算梯度并把值保存到 `grad` 中
- `y.backward()`：计算梯度（y 必须是标量）
- `x.grad`：获取 x 点的梯度值（**会累加上一次梯度值，需要清零**）

### 梯度基本计算（标量）

```python
x = torch.tensor(10, requires_grad=True, dtype=torch.float32)
print("x-->", x)

# 定义一个曲线
y = 2 * x ** 2
print("y-->", y)              # tensor(200.)
print(y.grad_fn)              # 查看梯度函数类型

# y 是标量，可以直接 backward
y.sum().backward()
# y'|(x=10) = (2*x**2)'|(x=10) = 4x|(x=10) = 40
print("x的梯度值是:", x.grad)   # tensor(40.)
```

### 梯度基本计算（向量）

```python
x = torch.tensor([10, 20], requires_grad=True, dtype=torch.float32)
print("x-->", x)

y = 2 * x ** 2
print("y-->", y)   # tensor([200., 800.])

# x 和 y 都是向量张量，不能直接求导 → 用 y.sum() 转成标量
y.sum().backward()
print("x.grad-->", x.grad)   # tensor([40., 80.])
```

> **重点**：PyTorch 不支持向量张量对向量张量的求导，只支持**标量对向量的求导**。所以向量要 `y.sum()` 转成标量再 backward。

### 梯度下降法求最优解

> 公式：`w = w - r * grad`（r 是学习率，grad 是梯度值）

```python
# 求 y = x**2 + 20 的极小值点
# 1. 定义点 x=10
x = torch.tensor(10, requires_grad=True, dtype=torch.float32)

# 2. 循环迭代 1000 次
for i in range(1, 1001):
    # 3-1 正向计算（前向传播）
    y = x ** 2 + 20
    # 3-2 梯度清零（grad 属性会累加历史梯度，需手工清零）
    if x.grad is not None:
        x.grad.zero_()
    # 3-3 反向传播
    y.backward()
    # 3-4 梯度更新
    # 注意：用 x.data 修改，前后 x 的内存空间一样
    x.data = x.data - 0.01 * x.grad   # 不能写成 x = x - 0.01 * x.grad
    if i % 200 == 0:
        print(f'次数:{i} 权重x:{x.item():.6f} y:{y.item():.6f}')

# 结果：x 趋近 0，y 趋近最小值 20
```

### 梯度计算注意点

```python
x1 = torch.tensor([10, 20], requires_grad=True, dtype=torch.float64)

# 不能将自动微分的张量直接转换成 numpy 数组（会报错）
# print(x1.numpy())  # RuntimeError!

# 通过 detach() 方法产生一个新张量，作为叶子结点，不再自动微分
x2 = x1.detach()
print(x1.requires_grad)   # True
print(x2.requires_grad)   # False

# x1 和 x2 共享同一份内存数据
print(x1.data)   # tensor([10., 20.], dtype=torch.float64)
print(x2.data)   # tensor([10., 20.], dtype=torch.float64)

# 现在可以转 numpy 了
print(x2.numpy())   # [10. 20.]
```

### 自动微分模块应用（简单神经网络）

```python
# 输入张量 2*5
x = torch.ones(2, 5)
# 目标值 2*3
y = torch.zeros(2, 3)
# 设置要更新的权重和偏置（requires_grad=True）
w = torch.randn(5, 3, requires_grad=True)
b = torch.randn(3, requires_grad=True)
# 网络输出：矩阵乘法
z = torch.matmul(x, w) + b
# 设置损失函数并计算损失
loss = torch.nn.MSELoss()
loss = loss(z, y)
# 自动微分
loss.backward()
# 打印 w, b 的梯度（backward 计算的值存在 grad 中）
print("W的梯度:", w.grad)
print("b的梯度:", b.grad)
```

---

## 14. 案例——线性回归案例

使用 PyTorch 的各个组件构建线性回归。模型构建流程分四步：

```
准备训练集数据 → 构建模型 → 设置损失函数和优化器 → 模型训练
```

**用到的 API（和手写版对比）**：

| 手写 | PyTorch API |
|---|---|
| 假设函数 `y = wx + b` | `nn.Linear(in_features, out_features)` |
| 平方损失 | `nn.MSELoss()` |
| 梯度下降手写更新 | `optim.SGD(params, lr)` |
| 手动分批 | `data.DataLoader` |

### 完整代码

```python
# 导入相关模块
import torch
from torch.utils.data import TensorDataset   # 构造数据集对象
from torch.utils.data import DataLoader      # 数据加载器
from torch import nn                         # nn 模块：损失函数和假设函数
from torch import optim                      # optim 模块：优化器
from sklearn.datasets import make_regression # 创建线性回归数据集
import matplotlib.pyplot as plt

plt.rcParams['font.sans-serif'] = ['SimHei']     # 显示中文
plt.rcParams['axes.unicode_minus'] = False       # 显示负号


# ============ 1. 准备训练集数据 ============
def create_dataset():
    x, y, coef = make_regression(
        n_samples=100,      # 样本数
        n_features=1,       # 特征数
        noise=10,           # 噪声
        coef=True,          # 返回系数
        bias=14.5,          # 截距
        random_state=0
    )
    # 转换为张量类型
    x = torch.tensor(x)
    y = torch.tensor(y)
    return x, y, coef


if __name__ == "__main__":
    # 生成数据
    x, y, coef = create_dataset()

    # ============ 2. 构建数据集和数据加载器 ============
    dataset = TensorDataset(x, y)
    dataloader = DataLoader(
        dataset=dataset,
        batch_size=16,      # 批量训练样本数
        shuffle=True        # 打乱顺序
    )

    # ============ 3. 构建模型 ============
    # in_features：输入张量的大小；out_features：输出张量的大小
    model = nn.Linear(in_features=1, out_features=1)

    # ============ 4. 设置损失函数和优化器 ============
    criterion = nn.MSELoss()                          # 平方损失函数
    optimizer = optim.SGD(params=model.parameters(), lr=1e-2)   # 优化器

    # ============ 5. 模型训练 ============
    epochs = 100
    epoch_loss = []       # 记录每个 epoch 的损失
    total_loss = 0.0
    train_sample = 0.0

    for _ in range(epochs):
        for train_x, train_y in dataloader:
            # 将一个 batch 的训练数据送入模型
            y_pred = model(train_x.type(torch.float32))
            # 计算损失（均方误差，当前批次所有样本的平均误差）
            loss = criterion(y_pred, train_y.reshape(-1, 1).type(torch.float32))
            total_loss += loss.item()
            train_sample += 1
            # 梯度清零
            optimizer.zero_grad()
            # 反向传播
            loss.backward()
            # 更新参数
            optimizer.step()
        # 计算当前 epoch 的平均误差
        epoch_loss.append(total_loss / train_sample)

    # ============ 6. 绘制损失变化曲线 ============
    plt.plot(range(epochs), epoch_loss)
    plt.title('损失变化曲线')
    plt.grid()
    plt.show()

    # ============ 7. 绘制拟合直线对比 ============
    plt.scatter(x, y)
    xx = torch.linspace(x.min(), x.max(), 1000)
    y1 = torch.tensor([v * model.weight + model.bias for v in xx])   # 训练结果
    y2 = torch.tensor([v * coef + 14.5 for v in xx])                 # 真实直线
    plt.plot(xx, y1, label='训练')
    plt.plot(xx, y2, label='真实')
    plt.grid()
    plt.legend()
    plt.show()
```

### 训练循环五步走（背下来）

```
① optimizer.zero_grad()  梯度清零
② y_pred = model(x)      前向计算
③ loss = criterion()     算损失
④ loss.backward()        反向传播
⑤ optimizer.step()       更新参数
```

---

## 结尾 · 总结

PyTorch 模型构建流程：

```
准备训练集数据 → 构建模型 → 设置损失函数和优化器 → 模型训练
```

这份笔记：
- 张量创建、类型转换、运算、索引、形状、拼接
- 自动微分模块（requires_grad / backward / grad / detach）
- 线性回归完整案例（nn.Linear / MSELoss / SGD / DataLoader）
