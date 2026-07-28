%RERUN_UNSTABLE_POINTS Recheck and fix q-selection issues in the latest delay results.
%
% Targets every condition in the latest delay result whose
% stable_fraction < 1.  Uses protocol-specific fine q-grids centered on
% the empirically observed stable basins, plus more validation and
% evaluation runs to avoid selecting borderline q values.
%
% The script never overwrites the source result.  After the rerun,
% merge_supplement_results replaces only the selected rows and
% checkpoints, and analyze_experiment_v2 regenerates the combined plots.

base_dir = fullfile(pwd,'results_v2','20260728_013738_004bf801fbbb');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_unstable_points:MissingBaseSummary', ...
        'Latest delay summary not found: %s',base_summary_path);
end

base_summary = readtable(base_summary_path,'VariableNamingRule','preserve');
unstable_mask = double(base_summary.stable_fraction) < 1-1e-12;
selected = base_summary(unstable_mask,:);

condition_tags = strings(height(selected),1);
for i = 1:height(selected)
    condition_tags(i) = sprintf('%s_%s_lam%g_M%d', ...
        char(string(selected.protocol(i))), ...
        char(string(selected.load_mode(i))), ...
        double(selected.lambda_base(i)),double(selected.M(i)));
end
condition_tags = unique(condition_tags,'stable');

cfg = default_experiment_config('analysis');
cfg.condition_filter = cellstr(condition_tags);

% Use a 2-second measurement window to reduce rate/slope noise.
cfg.warmup_us = 5e5;
cfg.measure_us = 2e6;
cfg.drain_max_us = 4e6;
cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
cfg.tune_warmup_us = 5e5;
cfg.tune_measure_us = 2e6;
cfg.tune_drain_max_us = 4e6;
cfg.tune_measure_max_us = 2e6;

% More validation and evaluation runs to catch borderline q values.
cfg.n_eval_runs = 5;
cfg.q_validation_runs = 5;
cfg.q_validation_max_candidates = 5;
cfg.q_fine_tune_runs = 3;
cfg.q_coarse_tune_runs = 2;
cfg.q_fine_points = 9;
cfg.q_max_refinement_passes = 3;

% Protocol-specific q-grids.  Each grid is densified in the empirically
% observed stable basin while keeping enough range to confirm the basin
% edges.  For protocols whose stable region is a narrow spike, extra
% points are added inside the spike.
cfg.protocol_q_grids_enabled = true;

% SF-CB: stable region varies widely with lambda/M.  Cover 0.001-1.0
% but concentrate points around the known stable basins.
cfg.protocol_q_grids.sf_cb = unique([ ...
    0.001 0.002 0.005 0.01 0.02 0.03 0.04 0.05 ...
    0.06 0.07 0.08 0.09 0.1 0.15 0.2 ...
    0.25 0.3 0.35 0.4 0.45 0.5 0.55 0.6 0.625 ...
    0.65 0.675 0.7 0.725 0.75 0.775 0.8 0.825 0.85 0.9 1.0]);

% SB-CB: stable region is very narrow at high load.  Concentrate around
% q=0.001-0.01 with extra resolution.
cfg.protocol_q_grids.sb_cb = unique([ ...
    1e-4 2e-4 3e-4 5e-4 7e-4 1e-3 1.2e-3 1.5e-3 ...
    2e-3 2.5e-3 3e-3 3.5e-3 4e-3 5e-3 6e-3 7e-3 ...
    8e-3 1e-2 1.5e-2 2e-2 5e-2 0.1 0.2 0.5 1]);

% SF-CF: slot length = Tp = M*198us, so very few slots per second.
% Stable q is small.  Concentrate around q=0.01-0.1.
cfg.protocol_q_grids.sf_cf = unique([ ...
    1e-4 5e-4 1e-3 2e-3 5e-3 ...
    0.01 0.015 0.02 0.025 0.03 0.035 0.04 0.045 0.05 ...
    0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 1]);

% SB-CF: uses basic 9us slots with DIFS/SIFS, so q is extremely small.
% The stable basin can be a single spike at q~0.0003-0.0008.
cfg.protocol_q_grids.sb_cf = unique([ ...
    1e-5 2e-5 3e-5 5e-5 7e-5 ...
    1e-4 1.5e-4 2e-4 3e-4 4e-4 5e-4 6e-4 7e-4 8e-4 ...
    1e-3 1.5e-3 2e-3 3e-3 5e-3 0.01 0.02 0.05 0.1 0.2 0.5 1]);

cfg.protocol_q_grids.s7_clean = unique([ ...
    0.001 0.002 0.005 0.01 0.02 0.03 0.04 0.05 ...
    0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 1]);

cfg.protocol_q_grids.s7_busy = unique([ ...
    0.001 0.002 0.005 0.01 0.02 0.03 0.04 0.05 ...
    0.06 0.07 0.08 0.09 0.1 0.15 0.2 0.3 0.5 1]);

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;
cfg.condition_timeout_s = 3600;

fprintf('Source results: %s\n',base_dir);
fprintf('Unstable conditions to rerun: %d\n',numel(condition_tags));
for i = 1:numel(condition_tags)
    fprintf('  %s\n',condition_tags(i));
end
fprintf(['Targeted rerun: warm-up=%.1f s, measure=%.1f s, drain<=%.1f s, ', ...
    'eval_runs=%d, validation_runs=%d\n'], ...
    cfg.warmup_us*1e-6,cfg.measure_us*1e-6, ...
    cfg.drain_max_us*1e-6,cfg.n_eval_runs,cfg.q_validation_runs);

experiment = run_experiment(cfg);
analyze_experiment_v2(experiment.output_dir);

merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nUnstable-point rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined view dir: %s\n',merge_outputs.combined_dir);
