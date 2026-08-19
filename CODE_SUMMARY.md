# delay 实验代码与结果摘要

> 写于 2026-08-19，对话上下文太长时供新对话快速上手。

## 1. 目录结构

```
delay/
├─ run_analysis_1s.m               ← 启动：时延实验（非饱和，逻辑一）
├─ run_analysis_1s_batch_m.m       ← 启动：时延实验（逻辑二，M=1:6，λ=16,30）
├─ run_analysis_1s_batch_m_lambda50.m  ← 逻辑二 λ=50 快速扫描
├─ run_analysis_1s_batch_m_lambda30.m  ← 逻辑二 λ=30 专用扫描
├─ run_delay_m_analysis.m          ← M 扫描共用流水线与 CF 基线合并
├─ plot_delay_m_comparison.m       ← M 扫描绘图
├─ run_saturation_analysis_1s.m     ← 启动：饱和吞吐实验
├─ run_experiment.m                 ← 核心流水线：调 q → 评估 → 汇总结
├─ default_experiment_config.m      ← 所有默认参数（配置文件）
├─ run_protocol_v2.m                ← 协议分发器
├─ finalize_sim_result.m            ← 非饱和结果汇总（计算时延等，含结构性截尾处理）
├─ finalize_saturation_result.m     ← 饱和结果汇总（计算吞吐等）
├─ prepare_scenario_v2.m            ← 拓扑/扇区/场景生成
├─ sim_utils.m                      ← 公共工具函数
├─ txop_mode.m / is_batch_txop_mode.m ← TXOP 模式辅助
├─ build_piecewise_q_grid.m         ← 分段十倍区间 q 粗网格
│
├─ simulate_aloha_v2.m              ← SF-CF / SF-CB 时隙模拟器（SF-CB 含真实 RTS/CTS 时序）
├─ simulate_sb_cf_v2.m              ← SB-CF（事件驱动 CSMA，无 RTS/CTS）
├─ simulate_sb_cb_v2.m              ← SB-CB（事件驱动，DIFS+9µs 边界 Bernoulli）
├─ simulate_unslotted_sf_cb.m       ← unslotted 分发包装
├─ simulate_unslotted_engine.m      ← unslotted & sb_cb 共用连续时间引擎
├─ simulate_s7_v2.m                 ← S7（sub7 辅助 MLO/SLO）
│
├─ run_lambda_sweep.m               ← λ 扫描脚本（M=1，λ=5,10,16,20）
├─ run_lambda_sweep_fixpoints.m     ← 异常点补跑（3 种子 tune/eval）
├─ run_lambda_sweep_fixpoints2.m    ← sb_cb 5 种子补跑
│
├─ results_v2/                      ← 输出根目录
│   ├─ lambda_sweep_20260814_060540_597e78800cf0/  ← 最终 λ 扫描结果
│   │   ├─ summary.csv              ← 所有条件结果（q、时延、排队等）
│   │   ├─ checkpoints/             ← 28 个 .mat checkpoint
│   │   └─ figures/                 ← delay/access/completion vs λ PNG
│   ├─ R9_merged/                   ← 旧版 M 扫描合并结果
│   ├─ R9_merged_logic1/            ← 逻辑一改进后 M 扫描结果（λ=16,30）
│   ├─ R9_merged_batch_M/           ← 逻辑二 M 扫描结果（λ=16,30，未完成）
│   ├─ R9_merged_batch_M_lambda50/  ← 逻辑二 λ=50 扫描结果
│   ├─ R9_merged_batch_M_lambda30/  ← 逻辑二 λ=30 扫描结果（待运行）
│   └─ saturation-*/                ← 饱和吞吐结果
│
└─ CODE_SUMMARY.md                  ← 这个文件
```

## 2. 核心时序常量（所有协议统一）

