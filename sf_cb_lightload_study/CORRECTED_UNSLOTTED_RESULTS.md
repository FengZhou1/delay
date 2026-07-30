# 修正后的 Unslotted SF-CB 轻载时延结果

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: execution
- Origin Date: 2026-07-30
- Verification Status: VERIFIED
- Version Label: corrected_unslotted_rts18_v1
- Corrected Result:
  `results/20260729_182732/corrected_unslotted_20260730_033919`
- Merged Result:
  `results/20260729_182732/corrected_unslotted_20260730_033919/merged_corrected`

## 修正的协议语义

旧实现错误地把完整198 us预约事务当成纯Aloha碰撞脆弱区间。当前有效实现
改为：

1. 不再等待198 us连接时隙边界；新HOL在其到达的9 us物理仿真边界立即
   开始RTS。
2. RTS持续18 us（2个毫米波slot）。只有两个或以上RTS发送区间重叠，
   才按经典碰撞模型全部失败；198 us不是RTS碰撞窗口。
3. 一个RTS仅在其完整18 us内AP始终空闲且没有其他RTS重叠时成功。成功后
   AP按照8个扇区依次发送CTS。
4. STA在扫描到本扇区时若正在发送RTS，则因半双工听不到CTS；否则按照
   `CTS_SINR_TH = 6 dB` 判断，成功解码后设置NAV。
5. 获胜STA定向发送DATA，AP定向接收；扫描期或DATA期的晚到RTS按实际
   干扰进入CTS或DATA SINR，DATA门限为 `21 dB`。
6. 新HOL第一次RTS必发；失败后的HOL才使用 `q`，在后续9 us物理边界
   进行Bernoulli重试。

因此，本实验中的“Unslotted”准确含义是“不受198 us连接边界约束”。
为了与其他协议共用完全相同的离散到达轨迹，时间分辨率仍是9 us；它不是
任意实数时刻的连续时间仿真。

## 验证

- 9/9个Unslotted专项确定性测试通过；
- 根目录31/31个全协议回归测试通过，默认SB-CB等协议行为未改变；
- 18/18个条件、90/90个正式run完成；
- 21762/21762个测量包完成，完成率均为1；
- 90/90个run通过稳定性、包守恒和终止积压为0的检查；
- 与匹配SB-CB保存结果的21762个包逐包核对，节点、到达时刻、run和
  packet id完全一致；
- `total_delay = queue_delay + access_delay` 最大误差为
  `2.27e-13 us`；
- 18/18个所选 `q` 通过独立验证、相邻稳定性和同步碰撞恢复压力测试；
- 原始调优均值的最小值没有任何一点落在扫描下界，因此未发现“最优q在
  范围外”的证据。

## 修正后的端到端时延

单位为ms：

| λ (pkt/STA/s) | M=1 | M=2 | M=3 | M=4 | M=5 | M=6 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0.402 | 0.608 | 0.826 | 1.035 | 1.235 | 1.448 |
| 3 | 0.415 | 0.634 | 0.857 | 1.096 | 1.354 | 1.656 |
| 5 | 0.435 | 0.662 | 0.914 | 1.181 | 1.509 | 1.813 |

修正后相对旧的错误Unslotted模型，18个点全部降低，降幅为
`10.6--186.0 us`。原因是旧模型把RTS之后的CTS扫描等时间错误地扩大成
碰撞窗口。

相对原始分时隙SF-CB，修正后的Unslotted在18/18个点均值更低；按三个
负载分别对六个M取平均，相对降幅为22.8%、21.6%和21.6%。

## 与匹配 SB-CB 的结论

- 18/18个点上，Unslotted的正式均值都低于SB-CB；
- SB-CB减Unslotted的平均差为45.1 us，逐点范围为14.1--112.9 us；
- 五个共享到达轨迹的run做配对95%置信区间后，10/18个点可区分为
  Unslotted更低，8/18个点仍无法稳定区分；
- 没有任何点的配对区间支持SB-CB更低。

这表明在当前轻载场景和当前物理模型下，取消198 us边界等待的收益通常
大于额外晚到RTS干扰的代价。不过8个未分辨点不能仅凭曲线上下顺序宣称
存在确定差异。

## 最优 q 的解释

正式 `best_q` 为：

| λ (pkt/STA/s) | M=1 | M=2 | M=3 | M=4 | M=5 | M=6 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | .025 | .025 | .005 | .005 | .005 | .0075 |
| 3 | .020 | .034375 | .0075 | .010 | .0075 | .005 |
| 5 | .020 | .020 | .020 | .020 | .015 | .015 |

这里的 `q` 只控制碰撞或CTS超时后的重试，新HOL第一次发送不受小 `q`
拖慢。轻载下绝大多数包只尝试一次，因此多个 `q` 的调优均值完全相同或
落在一个标准误内；此时选择较低重试概率，用于降低同步重试雪崩风险。
有4个所选点位于局部细扫的0.005下界，但这些点的原始均值最小值均位于
更高 `q`，所以不属于搜索范围截断。

## 可复现文件

- 合并条件结果：`merged_corrected/condition_summary_corrected_with_sb_cb.csv`
- 配对比较：`merged_corrected/corrected_unslotted_vs_sb_cb_paired.csv`
- q审计：`merged_corrected/corrected_unslotted_q_selection_audit.csv`
- 后验验证：`merged_corrected/verification/posthoc_verification.json`
- 四种SF-CB合并图：
  `merged_corrected/figures/sf_cb_lightload_delay_comparison.png`
- 加入匹配SB-CB的合并图：
  `merged_corrected/figures/sf_cb_lightload_delay_comparison_with_sb_cb.png`

## 统计谬误扫描（11/11）

1. 伪重复：以独立run配对，不把包当作独立实验重复；
2. 到达不公平：逐包验证相同到达轨迹；
3. 删失偏差：所有正式包均完成；
4. 不稳定点伪有限时延：所有run稳定且排空；
5. q选择泄漏：调优、验证和正式评估种子分离；
6. 搜索边界截断：原始均值最小值均不在下界；
7. 碰撞窗口偷换：明确区分18 us RTS和198 us完整事务；
8. 多重比较：报告18点探索性结果，不把未校正逐点检验当总体定论；
9. 均值排序冒充显著性：同时报告配对95%区间；
10. 小样本过度外推：明确8个点尚未分辨，且当前仅覆盖轻载；
11. 机制因果过度声明：结论限定于当前拓扑、门限、9 us分辨率和PHY模型。
