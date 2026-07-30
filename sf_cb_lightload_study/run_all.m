%RUN_ALL Execute the isolated SF-CB light-load MAC-variant study.

study_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(study_dir);
addpath(repo_root);
addpath(study_dir);

lightload_cfg = default_lightload_sfcb_config('analysis');
lightload_experiment = run_sfcb_lightload_study(lightload_cfg);

fprintf('\nSF-CB light-load study completed.\n');
fprintf('Result directory: %s\n',lightload_experiment.output_dir);
fprintf('Comparison figure: %s\n',lightload_experiment.figure.png_path);
