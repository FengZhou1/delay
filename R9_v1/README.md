# R9_v1 归档

本文件夹收拢 R9 版本（`0819_R9_results`）的结果、原始实验输出、运行日志和运行脚本，不再参与 R10 主目录运行。

## 目录

- `results/`：正式合并结果（原 `0819_R9_results/`）
- `raw_results/`：每次实验的原始输出与 checkpoint（原 `results_v2/`）
- `logs/`：运行日志（原 `run_logs/`）
- `scripts/`：R9 专用入口/绘图/补跑脚本，含 `run_0819_R9.m`
- `scripts/archive_scripts/`：一次性补跑/旧入口/rerun/merge 脚本

## 说明

- 根目录保留 `run_experiment.m`、`simulate_*.m`、`default_experiment_config.m` 等核心库供 R10 使用。
- 若要在归档中重新运行 R9 脚本，需要把 delay 根目录加入 MATLAB 路径，因为核心库没有复制进本文件夹。
- 饱和吞吐运行脚本已独立放在 `saturation_throughput/`，delay 根目录不再保留饱和运行脚本。
