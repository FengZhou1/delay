%RERUN_SB_CB_LAM10_M4_SPIKE Re-evaluate the SB-CB delay spike robustly.
%
% Target:
%   protocol=SB-CB, load=fixed_packet, lambda_base=10, M=4
%
% The old 1-s result selected q=0.1 and was labelled stable even though one
% evaluation seed entered a congestion avalanche. This targeted rerun uses
% a finer low-q grid, strict stability gates, a longer evaluation window,
% and independent evaluation seeds. The result is merged into a new copy of
% the current complete result set; the existing combined_view is unchanged.

base_dir = fullfile(pwd,'results_v2','20260726_181043_20f5418a8885', ...
                    'combined_view');
if ~isfile(fullfile(base_dir,'summary.csv'))
    error('rerun_sb_cb_lam10_M4_spike:MissingBase', ...
          'Base combined summary not found: %s',base_dir);
end

cfg = default_experiment_config('analysis');
cfg.protocols = {'sb_cb'};
cfg.load_modes = {'fixed_packet'};
cfg.lambda_values = 10;
cfg.M_values = 4;
cfg.condition_filter = {'sb_cb_fixed_packet_lam10_M4'};

cfg.warmup_us = 5e5;
cfg.measure_us = 3e6;
cfg.drain_max_us = 3e6;
cfg.n_eval_runs = 5;

cfg.tune_warmup_us = 5e5;
cfg.tune_measure_us = 2e6;
cfg.tune_drain_max_us = 15e5;
cfg.tune_measure_max_us = 2e6;
cfg.tune_min_expected_arrivals = 0;
cfg.n_tune_runs = 3;
cfg.tuning_rate_screen = true;

cfg.protocol_q_grids_enabled = true;
cfg.protocol_q_grids.sb_cb = ...
    [0.005 0.0075 0.01 0.0125 0.015 0.02 0.025 0.03 ...
     0.04 0.05 0.075 0.1];
cfg.q_refine_points = 0;

cfg.stability_rate_tolerance = 0.05;
cfg.stability_censor_tolerance = 0.01;
cfg.stability_slope_fraction = 0.05;
cfg.stability_require_slope = true;

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;
cfg.condition_timeout_s = 5400;

fprintf('SB-CB spike rerun base: %s\n',base_dir);
fprintf(['q grid: %s\nTune: %d seeds, %.2f s measure. ', ...
         'Eval: %d seeds, %.2f s measure.\n'], ...
    mat2str(cfg.protocol_q_grids.sb_cb),cfg.n_tune_runs, ...
    cfg.tune_measure_us*1e-6,cfg.n_eval_runs,cfg.measure_us*1e-6);

experiment = run_experiment(cfg);
merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nSB-CB spike rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined delay plot: %s\n',fullfile( ...
    merge_outputs.combined_dir,'figures','delay_by_M.png'));
