# 第 10 章：主题分类器与模型微调（源码解析）

**日期**：2026-09-18
**标签**：AI Agent · OpsDesk · 源码解析


> 对应笔记：`第 10 章：主题分类器与模型微调（项目落地笔记）.md`
> 本解析按脚本流水线走读，重点拆评估报告的数字结构和黄金样例的门控逻辑。

## 涉及文件

| 文件/数据 | 职责 |
|---|---|
| `scripts/ch10/build_corpus.py` / `corpus_lib.py` / `_gen_corpus.py` | 规则生成语料（origin=simulated） |
| `scripts/ch10/prelabel.py` | prompt 批量预标 |
| `scripts/ch10/validate_golden.py` + `golden_samples.jsonl` | 黄金样例验证（预标 prompt 把关） |
| `scripts/ch10/build_dataset.py` | 分层划分 + 训练集增强 |
| `scripts/ch10/train.py` | RoBERTa-wwm-ext 全参微调 |
| `scripts/ch10/evaluate.py` | 每类 P/R/F1 + 混淆矩阵 + 红线 |
| `scripts/ch10/export_onnx.py` | 导出 ONNX |
| `scripts/ch10/serve.py` + `inference_lib.py` | 推理服务 :8110 |
| `scripts/ch10/classify_pool.py` | 旁路批量归类 |
| `scripts/ch10/scan_threshold_replay.py` | 阈值扫描重放 |
| `data/ch10/reports/eval_report.json` / `golden_report.json` | 实测评估报告 |

## 流水线总览

```
build_corpus（规则造语料 430 条, origin=simulated）
  → validate_golden（30 条黄金样例验预标 prompt, 过 80% 才放行）
  → prelabel（prompt 批量预标语料）
  → build_dataset（分层划分 train/dev/test + 增强）
  → train（RoBERTa-wwm-ext 全参微调, threshold 0.3）
  → evaluate（每类 P/R/F1 + 混淆矩阵 + 红线 严0.9/中0.8）
  → export_onnx → serve(:8110) / classify_pool（旁路批量归类）
```

每道闸都是"验证过了才进下一步"，不是一口气冲到底。

## 语料生成：corpus_lib 的设计意图

`build_corpus.py` + `corpus_lib.py` 按"意图 × 说法变体 × 设备/场景填充"生成语料。三个要点：

- **`origin=simulated` 标记**：每条例数据都标来源。这不是形式主义——评估、后续补真实数据时，能精确区分"模型见过的模板"和"真实用户话术"，防自欺
- **变体覆盖**：同一意图多种说法（"帮我报修一下" / "XX 坏了" / "XX 不转了快看看"），让模型学的是意图不是字面
- **尺寸适配补充**（supplement_sizefit.jsonl）：让序列长度分布贴近真实输入，避免训练/推理时 padding 浪费——小数据集的工程细节，影响实际吞吐

## 黄金样例：validate_golden 的门控逻辑

`golden_samples.jsonl` 30 条人肉标注的边界样例，`validate_golden.py` 跑预标 prompt 验证。实测报告结构：

```json
{
  "total": 30,
  "hits": 25,
  "rate": 0.8333,
  "pass_line": 0.8,
  "passed": true,
  "failures": [...5 条失败明细...]
}
```

逐字段含义：

- `total` / `hits` / `rate`：命中率 83.3%
- `pass_line: 0.8`：过线阈值——**prompt 质量达标才放行批量预标**
- `passed: true`：门控通过
- `failures`：失败明细（text + gold + pred），每条都是分类边界的真实样本

**门控的意义**：批量预标 = 用 prompt 给全部语料打标签，prompt 不行 → 标签全错 → 训练喂脏数据。先用 30 条刁钻样例验 prompt，过线才放行，是把错误挡在训练之前。失败明细里 gold/pred 对照（如"电机不转了快来看看" gold=设备报修 pred=故障咨询）是后续迭代 prompt 的直接依据。

## 训练与评估：eval_report 的结构拆解

`evaluate.py` 产出 `eval_report.json`，结构：

```json
{
  "test_size": 44,          // 测试集 44 条
  "threshold": 0.3,         // 分类置信度阈值
  "red_lines": {"严": 0.9, "中": 0.8},   // 红线：严类/中类
  "micro": {"p": 1.0, "r": 1.0, "f1": 1.0},
  "macro": {"p": 1.0, "r": 1.0, "f1": 1.0},
  "classes": [...10 类明细...],
  "errors": [],
  "total_cells": 440,       // 10 类 × 44 条的混淆矩阵单元格
  "total_fp": 0,
  "total_fn": 0,
  "red_line_passed": true
}
```

逐点拆：

1. **micro / macro 双口径**：micro（按样本汇总算）和 macro（每类先算再平均）都报，防单一口径掩盖类别失衡
2. **每类明细带 support、TP/FP/FN/TN**：

```json
{
  "name": "设备报修",
  "severity": "严",
  "p": 1.0, "r": 1.0, "f1": 1.0,
  "support": 5,          // 该类测试样本 5 条
  "red_line": 0.9, "passed": true,
  "tn": 39, "fp": 0, "fn": 0, "tp": 5
}
```

support 4-5 条、全 TP、FP/FN 全 0——**F1=1.0 的真相：44 条测试集太干净**，模板语料变体模型背得过来，真实边界在黄金样例失败里。所以读这份报告的正确姿势是：数字好看 ≠ 分类完美，红线门控（严类 0.9 必须过）才是兜底。

3. **severity 分级红线**：严类（设备报修/工单查询/故障咨询/安全规程）0.9，中类 0.8，宽类（其他）不设红线——**分错代价不同，门槛不同**。报修分错成故障咨询（用户想修没修成）和"其他"分错成设备信息（不影响任何业务动作），严重性完全不同
4. **`total_cells: 440`**：10 类 × 44 条 = 混淆矩阵全格，报告里 errors 空数组表示零错误
5. **threshold 0.3**：分类置信度阈值——低于 0.3 不输出该标签（宁可漏不可错，结合红线）

## 部署链路：export / serve / classify_pool

- `export_onnx.py`：PyTorch 模型转 ONNX——跨平台、无 Python 运行时依赖、推理快
- `serve.py`：ONNX 推理服务 :8110（FastAPI），主应用通过旁路调用
- `classify_pool.py`：**旁路批量归类**——对历史对话池批量打主题标签，不实时介入用户对话（微调分类器不替代主链路的 LLM 意图分类，两者职责不同：实时对话要 9 类细粒度 + 置信度，走 LLM；批量历史归类要快、便宜，走小模型）
- `scan_threshold_replay.py`：阈值扫描重放——扫不同 threshold 下的 P/R 曲线，用数据选阈值而不是拍脑袋

## 关键设计点小结

| 设计 | 解决的问题 |
|---|---|
| 规则造语料 + origin=simulated 标记 | 无现成语料时的起点，且数据来源可审计 |
| 黄金样例门控（过 80% 才放行预标） | 预标 prompt 不行 → 全语料标签错 → 训练喂脏数据 |
| severity 分级红线（严0.9/中0.8） | 分错代价不同，门槛不同 |
| micro + macro 双口径 | 防单一口径掩盖类别失衡 |
| threshold 0.3 低阈值 + 红线 | 宁可漏不可错，红线兜底 |
| 旁路批量归类 | 小模型干浅任务，不替代主链路 LLM 意图 |
| ONNX 导出 | 跨平台轻部署，推理快 |
