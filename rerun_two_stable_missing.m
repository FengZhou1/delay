%RERUN_TWO_STABLE_MISSING  Re-search q for SF-CB (lam5, M2) and SB-CF (lam5, M4).
% Both conditions are theoretically stable.  SB-CF previously achieved 9/10
% stable at q=0.000625 but had NaN mean delay.  This script uses a more
% conservative q-basin (0.0003-0.00055) that was 100% stable in prior
% tuning, and re-confirms SF-CB with 10 eval runs.

base_dir = fullfile(pwd,'results_v2','20260728_185248_f7f295593299','combined_view');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_two_stable_missing:MissingBaseSummary', ...
        'Combined summary not found: %s',base_summary_path);
end

condition_tags = {'sf_cb_fixed_packet_lam5_M2', ...
                  'sb_cf_fixed_packet_lam5_M4'};

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

% Skip validation; use tuning result directly (borderline-stable conditions).
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

% SF-CB: known stable basin 0.68-0.78.  Dense grid with 0.005 steps.
cfg.protocol_q_grids.sf_cb = unique([ ...
    0.5 0.55 0.6 0.63 0.65 0.66 0.67 0.68 0.685 0.69 0.695 ...
    0.7 0.705 0.71 0.715 0.72 0.725 0.73 0.735 0.74 0.745 ...
    0.75 0.755 0.76 0.765 0.77 0.775 0.78 0.785 0.79 0.8 ...
    0.85 0.9 1.0]);

% SB-CF: use conservative basin 0.0003-0.00055 (100% stable in prior
% coarse tuning, goodput~207, delay 33-137 ms).  q=0.000625 gave 9/10
% stable at the edge of the cliff, so stay below it.
cfg.protocol_q_grids.sb_cf = unique([ ...
    1e-5 5e-5 1e-4 1.5e-4 2e-4 2.5e-4 3e-4 3.25e-4 3.5e-4 ...
    3.75e-4 4e-4 4.25e-4 4.5e-4 4.75e-4 5e-4 5.25e-4 5.5e-4 ...
    5.75e-4 6e-4 6.5e-4 7e-4 7.5e-4 8e-4 9e-4 1e-3]);

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

fprintf('\nTwo-point rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined view dir: %s\n',merge_outputs.combined_dir);
