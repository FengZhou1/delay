%RUN_ANALYSIS_1S Run the six-protocol, two-load analysis profile.
%
% The default analysis profile uses:
%   0.2 s warm-up + 1 s measurement + up to 1 s drain
%   two-seed, protocol-specific global coarse q coverage
%   three-seed nine-point local refinement over two coarse neighbors
%   a preferred five-consecutive-q stable basin (two neighbors per side)
%   up to two local refinement passes
%   two independent q-validation seeds with ranked-candidate fallback
%   3 final independent evaluation seeds
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
