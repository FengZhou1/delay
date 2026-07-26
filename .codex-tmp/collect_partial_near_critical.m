repo_dir = fileparts(fileparts(mfilename('fullpath')));
run_dir = fullfile(repo_dir,'results_v2','20260726_181043_20f5418a8885');
checkpoint_dir = fullfile(run_dir,'checkpoints');
files = dir(fullfile(checkpoint_dir,'*.mat'));
rows = struct([]);
for i = 1:numel(files)
    saved = load(fullfile(files(i).folder,files(i).name),'condition');
    if isempty(rows)
        rows = saved.condition.row;
    else
        rows(end+1) = saved.condition.row; %#ok<SAGROW>
    end
end
partial_summary = struct2table(rows);
writetable(partial_summary,fullfile(run_dir,'partial_summary.csv'));
writetable(partial_summary,fullfile(run_dir,'summary.csv'));
fprintf('PARTIAL_SUMMARY_ROWS=%d\n',height(partial_summary));
