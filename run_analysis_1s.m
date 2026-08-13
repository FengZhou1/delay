%%RUN_ANALYSIS_1S Full automated delay analysis pipeline.
%%
%% Pipeline:
%%   1. tune + eval (with completion-rate fallback)
%%   2. Auto-detect boundary-hit q values
%%   3. Boundary supplement (3 seeds, 3 tune, stable-only, left-fallback eval)
%%   4. Merge supplement results -> R9_merged
%%   5. Final delay plots
%%
%% Results: results_v2/<timestamp>/  (raw experiment)
%%          results_v2/R9_merged/    (final merged results + figures)

cfg = default_experiment_config('analysis');
cfg.protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
cfg.run_preflight_tests = false;
cfg.resume = false;  % force fresh run, no resume from old configs

%% Step 1: Main experiment (tune + eval)
fprintf('========================================\n');
fprintf('  STEP 1: Main experiment (tune + eval)\n');
fprintf('========================================\n');
experiment = run_experiment(cfg);
r9_dir = experiment.output_dir;
fprintf('Main experiment done: %s\n', r9_dir);

%% Step 2: Auto-detect boundary-hit q and run supplement
fprintf('\n========================================\n');
fprintf('  STEP 2: Boundary-q supplement scan\n');
fprintf('========================================\n');

% Load summary to detect boundary hits
summary = readtable(fullfile(r9_dir, 'summary.csv'), 'VariableNamingRule', 'preserve');
hit_rows = [];
for ri = 1:height(summary)
    proto = char(summary.protocol(ri));
    if ~isfield(cfg.protocol_q_grids, proto), continue; end
    grid = double(cfg.protocol_q_grids.(proto));
    bq = double(summary.best_q(ri));
    if ~isfinite(bq), continue; end
    if abs(bq - max(grid)) <= 1e-9 || abs(bq - min(grid)) <= 1e-9
        hit_rows(end+1) = ri; %#ok<AGROW>
    end
end

if isempty(hit_rows)
    fprintf('No boundary-hit q detected. Skipping supplement.\n');
    % Still copy results to R9_merged for final plots
    out_dir = fullfile('results_v2', 'R9_merged');
    if ~isfolder(out_dir), mkdir(out_dir); end
    copyfile(fullfile(r9_dir, 'summary.csv'), fullfile(out_dir, 'summary.csv'), 'f');
    copyfile(fullfile(r9_dir, 'config.mat'), fullfile(out_dir, 'config.mat'), 'f');
    if isfile(fullfile(r9_dir, 'scenario.mat'))
        copyfile(fullfile(r9_dir, 'scenario.mat'), fullfile(out_dir, 'scenario.mat'), 'f');
    end
else
    fprintf('Found %d boundary-hit conditions:\n', numel(hit_rows));
    for hi = 1:numel(hit_rows)
        ri = hit_rows(hi);
        fprintf('  %s lam=%g M=%d q=%.4g\n', ...
            char(summary.protocol(ri)), double(summary.lambda_base(ri)), ...
            double(summary.M(ri)), double(summary.best_q(ri)));
    end
    
    %% Step 3: Run boundary supplement
    fprintf('\n========================================\n');
    fprintf('  STEP 3: Running boundary supplement\n');
    fprintf('========================================\n');
    
    out_dir = fullfile('results_v2', 'R9_merged');
    sup_info = run_boundary_q_supplement(r9_dir, out_dir, {}, false, 1);
    
    %% Step 4: Merge results
    fprintf('\n========================================\n');
    fprintf('  STEP 4: Merging results -> R9_merged\n');
    fprintf('========================================\n');
    
    merged = merge_r9_boundary(r9_dir, out_dir);
end

%% Step 5: Analysis report
fprintf('\n========================================\n');
fprintf('  STEP 5: Analysis report\n');
fprintf('========================================\n');
analysis_result = analyze_experiment_v2(r9_dir);

fprintf('\n========================================\n');
fprintf('  PIPELINE COMPLETE\n');
fprintf('========================================\n');
fprintf('Raw experiment: %s\n', r9_dir);
fprintf('Final merged:   %s\n', fullfile('results_v2', 'R9_merged'));
fprintf('Report:         %s\n', analysis_result.report_path);
