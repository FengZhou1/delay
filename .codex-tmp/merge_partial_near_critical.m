repo_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_dir);
base_dir = fullfile(repo_dir,'results_v2', ...
    '20260723_200440_dae2255a7e44','combined_view');
rerun_dir = fullfile(repo_dir,'results_v2', ...
    '20260726_181043_20f5418a8885');

base_summary = readtable(fullfile(base_dir,'summary.csv'), ...
    'VariableNamingRule','preserve');
rerun_summary = readtable(fullfile(rerun_dir,'summary.csv'), ...
    'VariableNamingRule','preserve');
if ~ismember('result_source',rerun_summary.Properties.VariableNames)
    rerun_summary.result_source = repmat("partial_near_critical", ...
        height(rerun_summary),1);
end
if ~ismember('rerun_replaced',rerun_summary.Properties.VariableNames)
    rerun_summary.rerun_replaced = true(height(rerun_summary),1);
end
rerun_summary = rerun_summary(:,base_summary.Properties.VariableNames);
writetable(rerun_summary,fullfile(rerun_dir,'summary.csv'));

merge_outputs = merge_supplement_results(base_dir,rerun_dir);
save(fullfile(rerun_dir,'partial_merge_outputs.mat'),'merge_outputs');

fprintf('COMBINED_DIR=%s\n',merge_outputs.combined_dir);
fprintf('COMBINED_SUMMARY=%s\n',merge_outputs.combined_summary_path);
fprintf('COMBINED_REPORT=%s\n',merge_outputs.analysis.report_path);
