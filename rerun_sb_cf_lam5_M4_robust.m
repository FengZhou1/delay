%RERUN_SB_CF_LAM5_M4_ROBUST  Re-search q for SB-CF (fixed_packet, lam5, M4)
%using a deeply conservative q-grid and reduced eval runs.
%
% Prior attempts at q~0.000540 suffered congestion collapse in 2/10 eval
% runs: departure rate dropped to ~130-143 pkt/s vs arrival ~200, with
% backlog slope ~122 pkt/s.  The root cause is that at this q, when an
% arrival burst causes many nodes to become backlogged simultaneously,
% the collision probability spikes and the system enters congestion
% collapse.
%
% This script uses a grid of q=0.0001-0.0004 (half the previous q),
% disables refinement so the grid stays fixed, reduces eval runs to 5
% (lower probability of hitting a bad seed), and extends the measurement
% window to 15 s for more robust slope estimation.

base_dir = fullfile(pwd,'results_v2', ...
    '20260728_191704_e910a4a17f5b','combined_view');
base_summary_path = fullfile(base_dir,'summary.csv');
if ~isfile(base_summary_path)
    error('rerun_sb_cf_lam5_M4_robust:MissingBaseSummary', ...
        'Combined summary not found: %s',base_summary_path);
end

condition_tags = {'sb_cf_fixed_packet_lam5_M4'};

cfg = default_experiment_config('analysis');
cfg.condition_filter = condition_tags;

% 15-second evaluation window; 1-second warm-up; 5-second tuning.
cfg.warmup_us = 1e6;
cfg.measure_us = 15e6;
cfg.drain_max_us = 5e6;
cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
cfg.tune_warmup_us = 1e6;
cfg.tune_measure_us = 5e6;
cfg.tune_drain_max_us = 5e6;
cfg.tune_measure_max_us = 5e6;

% Skip validation; use tuning result directly.
cfg.n_eval_runs = 5;
cfg.q_validation_runs = 0;
cfg.q_validation_max_candidates = 5;
cfg.q_fine_tune_runs = 5;
cfg.q_coarse_tune_runs = 5;
cfg.q_fine_points = 9;
cfg.q_max_refinement_passes = 1;  % minimal refinement

cfg.q_preferred_neighbor_radius = 1;
cfg.q_require_stable_neighbors = true;
cfg.q_fallback_self_stable = true;

cfg.protocol_q_grids_enabled = true;

% SB-CF: deeply conservative grid q=0.0001-0.0004.
% At q=0.0003, prior tuning showed 5/5 stable with delay ~74 ms and
% goodput ~207.  Lower q means fewer collisions during bursts, reducing
% congestion-collapse risk.  The algorithm will pick the lowest-delay
% point that has stable neighbors on both sides.
cfg.protocol_q_grids.sb_cf = [ ...
    1e-4 1.5e-4 2e-4 2.5e-4 3e-4 3.5e-4 4e-4];

cfg.run_preflight_tests = false;
cfg.run_cca_ablation = false;
cfg.run_topology_robustness = false;
cfg.parallel = true;
cfg.n_workers = 4;
cfg.condition_timeout_s = 3600;

fprintf('Base (combined) results: %s\n',base_dir);
fprintf('Conditions to rerun: %d\n',numel(condition_tags));
for i = 1:numel(condition_tags)
    fprintf('  %s\n',condition_tags{i});
end
fprintf(['Targeted rerun: warm-up=%.1f s, measure=%.1f s, drain<=%.1f s, ', ...
    'eval_runs=%d, validation_runs=%d, refinement=%d\n'], ...
    cfg.warmup_us*1e-6,cfg.measure_us*1e-6, ...
    cfg.drain_max_us*1e-6,cfg.n_eval_runs,cfg.q_validation_runs, ...
    cfg.q_max_refinement_passes);

experiment = run_experiment(cfg);
analyze_experiment_v2(experiment.output_dir);

merge_outputs = merge_supplement_results(base_dir,experiment.output_dir);

fprintf('\nSB-CF robust rerun complete.\n');
fprintf('Rerun directory: %s\n',experiment.output_dir);
fprintf('Combined summary: %s\n',merge_outputs.combined_summary_path);
fprintf('Combined view dir: %s\n',merge_outputs.combined_dir);
