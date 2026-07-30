%RUN_CORRECTED_UNSLOTTED Re-run only the corrected asynchronous SF-CB model.

study_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(study_dir);
addpath(repo_root);
addpath(study_dir);

cfg = default_lightload_sfcb_config('analysis');
cfg.variants = {'unslotted'};
cfg.lambda_values = [1 3 5];
cfg.M_values = 1:6;
cfg.resume = false;

base_result_dir = fullfile(study_dir,'results','20260729_182732');
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
cfg.output_dir = fullfile(base_result_dir, ...
    ['corrected_unslotted_' stamp]);

corrected_unslotted_experiment = run_sfcb_lightload_study(cfg);

fprintf('\nCorrected Unslotted study completed.\n');
fprintf('Result directory: %s\n', ...
    corrected_unslotted_experiment.output_dir);

