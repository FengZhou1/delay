# delay 实验代码与结果摘要

> 写于 2026-08-14，对话上下文太长时供新对话快速上手。

## 1. 目录结构

```
delay/
├─ run_analysis_1s.m               ← 启动：时延实验（非饱和，逻辑一）
├─ run_analysis_1s_batch_m.m       ← 启动：时延实验（逻辑二，M 包请求队列）
├─ run_delay_m_analysis.m          ← M 扫描共用流水线与 CF 基线合并
├─ plot_delay_m_comparison.m       ← M 扫描绘图
├─ run_saturation_analysis_1s.m     ← 启动：饱和吞吐实验
├─ run_experiment.m                 ← 核心流水线：调 q → 评估 → 汇总结
├─ default_experiment_config.m      ← 所有默认参数（配置文件）
├─ run_protocol_v2.m                ← 协议分发器
├─ finalize_sim_result.m            ← 非饱和结果汇总（计算时延等）
├─ finalize_saturation_result.m     ← 饱和结果汇总（计算吞吐等）
├─ prepare_scenario_v2.m            ← 拓扑/扇区/场景生成
├─ sim_utils.m                      ← 公共工具函数
├─ txop_mode.m / is_batch_txop_mode.m ← TXOP 模式辅助
├─ build_piecewise_q_grid.m         ← 分段十倍区间 q 粗网格
│
├─ simulate_aloha_v2.m              ← SF-CF / SF-CB 时隙模拟器
├─ simulate_sb_cf_v2.m              ← SB-CF（事件驱动 CSMA，无 RTS/CTS）
├─ simulate_sb_cb_v2.m              ← SB-CB（事件驱动，DIFS+9µs 边界 Bernoulli）
├─ simulate_unslotted_sf_cb.m       ← unslotted 分发包装
├─ simulate_unslotted_engine.m      ← unslotted & sb_cb 共用连续时间引擎
├─ simulate_s7_v2.m                 ← S7（sub7 辅助 MLO/SLO）
│
├─ run_lambda_sweep.m               ← λ 扫描脚本（这次新增）
├─ run_lambda_sweep_fixpoints.m     ← 异常点补跑（3 种子 tune/eval）
├─ run_lambda_sweep_fixpoints2.m    ← sb_cb 5 种子补跑
│
├─ results_v2/                      ← 输出根目录
│   ├─ lambda_sweep_20260814_060540_597e78800cf0/  ← 最终 λ 扫描结果
│   │   ├─ summary.csv              ← 所有条件结果（q、时延、排队等）
│   │   ├─ checkpoints/             ← 28 个 .mat checkpoint
│   │   └─ figures/                 ← delay/access/completion vs λ PNG
│   ├─ lambda_sweep_20260814_024312_84a1e9525269/  ← 旧版（q 卡 0.2 bug）
│   ├─ lambda_sweep_20260814_041553_d66ecc2e2d32/  ← 中版（q 到 0.45）
│   ├─ R9_merged/                   ← 之前 M 扫描合并结果
│   ├─ R9_merged_logic1/            ← 逻辑一改进后的 M 扫描结果
│   └─ R9_merged_batch_M/           ← 逻辑二 M 扫描结果
│   └─ saturation-*/                ← 饱和吞吐结果
│
└─ CODE_SUMMARY.md                  ← 这个文件
```

## 2. 核心时序常量（所有协议统一）

| 参数 | 值 | 说明 |
|------|-----|------|
| `CONN_OVERHEAD_US` | 162.5 µs | 一个数据包的传输时间（也是 SF-CB 的竞争时隙） |
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