| 参数 | 值 | 说明 |
|------|-----|------|
| `CONN_OVERHEAD_US` | 162.5 µs | 一个数据包的传输时间（也是 SF-CB 的预约时隙） |
| `RTS_US` | 14.5 µs | 毫米波 RTS 帧（mmWave） |
| `CTS_US` | 14.5 µs | 毫米波 CTS 帧（mmWave） |
| `SIFS_US` | 16 µs | 短帧间隔 |
| `DIFS_US` | 34 µs | 分布式帧间隔（sb_cb/sb_cf 使用） |
| `SLOT_US` | 9 µs | 微时隙（SB 类协议 9µs 边界对齐） |
| `CTS_TIMEOUT_US` | 132 µs | CTS 超时 = SIFS + CTS sweep |
| `CTS_SWEEP_US` | 116 µs | 8 扇区定向 CTS 扫描 |
| `DIFS_TICKS` | 4 | 未使用（历史遗留） |

Sub7 时序：
| 参数 | 值 |
|------|-----|
| `SUB7.RTS_US` | 26.7 µs |
| `SUB7.CTS_US` | 24.7 µs |
| `SUB7.SLO_RTS_US` | 26.7 µs |
| `SUB7.SLO_CTS_US` | 24.7 µs |

## 3. 协议列表与模拟器

| 协议名称 | 模拟器文件 | 竞争方式 | RTS/CTS | M 含义 |
|---------|-----------|---------|---------|--------|
| **sf_cf** | simulate_aloha_v2.m | 时隙 ALOHA，slot=M×162.5µs | 无 | TXOP 长度(slots) |
| **sf_cb** | simulate_aloha_v2.m | 时隙预约 ALOHA，RTS→SIFS→8扇区CTS→SIFS→DATA | 有（CTS 单 RTS 简化） | TXOP 包数 |
| **sb_cf** | simulate_sb_cf_v2.m | CSMA 9µs 边界，DIFS 空闲后竞 | 无（直接发 DATA） | TXOP 包数 |
| **sb_cb** | simulate_unslotted_engine.m (mode='sb_cb') | CSMA 9µs 边界，DIFS 空闲后 q 竞 | 有（RTS/CTS/SINR） | TXOP 包数 |
| **unslotted** | simulate_unslotted_engine.m (mode='unslotted') | 纯 ALOHA（无监听），指数退避 | 有（RTS/CTS/SINR） | TXOP 包数 |
| **s7_clean** | simulate_s7_v2.m | sub7 辅助（MLO 竞争，SLO=0） | 有（sub7 RTS/CTS） | TXOP 包数 |
| **s7_busy** | simulate_s7_v2.m | sub7 辅助（MLO 竞争，SLO=10 持久饱和） | 有（sub7 RTS/CTS） | TXOP 包数 |

拓扑：n=40 MLO 节点，8 扇区，定向天线。cca_mode='directional'，rx_sens=-62dBm，CTS SINR 阈值 6dB，DATA SINR 阈值 21dB。

## 4. TXOP 模式

### 4.1 逻辑一：ready_queue（默认）
- `cfg.txop_mode = ''ready_queue''`
- 队列有包即可参与竞争；成功后发送 `min(队列包数, M)` 个包
- CF 协议（sf_cf, sb_cf）固定 M=1，作为水平参考线
- 尾部不足 M 个包正常发送，不存在结构性截尾

### 4.2 逻辑二：batch_M
- `cfg.txop_mode = ''batch_M''`
- 每累计 M 个包形成一个预约请求，只有请求队列非空才竞争
- 成功后发送该请求对应的 M 个包
- 尾部不足 M 个包的批次标记为**结构性截尾**，不计入完成率分母
- 不包含 CF 协议

### 4.3 包模型
- 包长固定 = 1 conn_slot = 162.5µs（不随 M 变）
- M = TXOP 长度 = 一次预约/成功可发的最大包数
- 到达：每 9µs 判定一次（mini-slot），按泊松近似生成 trace
- λ 单位：pkt/STA/s

## 5. q 扫描流程（M 扫描专用）

