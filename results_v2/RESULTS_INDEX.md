# results_v2 结果索引

## 当前推荐结果

### `20260723_145527_b2bf4af3385d`

- 状态：`completed`，Material Passport：`VERIFIED / exp_result_v2`。
- 档位：`analysis` 相对完整主矩阵，不是论文正式统计结果。
- 覆盖：216 个主条件（六协议、`lambda=[5,15,30]`、`M=1:6`、两种负载口径），每点2个调优种子和2个独立评估种子。
- 配置：20 ms warm-up、100 ms测量、100 ms排空；按聚合负载选择轻/中/重三组q网格，低到达率调优最多延长到200 ms。
- 运行时间：1285.982 s（21.4分钟）。
- 自动预检：24/24确定性/配置测试通过；受控`K=40,q=1/40` Aloha概率门通过，服务周期相对误差0.885%。
- 自动严格验收：117个条件通过、19个失败、80个不适用；严格5%门仍比analysis档位自身25%工程稳定门更苛刻。
- 入口文件：`中文理论-仿真报告.md`、`summary.csv`、`acceptance_checks.csv`、`csma_diagnostics.csv`和`figures/`。
- 限定：独立评估样本仍只有2个，不重复CCA/拓扑消融，不能替代`full`的10秒、10种子结论。

### 配套物理诊断：`20260723_015251_ddb4c80f0c57`

- `scaled`单种子工程验证，包含同一六协议主轴、42个CCA/灵敏度消融和48个拓扑复核条件。
- 用于解释监听漏检、晚启动、CTS/NAV和拓扑敏感性；主性能比较优先使用上面的`analysis`目录。

## 独立验证与专项诊断

- `verification_20260723_0118/`：持久化的 22/22 回归报告与受控 Aloha 理论校验。
- `legacy_M01_20260723_001345/`：仅解释历史 `M=0.1` 下 SB-CF 时延低于 SF-CF 的来源，不进入正式 `M=1:6` 扫描。
- `aloha_theory_20260723_001501/`：较早的同类受控 Aloha 校验；当前推荐结果目录中的 `verification/aloha_controlled/` 是最终随实验固化的版本。

## 不作为结论使用的目录

- `20260723_013931_404d4077fa1a/`：性能诊断时主动中止，只含 63/216 个主检查点；manifest 已标记 `aborted`。
- `20260723_143315_f70422ace551/`：首次analysis运行在SB-CF空区间边界触发错误后停止；manifest已标记`crashed`，修复后新增回归并由最终目录取代。
- `20260723_143650_deced9dcc8b1/`：固定低q网格的完整analysis先导结果，已由负载自适应q版本取代。
- `20260723_143619_*`、`20260723_145304_*`、`20260723_145357_*`：空区间修复或自适应q选择的最小集成验证。
- `integration_runner*`、`integration_extended/`：开发期接口与分析器集成测试，不是实验结果。
- 原有 `results/`：历史实现结果，未被 v2 覆盖或修改。

## Material Passport

- Origin Skill: experiment-agent
- Origin Mode: run/validate
- Origin Date: 2026-07-22
- Verification Status: VERIFIED（仅指代码预检与受控理论门；`analysis`统计限定见上文）
- Version Label: exp_result_v2

## 2026-07-24：1 秒 analysis 非稳定条件修正补跑

### 当前推荐的 1 秒工程分析视图

- 基础结果：`20260723_160326_a80db2f32f0f/`，216 条，原始统计为
  141 stable、16 mixed、59 unstable。
- 补跑结果：`20260723_200440_dae2255a7e44/`，只重跑基础结果中
  `stable_fraction<1` 的 75 条。
- 推荐读取：
  `20260723_200440_dae2255a7e44/combined_view/`。其中保留原来 141 条
  stable 结果，并用修正 q 网格的 75 条补跑结果替换对应行和 checkpoint；
  合计仍为 216 条。
- 修正后的统计：196 stable、9 mixed、11 unstable。75 条补跑中有 55 条
  恢复为 stable；无可用 `best_q` 的条件从 40 条降为 10 条。
- 分口径统计：
  fixed-packet 为 91 stable、6 mixed、11 unstable；
  fixed-payload 为 105 stable、3 mixed、0 unstable。
- 主要修正：SF/S7 使用按 190 us 竞争边界设计的 q 网格；SB-CF 使用
  `1e-4:...:1e-2` 量级网格；SB-CB 使用 `5e-4:...:0.2` 网格；禁止
  `q=1`。所有补跑仍使用 0.2 s warm-up、1 s 测量、1 s 排空、
  3 个调优种子和 2 个独立评估种子。
- 运行时间：75 条补跑 14171.3 s。`SB-CB/fixed_packet/lambda=15/M=2`
  超过 1800 s 慢点标记但成功完成；该标记是墙钟性能诊断，不是协议时延。
- 后处理曾因 CSV cell/string 类型不一致在表替换处退出；75 个 checkpoint
  均已成功保存。修复后只重跑合并和绘图，未重跑仿真。最终 combined_view
  含 216 个 checkpoint，后处理 stderr 为空。
- 回归验证：MATLAB R2023b，`run_v2_tests` 24/24 通过。
- 限定：这是 1 秒 engineering analysis，不是正式论文结果。
  `stable` 使用 25% 速率差、10% 删失的 analysis 门且要求 2/2 评估
  run 稳定；严格 5% 速率/Little 复核为 186 pass、10 fail、
  20 not_applicable。最终论文结论仍需更长窗口和更多独立种子。
- 详细新旧对比与剩余点解释：
  `20260723_200440_dae2255a7e44/补跑稳定性对比.md`。

### 本次补跑的 Material Passport

- Origin Skill: experiment-agent
- Origin Mode: run/validate
- Origin Date: 2026-07-23
- Verification Status: VERIFIED_FOR_1S_ENGINEERING_ANALYSIS
- Version Label: analysis_1s_corrected_q_supplement_v1
