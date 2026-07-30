%RUN_MATCHED_SBCB Add a matched SB-CB experiment to the verified SF-CB study.

study_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(study_dir);
addpath(repo_root);
addpath(study_dir);

base_result_dir = fullfile(study_dir,'results','20260729_182732');
matched_sbcb_experiment = run_matched_sbcb_study(base_result_dir);

fprintf('\nMatched SB-CB study completed.\n');
fprintf('Result directory: %s\n',matched_sbcb_experiment.output_dir);
fprintf('Combined figure: %s\n',matched_sbcb_experiment.figure.png_path);
