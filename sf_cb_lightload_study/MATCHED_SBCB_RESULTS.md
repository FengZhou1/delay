# SF-CB 轻载改进与匹配 SB-CB 对比

## Material Passport

- Origin Skill: academic-research-suite / experiment-agent
- Origin Mode: execution
- Origin Date: 2026-07-30
- Verification Status: VERIFIED
- Version Label: sfcb_lightload_matched_sbcb_v1
- Base SF-CB Result: `results/20260729_182732`
- Matched SB-CB Result: `results/20260729_182732/matched_sbcb_20260730_010511`

> 注意：本文件关于旧 `unslotted` 的判断已被修正后的18 us RTS碰撞模型
> 取代；请以 `CORRECTED_UNSLOTTED_RESULTS.md` 及其合并图为准。SB-CB、
> 原始SF-CB、Fast-first和Batch-clear数据不受影响。

## 对比条件

- 到达率：`lambda = [1 3 5] pkt/STA/s`
- 数据长度：`M = 1:6`，`Tp = 198*M us`
- 40 个 STA，所有协议逐条件复用完全相同的物理到达轨迹
- 每点 3 个调优 run、5 个独立验证 run、5 个正式评估 run
- SB-CB 使用当前根目录实现及其方向性 CTS/NAV、DATA/控制帧独立
  SINR 门限和经典 RTS 碰撞逻辑

## 完整性检查

- 18/18 个 SB-CB 条件完成；
- 90/90 个正式 run 完成率为 1、终止积压为 0，并通过包守恒；
- 21762/21762 个测量包完成；
- 15/15 条正式到达轨迹与原 SF-CB 保存结果逐包一致；
- 18/18 个所选 `q` 通过独立验证及 12 节点同步碰撞恢复压力测试；
- `total_delay = queue_delay + access_delay` 的最大数值误差为
  `4.55e-13 us`。

## 结论

- `fast_first` 是最值得保留的分时隙改进：改动小、所有点稳定，并显著
  降低原 SF-CB 时延。但它仍保留最长约 198 us、平均约 99 us 的边界相位
  等待，因此在多数点比可在 9 us 边界开始 DIFS/RTS 的 SB-CB 慢约
  30--55 us。
- `unslotted` 在 `lambda=1` 时与 SB-CB 基本处于同一水平；负载升高后，
  预约区间重叠的纯 Aloha 碰撞开始抵消取消边界等待的收益。
- `batch_clear` 在轻载下收益很小，因为建立连接时队列通常只有一个包；
  当前总时延几乎完全由接入时延决定。
- 在 `lambda=5, M=4:6`，`fast_first` 与 SB-CB 的均值差仅为数微秒到
  数十微秒，5 个配对 run 尚不足以稳定区分；不能仅凭曲线的上下顺序
  宣称其中一个机制必然更优。

## 最优 q 的含义

`best_q` 是扫描和独立验证得到的稳健工作点，不是解析闭式值：

1. 在 `[0.01, 0.025, 0.05, 0.1:0.1:0.9, 0.95, 0.975, 1]` 上粗扫；
2. 围绕粗扫最优区间增加 9 点局部细扫；
3. 要求候选自身及数值相邻 `q` 的完成率通过门槛；
4. 在均值差处于一个标准误或 1% 以内时，SB-CB 选择较低 `q`，避免靠近
   高概率碰撞悬崖；
5. 用 5 个独立到达种子验证，并通过 5 组 12 节点同步碰撞恢复压力测试；
6. 最后再用另外 5 个正式种子报告时延。

因此表中的 `best_q` 更准确地应称为“经验证的稳健低时延 q”。逐条件原始
调优最小值、最终选择值及保守代价记录在
`sb_cb_q_selection_audit.csv`。
