%RERUN_LATEST_DELAY_PROBLEM_POINTS Recheck the latest delay anomalies.
%
% Scope:
%   1) every condition in the latest delay result whose stable_fraction < 1;
%   2) SF-CF and SB-CF at M=1 under fixed-packet load, to verify the
%      user-reported ordering without rerunning the duplicated M=1
%      fixed-payload conditions.
%
% This is a supplemental run.  It never overwrites the source result.
% The final combined_view replaces only the selected rows and checkpoints.

base_dir = fullfile(pwd,'results_v2','20260727_171921_656dc48da53d');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_latest_delay_problem_points:MissingBaseSummary', ...
        'Latest delay summary not found: %s',base_summary_path);
end

base_summary = readtable(base_summary_path,'VariableNamingRule','preserve');
fprintf('Current latest M=1 fixed-packet ordering (mean delay, us):\n');
for lambda_base = unique(double(base_summary.lambda_base)).'
    sf = base_summary(string(base_summary.protocol)=="sf_cf" & ...
        string(base_summary.load_mode)=="fixed_packet" & ...
        double(base_summary.lambda_base)==lambda_base & ...
        double(base_summary.M)==1,:);
    sb = base_summary(string(base_summary.protocol)=="sb_cf" & ...
        string(base_summary.load_mode)=="fixed_packet" & ...
        double(base_summary.lambda_base)==lambda_base & ...
        double(base_summary.M)==1,:);
    if height(sf)==1 && height(sb)==1
        fprintf('  lambda=%g: SF-CF %.3f, SB-CF %.3f, SB-SF %.3f\n', ...
            lambda_base,double(sf.mean_delay_us),double(sb.mean_delay_us), ...
            double(sb.mean_delay_us)-double(sf.mean_delay_us));
    end
end
unstable_mask = double(base_summary.stable_fraction) < 1-1e-12;
m1_check_mask = double(base_summary.M)==1 & ...
    string(base_summary.load_mode)=="fixed_packet" & ...
    ismember(string(base_summary.protocol),["sf_cf","sb_cf"]);
selected_mask = unstable_mask | m1_check_mask;
selected = base_summary(selected_mask,:);

condition_tags = strings(height(selected),1);
for i = 1:height(selected)
    condition_tags(i) = sprintf('%s_%s_lam%g_M%d', ...
        char(string(selected.protocol(i))), ...
        char(string(selected.load_mode(i))), ...
        double(selected.lambda_base(i)),double(selected.M(i)));
end

% Rebuild the reason vector using condition tags so it remains correct if
% table row order changes in a future result schema.
unstable_tags = strings(nnz(unstable_mask),1);
unstable_rows = base_summary(unstable_mask,:);
for i = 1:height(unstable_rows)
    unstable_tags(i) = sprintf('%s_%s_lam%g_M%d', ...
        char(string(unstable_rows.protocol(i))), ...
        char(string(unstable_rows.load_mode(i))), ...
        double(unstable_rows.lambda_base(i)),double(unstable_rows.M(i)));
end
condition_tags = unique(condition_tags,'stable');
reason = repmat("M1_ordering_check",numel(condition_tags),1);
reason(ismember(condition_tags,unstable_tags)) = "non_fully_stable";

cfg = default_experiment_config('analysis');
cfg.condition_filter = cellstr(condition_tags);

% A two-second targeted window is long enough to reduce the one-second
% rate/slope noise while remaining far cheaper than rerunning all 216
% conditions at the publication-scale ten-second setting.
cfg.warmup_us = 5e5;
cfg.measure_us = 2e6;
cfg.drain_max_us = 4e6;
cfg.tune_warmup_us = 5e5;
cfg.tune_measure_us = 2e6;
cfg.tune_drain_max_us = 4e6;
cfg.tune_measure_max_us = 2e6;
cfg.n_eval_runs = 5;
cfg.q_fine_tune_runs = 3;
cfg.q_fine_points = 7;
cfg.q_max_refinement_passes = 2;

% Expand only the outer bounds and let the two local refinement passes
% supply fine resolution.  The latest audit showed that the empirical
% goodput maxima were internal, so a very large uniform grid is unnecessary.
cfg.protocol_q_grids.sf_cf = ...
    [0.0025 0.005 0.01 0.025 0.05 0.1 0.2 0.5 1];
cfg.protocol_q_grids.sf_cb = ...
    [0.0025 0.005 0.01 0.025 0.05 0.1 0.2 0.5 1];
cfg.protocol_q_grids.sb_cf = ...
    [1e-5 2e-5 5e-5 1e-4 2e-4 5e-4 1e-3 2e-3 ...
     5e-3 1e-2 2e-2 5e-2];
cfg.protocol_q_grids.sb_cb = ...
    [2.5e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 5e-2 0.1 0.2 0.5];
cfg.protocol_q_grids.s7_clean = ...
    [0.0025 0.005 0.01 0.025 0.05 0.1 0.2 0.5 1];
cfg.protocol_q_grids.s7_busy = ...
    [0.0025 0.005 0.01 0.025 0.05 0.1 0.2 0.5 1];

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;
cfg.condition_timeout_s = 3600;

fprintf('Latest delay source: %s\n',base_dir);
fprintf('Selected conditions: %d (%d non-fully-stable + M=1 checks)\n', ...
    numel(condition_tags),nnz(unstable_mask));
fprintf(['Targeted validation: warm-up=%.1f s, measure=%.1f s, ', ...
    'drain<=%.1f s, evaluation runs=%d\n'], ...
    cfg.warmup_us*1e-6,cfg.measure_us*1e-6, ...
    cfg.drain_max_us*1e-6,cfg.n_eval_runs);

experiment = run_experiment(cfg);

selection_manifest = table(condition_tags,reason);
writetable(selection_manifest,fullfile(experiment.output_dir, ...
    'problem_point_selection.csv'));
analyze_experiment_v2(experiment.output_dir);
merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nTargeted delay rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined delay figure: %s\n',fullfile( ...
    merge_outputs.combined_dir,'figures','delay_by_M_with_unstable.png'));
