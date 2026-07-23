%RUN_ANALYSIS_1S Run the six-protocol, two-load analysis profile.
%
% The default analysis profile uses:
%   0.2 s warm-up + 1 s measurement + up to 1 s drain
%   2 tuning seeds + 2 independent evaluation seeds
%   lambda_base = [5 10 15], M = 1:6, and all six protocols
%
% Results are written to a new versioned results_v2 directory. The legacy
% results directory and earlier results_v2 runs are not overwritten.

cfg = default_experiment_config('analysis');
experiment = run_experiment(cfg);
analysis_result = analyze_experiment_v2(experiment.output_dir);

fprintf('\nAnalysis complete.\n');
fprintf('Result directory: %s\n', experiment.output_dir);
fprintf('Chinese report: %s\n', analysis_result.report_path);
