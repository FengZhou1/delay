%RUN_ALL_ANALYSIS_V2 Run both current delay and saturation analyses.
%
% The two studies use separate configurations and result directories.  This
% script is intentionally explicit because running both complete matrices can
% take substantially longer than either one alone.

delay_cfg = default_experiment_config('analysis');
delay_experiment = run_experiment(delay_cfg);
delay_analysis = analyze_experiment_v2(delay_experiment.output_dir);

saturation_cfg = default_saturation_config('analysis');
saturation_experiment = run_saturation_experiment(saturation_cfg);

fprintf('\nBoth v2 analyses are complete.\n');
fprintf('Delay result directory: %s\n',delay_experiment.output_dir);
fprintf('Delay report: %s\n',delay_analysis.report_path);
fprintf('Saturation result directory: %s\n',saturation_experiment.output_dir);
fprintf('Saturation figure: %s\n',saturation_experiment.plot.png_path);