| 协议名称 | 模拟器文件 | 竞争方式 | 有无 RTS/CTS | M 含义 |
|---------|-----------|---------|-------------|--------|
| **sf_cf** | simulate_aloha_v2.m | 时隙 ALOHA，slot=M×162.5µs | 无 | TXOP 长度(slots) |
| **sf_cb** | simulate_aloha_v2.m | 时隙预约 ALOHA，RTS→SIFS→8扇区CTS→SIFS，DATA 在下一个时隙开始 | 有 RTS/CTS 预约时序（CTS 单 RTS 简化） | TXOP 包数 |
| **sb_cf** | simulate_sb_cf_v2.m | CSMA 9µs 边界，DIFS 空闲后竞 | 无（直接发 DATA） | TXOP 包数 |
| **sb_cb** | simulate_unslotted_engine.m (mode='sb_cb') | CSMA 9µs 边界，DIFS 空闲后 q 竞 | 有（RTS/CTS/SINR） | TXOP 包数 |
| **unslotted** | simulate_unslotted_engine.m (mode='unslotted') | 纯 ALOHA（无监听），指数退避 | 有（RTS/CTS/SINR） | TXOP 包数 |
| **s7_clean** | simulate_s7_v2.m | sub7 辅助（MLO+SLO clean） | 有（sub7 RTS/CTS） | TXOP 包数 |
| **s7_busy** | simulate_s7_v2.m | sub7 辅助（MLO+SLO 忙碌） | 有（sub7 RTS/CTS） | TXOP 包数 |

拓扑：n=40 MLO 节点，8 扇区，定向天线。cca_mode='directional'，rx_sens=-62dBm，CTS SINR 阈值 6dB，DATA SINR 阈值 21dB。

## 4. 当前运行配置（延时实验）

### 4.1 包模型（最新设计）
- 包长固定 = 1 conn_slot = 162.5µs（不随 M 变）
- M = TXOP 长度 = 一次预约/成功可发的最大包数
- 逻辑一：队列有包即可竞争；成功时发 `min(队列包数, M)` 个包
- 逻辑二：每累计 M 个包形成一个预约请求，只有请求队列非空才竞争；成功后发送该请求对应的 M 个包
- 到达：每 9µs 判定一次（mini-slot），按泊松近似生成 trace
- λ 单位：pkt/STA/s

### 4.2 λ 扫描（时延 vs λ，M=1）
- 脚本：`run_lambda_sweep.m`（新增，不改现有代码）
- λ = [5, 10, 16, 20] pkt/STA/s
- M = 1（固定单包，无 TXOP 聚合）
- 7 个协议全跑
- 每个 (协议, λ) 独立 tune → eval → 输出到 checkpoints + summary.csv
- 运行命令：`run_lambda_sweep()` 或 MATLAB -batch

### 4.3 q 扫描与选择（M 扫描专用）
- 默认配置使用 **协议专属 q 网格**（`cfg.protocol_q_grids_enabled=true`）
- 粗扫：四个十倍区间各 10 点，`[1e-4,1e-3]`、`[1e-3,1e-2]`、`[1e-2,1e-1]`、`[1e-1,1]`，再加 `q=0.025`
- 多候选盆地：粗扫后选最多 3 个稳定低延迟盆地，对每个候选邻域做 7 点对数细扫
- 候选验证：综合延迟最低的前 2 至 3 个候选 q 再补到 3 个种子
- 最终评估：best_q 用 3 个独立评估种子
- 逻辑二尾部不足 M 个包的批次标记为结构性截尾，不计入完成率分母

### 4.4 饱和吞吐实验
- 脚本：`run_saturation_analysis_1s.m`
- M = [1:6]，每个协议生成"每节点每 M×162.5µs 到达 1 包"的确定性 trace
- 吞吐指标：`payload_success_overlap_us / measure_us`

### 4.5 注意
- `run_lambda_sweep.m` 的 `cfg.q_coarse` 如果没同时覆盖 `cfg.protocol_q_grids` 会被忽略（因为 `protocol_q_grids_enabled=true`）——**必须在脚本里显式覆盖 per-protocol grids**
- `default_experiment_config('analysis')` 的默认非 S7 网格**只到 0.2**（q=0.2 是上界），所以不要只改 `cfg.q_coarse`
- resume=true 可断点续算

