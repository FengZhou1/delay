%RERUN_NEAR_CRITICAL_RECOMMENDED Targeted validation of near-critical points.
%
% This run intentionally excludes the conditions already shown to be
% capacity-limited. It refines q only for the nine mixed-stability
% conditions and SF-CF/fixed_packet/lambda=15/M=3.
%
% Evaluation design:
%   0.5 s warm-up + 3 s measurement + up to 3 s drain
%   3 independent tuning seeds + 5 independent evaluation seeds
%   protocol-specific local q grids recommended after the 1-s analysis
%
% The previous complete result set is never overwritten. A combined_view
% directory is created under the new run and replaces only the ten selected
% rows/checkpoints.

base_dir = fullfile(pwd,'results_v2','20260723_200440_dae2255a7e44', ...
                    'combined_view');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_near_critical_recommended:MissingBaseSummary', ...
          'Base summary not found: %s',base_summary_path);
end

cfg = default_experiment_config('analysis');
cfg.condition_filter = { ...
    'sf_cf_fixed_packet_lam15_M2', ...
    'sf_cf_fixed_packet_lam15_M3', ...
    'sf_cb_fixed_packet_lam10_M3', ...
    'sf_cb_fixed_packet_lam10_M4', ...
    'sf_cb_fixed_packet_lam15_M4', ...
    'sb_cf_fixed_packet_lam10_M2', ...
    'sb_cf_fixed_payload_lam5_M6', ...
    'sb_cf_fixed_payload_lam15_M4', ...
    'sb_cb_fixed_payload_lam15_M1', ...
    's7_busy_fixed_packet_lam15_M3'};

cfg.warmup_us = 5e5;
cfg.measure_us = 3e6;
cfg.drain_max_us = 3e6;
cfg.tune_warmup_us = 5e5;
cfg.tune_measure_us = 3e6;
cfg.tune_drain_max_us = 3e6;
cfg.tune_measure_max_us = 3e6;
cfg.n_tune_runs = 3;
cfg.n_eval_runs = 5;

cfg.protocol_q_grids_enabled = true;
cfg.protocol_q_grids.sf_cf = ...
    [0.025 0.04 0.05 0.06 0.075 0.1 0.125 0.15 0.2];
cfg.protocol_q_grids.sf_cb = ...
    [0.025 0.05 0.075 0.1 0.15 0.2 0.3 0.4 0.5];
cfg.protocol_q_grids.sb_cf = ...
    [5e-4 7.5e-4 1e-3 1.25e-3 1.5e-3 1.75e-3 2e-3 ...
     2.5e-3 3e-3 5e-3 7.5e-3 1e-2 1.25e-2 1.5e-2 2e-2];
cfg.protocol_q_grids.sb_cb = [0.02 0.05 0.075 0.1];
cfg.protocol_q_grids.s7_clean = [0.05 0.075 0.1 0.15 0.2];
cfg.protocol_q_grids.s7_busy = [0.05 0.075 0.1 0.15 0.2];

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;

fprintf('Recommended near-critical rerun source: %s\n',base_dir);
fprintf('Selected conditions: %d\n',numel(cfg.condition_filter));
fprintf(['Tuning runs=%d, evaluation runs=%d, warm-up=%.3f s, ', ...
         'measurement=%.3f s, drain=%.3f s\n'], ...
    cfg.n_tune_runs,cfg.n_eval_runs,cfg.warmup_us*1e-6, ...
    cfg.measure_us*1e-6,cfg.drain_max_us*1e-6);

experiment = run_experiment(cfg);
rerun_analysis = analyze_experiment_v2(experiment.output_dir);
merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nRecommended near-critical rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined report: %s\n',merge_outputs.analysis.report_path);