### 5.1 默认粗扫网格（分段线性）
```
[1e-4:1e-4:1e-3, 1e-3:1e-3:1e-2, 1e-2:1e-2:1e-1, 1e-1:1e-1:1, 0.025]
```
每个十倍区间等距取 10 个点，共 37 个点，去重后约 37 个。

### 5.2 多候选盆地
- 粗扫每个 q 跑 1 个种子
- 保留最多 3 个稳定低延迟盆地
- 每个候选邻域做 7 点对数细扫，各 1 种子

### 5.3 候选验证
- 综合延迟最低的前 2-3 个候选 q 再补到 3 个种子
- 要求所有种子稳定

### 5.4 最终评估
- best_q 用 3 个独立评估种子（到达种子和协议种子均与 tune 不同）
- 3 个种子必须全部稳定，完成率 >= 0.99

## 6. 如何运行

```matlab
cd('C:\Users\Administrator\Documents\delay');

% === 时延 λ 扫描（M=1，λ=5,10,16,20） ===
run_lambda_sweep();

% === 逻辑一：M=1:6 时延扫描（λ=16,30） ===
run_analysis_1s();

% === 逻辑二：M=1:6 时延扫描（λ=16,30） ===
run_analysis_1s_batch_m();

% === 逻辑二：M=1:6 时延扫描（λ=50 高负载测试） ===
run_analysis_1s_batch_m_lambda50();

% === 逻辑二：M=1:6 时延扫描（λ=30 专用） ===
run_analysis_1s_batch_m_lambda30();

% === 饱和吞吐（M=1:6） ===
run_saturation_analysis_1s();
```

或者从命令行：
```
cd C:\Users\Administrator\Documents\delay
"D:\Software\Matlab\bin\matlab.exe" -batch "run_analysis_1s_batch_m_lambda30();"
```

## 7. SF-CB 时序修正说明

SF-CB 使用真实的 RTS/CTS 预约时序，而非旧版的简化竞争时隙模型：

- 每个预约时隙开始时，有请求的节点按 Bernoulli(q) 决定是否发送 RTS
- 只有 1 个节点发送 RTS 则预约成功（RTS 冲突则整个 162.5µs 预约时隙浪费）
- RTS 成功后，AP 经过 SIFS（16µs）后扫描 8 个扇区发送 CTS，再经过 SIFS
- 预约总时长固定为 162.5µs = RTS(14.5) + SIFS(16) + 8×CTS(116) + SIFS(16)
- 预约成功后数据在下一个预约时隙边界开始
- 预约时延计入 `control_delay_us`，DATA 时延计入 `data_delay_us`

## 8. 结构性截尾（batch_M 模式专用）

`finalize_sim_result.m` 支持 `raw.structural_censored` 字段：

- 逻辑二仿真结束时，节点剩余不足 M 个包的尾部分配为结构性截尾
- `n_eligible` = 总到达包数 - 结构性截尾包数
- 完成率 = `n_completed_eligible / n_eligible`
- 稳定性判断使用 `eligible_arrival_rate_pkt_s` 而非原始到达率
- 原始完成率保留在 `raw_completion_ratio` 中，供参考

## 9. 新增脚本

| 脚本 | 说明 |
|------|------|
| `run_analysis_1s_batch_m.m` | 逻辑二 λ=16,30 扫描 |
| `run_analysis_1s_batch_m_lambda50.m` | 逻辑二 λ=50 快速扫描 |
| `run_analysis_1s_batch_m_lambda30.m` | 逻辑二 λ=30 专用扫描 |
| `run_delay_m_analysis.m` | M 扫描共用流水线 |
| `plot_delay_m_comparison.m` | 绘图函数 |
| `txop_mode.m` / `is_batch_txop_mode.m` | TXOP 模式查询 |
| `build_piecewise_q_grid.m` | 分段粗扫网格生成 |

## 10. 饱和吞吐实验

见 `run_saturation_analysis_1s.m`，与逻辑一/逻辑二共享同一套模拟器。

## 11. sf_cb_lightload_study 文件夹
- 该目录是旧版协议脚本，不再使用
- 所有实验都在 delay 目录主模拟器运行