## 5. 当前时延结果摘要（M=1，最终版）

结果目录：`results_v2\lambda_sweep_20260814_060540_597e78800cf0`

| 协议 | λ=5 | λ=10 | λ=16 | λ=20 |
|------|------|------|------|------|
| sf_cf | 292 | 355 | 395 | 508 |
| sf_cb | 466 | 700 | 950 | 847 |
| sb_cf | 455 | 803 | 2713 | 2676 |
| sb_cb | 449 | 439 | 510 | 574 |
| s7_clean | 294 | 302 | 324 | 345 |
| s7_busy | 775 | 1001 | 1233 | 1319 |
| unslotted | 379 | 522 | 527 | 564 |

- sb_cb λ=5 用 5 种子补跑（CI 仍较宽 ±189µs）
- sf_cb λ=16 和 unslotted λ=16 用 3 种子补跑
- 所有完成率 = 1.0，G 范围 0.033~0.13，全部非饱和

## 6. 如何运行

```matlab
% === 时延 λ 扫描（M=1） ===
cd('C:\Users\Administrator\Documents\delay');
run_lambda_sweep();

% === 逻辑一：M=1:6 时延扫描 ===
run_analysis_1s();

% === 逻辑二：M 包请求队列 M=1:6 扫描 ===
run_analysis_1s_batch_m();

% === 饱和吞吐（M=1:6） ===
run_saturation_analysis_1s();

% === 并行池 ===
% 默认 4 个 worker，可在 default_experiment_config 或调用前设置：
% cfg.n_workers = 4;
```

或者从命令行：
```
cd C:\Users\Administrator\Documents\delay
"D:\Software\Matlab\bin\matlab.exe" -batch "run_lambda_sweep();"
```

## 7. 与理论对照的结论（M=1）

- SF-CF（时隙 ALOHA）实测接入时延比经典 Poisson 公式高 1.2-1.9 倍，差距来自有限总体（n=40）重传相关性——数值在同一量级，趋势合理
- SF-CB 容量减半（1/(2e)），λ=20 时负载 71%，解释 847µs > 508µs
- sb_cf 无 RTS → 冲突窗口 325µs（vs RTS 29µs）→ λ≥16 时最先劣化，符合理论
- s7_clean 接近物理延迟下限（~246µs），是所有协议中最好的
- unslotted ≈ sb_cb（RTS 保护消弭了监听的价值）
- 所有结果都在非饱和区，排队延迟 ≤ 20µs（sb_cf 除外）

## 8. 已知小问题
- sb_cb λ=5 延迟有宽 CI（±189µs，双峰），但不影响总体排序
- sf_cb λ=16(950) 略大于 λ=20(847)，在 CI 内重叠，属于种子噪声
- summary.csv 中 `Tp_us` 列在合并时可能显示 198（旧 bug 残留），不影响实际仿真
## 9. 扫描 M 的时延实验：`run_analysis_1s` / `run_analysis_1s_batch_m`

### 用途
对比不同 TXOP 预约逻辑在 M 扫描下的最优时延（非饱和，包长固定 = 1 conn_slot）。

### 参数（analysis profile 默认）
| 参数 | 值 |
|------|-----|
| λ | `[16, 30]` pkt/STA/s |
| M | `1:6` |
| load_mode | `'fixed_packet'` |
| 扫描协议 | `sf_cb, sb_cb, unslotted, s7_clean, s7_busy` |
| CF 基线 | `sf_cf, sb_cf` 固定 `M=1`，仅逻辑一 |

### 两种逻辑
- `txop_mode='ready_queue'`：队列有包即参与预约，成功发送最多 M 个包。
- `txop_mode='batch_M'`：每累计 M 个包形成一个预约请求，成功发送该请求对应的 M 个包；尾部不足 M 个包不生成请求。

