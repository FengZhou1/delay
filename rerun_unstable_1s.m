%RERUN_UNSTABLE_1S Supplement the 1-s analysis with corrected q grids.
%
% Only conditions whose original stable_fraction was below one are rerun.
% Original results are never overwritten. A combined_view directory merges
% the original stable rows with every supplemental row for plotting.

base_dir = fullfile(pwd,'results_v2','20260723_160326_a80db2f32f0f');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_unstable_1s:MissingBaseSummary', ...
          'Base summary not found: %s',base_summary_path);
end

base_summary = readtable(base_summary_path,'VariableNamingRule','preserve');
rerun_mask = double(base_summary.stable_fraction) < 1-1e-12;
selected = base_summary(rerun_mask,:);
condition_tags = strings(height(selected),1);
for i = 1:height(selected)
    condition_tags(i) = sprintf('%s_%s_lam%g_M%d', ...
        char(string(selected.protocol(i))), ...
        char(string(selected.load_mode(i))), ...
        double(selected.lambda_base(i)),double(selected.M(i)));
end

cfg = default_experiment_config('analysis');
cfg.condition_filter = cellstr(condition_tags);
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;

fprintf('Supplemental rerun source: %s\n',base_dir);
fprintf('Selected non-stable conditions: %d\n',numel(cfg.condition_filter));
fprintf('Tuning runs=%d, evaluation runs=%d, measurement=%.3f s\n', ...
    cfg.n_tune_runs,cfg.n_eval_runs,cfg.measure_us*1e-6);

experiment = run_experiment(cfg);
rerun_analysis = analyze_experiment_v2(experiment.output_dir);
merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nSupplemental rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined report: %s\n',merge_outputs.analysis.report_path);
