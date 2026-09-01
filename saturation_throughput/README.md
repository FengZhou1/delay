# saturation_throughput

本文件夹是从 git 提交 `e3efa57`（2026-08-10）单独抽出的**旧版饱和吞吐运行代码**：

- 逻辑：一次 TXOP 只发 1 个包，M 表示 DATA 长度 / TXOP 长度，不改变每成功完成包数。
- 场景：40 节点、8 扇区、定向天线 MLO；0.2 s warm-up + 1 s 测量；7 个协议。
- M 扫描：`[0.1 0.2 0.4 0.6 1:6 8 10 15 20]`，与
  `results/20260810_212454_4b69aebf1b98` 完全对应。
- 运行入口：`run_saturation_analysis_1s.m`。
- 结果文件由你自己放入本文件夹 `results/` 下，代码本身不包含结果。

## 运行

```matlab
cd('C:\Users\Administrator\Documents\delay\saturation_throughput');
run_saturation_analysis_1s;           % analysis，完整重跑
```

结果写入本文件夹 `results/` 下的新时间戳目录。这个文件夹可以整体移到
任意位置，脚本内部没有写死的绝对路径，输出也全部基于当前工作目录。

## 版本说明

`results/20260810_212454_4b69aebf1b98` 对应的源码是 2026-08-10 当晚的未提交
工作树，git 历史中没有 config hash 完全一致的提交。`e3efa57` 是逻辑最接近的
可用版本（同样是一次 TXOP 一个包）。因此如果直接把旧结果目录放回来并用本代码
`resume`，可能会因 config hash 不一致被拒绝；直接重新跑会生成新的结果目录。

## 与当前 delay 主目录的区别

- 主目录当前时延/饱和代码已经改为 ready-queue / batch_M 的“一次 TXOP 发最多 M 个包”逻辑。
- 本文件夹保留的是 2026-08-10 之前“一次 TXOP 一个包”的饱和吞吐逻辑，可独立运行，
  不受主目录后续修改影响。
