% run_refined_4.m - Re-run 4 protocols with refined q grids, then merge
function run_refined_4()
    cfg = default_experiment_config('analysis');
    cfg.protocols = {'sb_cf', 'sf_cb', 'sf_cf', 'unslotted'};
    cfg.run_preflight_tests = false;  % skip tests for speed
    
    % Run experiment
    experiment = run_experiment(cfg);
    
    % Merge with previous run
    old_dir = 'C:\Users\Administrator\Documents\delay\results_v2\20260810_134843_845e2c30c0db';
    new_dir = experiment.manifest.output_dir;
    
    % Read old summary
    old_summary = readtable(fullfile(old_dir, 'summary.csv'));
    new_summary = readtable(fullfile(new_dir, 'summary.csv'));
    
    % Remove the 4 protocols from old summary
    keep_mask = ~ismember(old_summary.protocol, {'sb_cf', 'sf_cb', 'sf_cf', 'unslotted'});
    merged = [old_summary(keep_mask, :); new_summary];
    
    % Sort
    [~, order] = sortrows(merged, {'protocol', 'lambda_effective', 'M'});
    merged = merged(order, :);
    
    % Write merged summary
    merged_dir = fullfile(new_dir, 'merged');
    if ~isfolder(merged_dir), mkdir(merged_dir); end
    writetable(merged, fullfile(merged_dir, 'summary.csv'));
    save(fullfile(merged_dir, 'config.mat'), 'cfg');
    
    % Generate delay plot
    gen_delay_plots(merged, merged_dir);
    
    fprintf('Merged results saved to %s\n', merged_dir);
    fprintf('Delay plot saved to %s\n', fullfile(merged_dir, 'figures'));
end

run_refined_4();