### 流水线
1. 每个扫描条件使用分段粗扫、多候选盆地细扫和 3 种子候选验证。
2. best_q 使用 3 个独立评估种子。
3. 逻辑一运行 CF 基线 `M=1` 并合并；逻辑二不包含 CF。
4. 输出到 `results_v2/R9_merged_logic1/` 或 `results_v2/R9_merged_batch_M/`。

### 运行命令
```matlab
cd('C:\Users\Administrator\Documents\delay');
run_analysis_1s();          % 逻辑一
run_analysis_1s_batch_m();  % 逻辑二
```

### 时延曲线解读
- 横轴 M（TXOP 长度），纵轴平均端到端时延（µs），分两个子图（λ=16 和 λ=30），每条曲线一个协议
- CF 类固定 `M=1`，在图中显示为水平参考线，不再参与不公平的 M 扫描
- CB 类 + unslotted + s7 的 M 扫描有意义：一次预约成功可摊薄预约开销，时延一般随 M 下降
- 逻辑二的曲线额外包含“攒满 M 个包”产生的批次等待时延，因此不能直接与逻辑一按相同 M 直接比较

## 10. 饱和吞吐实验：`run_saturation_analysis_1s`

### 用途
对比各协议在**饱和**（节点队列永不为空）下的**最大归一化吞吐**

### 参数（analysis profile 默认）
| 参数 | 值 |
|------|-----|
| M | `1:6`（TXOP 长度，实际是指数扫描：`[0.1 0.2 0.4 0.6 1:6 8 10 15 20]`，但 `1:6` 是主范围） |
| 协议 | 全部 7 个 |
| 负载 | 饱和（每节点每 M×162.5µs 到达 1 包，队列永不空） |
| q | 协议专属粗网格 + 局部对数细化（7 精扫点）；SF-CF/SF-CB 用固定 q=1/N=0.025 |
| 种子 | 3 个独立 eval 种子 |
| 测量 | 0.2s 预热 + 1s 测量，无排空 |

### 吞吐指标
```
归一化吞吐 = payload_success_overlap_us / measure_us
```
即成功接收的有效载荷时间占总测量时间的比例，等价于"成功包数 / 总 conn-slot 数"。

### q 网格（analysis profile，协议专属）
- SF-CF/SF-CB：固定 `q = 1/n = 0.025`（经典 ALOHA 最优值）
- SB-CF：`[logspace(-5,-2,14), 1e-3, 3e-3, 1e-2]`
- SB-CB：类似
- unslotted：`[logspace(-5,log10(3e-2),15), 1e-3, 3e-3, 1e-2]`
- S7：各自专用网格

### 运行命令
```matlab
cd('C:\Users\Administrator\Documents\delay');
run_saturation_analysis_1s;
```

### 吞吐曲线解读
- 横轴 Tp = M×162.5µs（TXOP 长度），纵轴归一化吞吐（0~1）
- 7 条曲线（每协议一条），M 增大时 CB/unslotted/s7 的吞吐上升（聚合增益），CF 的吞吐基本不变
- 结果存在 `results_v2/saturation-<timestamp>/`

### 最新饱和结果
`results_v2/saturation-20260810_212454_4b69aebf1b98/` 中的结果已使用新时序（conn_slot=162.5µs 等）。

## 11. 已知饱和吞吐问题
- SF-CF 在 M>1 时 `Tp_us` 显示为 198（旧 bug 残留），不影响实际仿真（协议内部用的是 162.5µs）
- 可能需要用 `getfield(load(scenario.mat), 'MMW_REAL', 'CONN_OVERHEAD_US')` 确认当前 conn_slot

## 12. sf_cb_lightload_study 文件夹
- 该目录是旧版协议脚本（最初独立的重构尝试），后来协议逻辑已合并进 delay 目录的主模拟器
- **当前不再使用**，所有实验都在 delay 目录跑
- 如需参考，里面的 `plan.md` 记录了原始时序设计和协议描述
