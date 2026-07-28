%RERUN_SB_CF_LAM5_M4  Re-search q for SB-CF (fixed_packet, lam5, M4) using
%the robustly-stable basin identified in prior tuning data.
%
% Prior rerun selected q=0.00085 (edge of stability cliff): 100% stable in
% 2-3 run tuning but only 40% stable in 5-run evaluation.  The coarse grid
% showed a wide stable basin at q=0.0003-0.0007 (100% stable, goodput~207,
% delay 33-137 ms).  This script restricts the grid to that basin, increases
% tuning/evaluation runs, and uses a 10-second measurement window.

base_dir = fullfile(pwd,'results_v2','20260728_183648_defa8d7220ff','combined_view');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_sb_cf_lam5_M4:MissingBaseSummary', ...
        'Combined summary not found: %s',base_summary_path);
end

condition_tags = {'sb_cf_fixed_packet_lam5_M4'};

cfg = default_experiment_config('analysis');
cfg.condition_filter = condition_tags;

% 10-second evaluation window; 5-second tuning.
cfg.warmup_us = 5e5;
cfg.measure_us = 10e6;
cfg.drain_max_us = 5e6;
cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
cfg.tune_warmup_us = 5e5;
cfg.tune_measure_us = 5e6;
cfg.tune_drain_max_us = 5e6;
cfg.tune_measure_max_us = 5e6;

% Skip validation; use tuning result directly.
cfg.n_eval_runs = 10;
cfg.q_validation_runs = 0;
cfg.q_validation_max_candidates = 5;
cfg.q_fine_tune_runs = 3;
cfg.q_coarse_tune_runs = 3;
cfg.q_fine_points = 9;
cfg.q_max_refinement_passes = 2;

cfg.q_preferred_neighbor_radius = 1;
cfg.q_require_stable_neighbors = true;
cfg.q_fallback_self_stable = true;

cfg.protocol_q_grids_enabled = true;

% SB-CF: restrict to the robustly-stable basin q=0.0003-0.000625.
% All these points were 100% stable (2/2) in prior coarse tuning with
% goodput~207 and finite delay.  The selection algorithm will pick the
% lowest-delay point that has stable neighbors on both sides.
cfg.protocol_q_grids.sb_cf = unique([ ...
    3e-4 3.5e-4 4e-4 4.5e-4 5e-4 5.5e-4 6e-4 6.25e-4]);

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;
cfg.condition_timeout_s = 3600;

fprintf('Base (combined) results: %s\n',base_dir);
fprintf('Conditions to rerun: %d\n',numel(condition_tags));
for i = 1:numel(condition_tags)
    fprintf('  %s\n',condition_tags{i});
end
fprintf(['Targeted rerun: warm-up=%.1f s, measure=%.1f s, drain<=%.1f s, ', ...
    'eval_runs=%d, validation_runs=%d\n'], ...
    cfg.warmup_us*1e-6,cfg.measure_us*1e-6, ...
    cfg.drain_max_us*1e-6,cfg.n_eval_runs,cfg.q_validation_runs);

experiment = run_experiment(cfg);
analyze_experiment_v2(experiment.output_dir);

merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nSB-CF rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined view dir: %s\n',merge_outputs.combined_dir);
