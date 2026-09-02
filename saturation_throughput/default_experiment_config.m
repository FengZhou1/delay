function cfg = default_experiment_config(profile)
%DEFAULT_EXPERIMENT_CONFIG Reproducible configuration for the v2 simulator.
%   cfg = default_experiment_config('smoke'|'scaled'|'analysis'|'pilot'|'full')
%
% The no-argument profile is deliberately small so that an accidental call
% never launches a multi-hour experiment.  Use the 'full' profile explicitly
% for the publication-scale experiment.

    if nargin < 1 || isempty(profile)
        profile = 'smoke';
    end

    cfg.schema_version = '2.0';
    cfg.profile = lower(char(profile));
    cfg.protocols = {'sf_cf', 'sf_cb', 'sb_cf', 'sb_cb', ...
                     's7_clean', 's7_busy', 'unslotted'};
    cfg.lambda_values = [5, 15, 30];       % pkt/STA/s at M=1
    cfg.M_values = 1:6;
    cfg.load_modes = {'fixed_packet'};

    cfg.n_nodes = 40;
    cfg.n_sectors = 8;
    % New mmWave timing set. Protocol durations are expressed as integer
    % slot counts; microsecond values are derived by mmw_timing_config().
    cfg.mmw_slot_us = 9;
    cfg.mmw_data_rate_bps = 2.2e9;
    cfg.mmw_control_rate_bps = 260e6;
    cfg.mmw_phy_header_slots = 2;
    cfg.mmw_sifs_slots = 2;
    cfg.mmw_difs_slots = 4;
    cfg.mmw_rts_bits = 160;
    cfg.mmw_cts_bits = 112;
    cfg.mmw_rts_slots = 2;
    cfg.mmw_cts_slots = 2;
    cfg.arrival_tick_us = cfg.mmw_slot_us;
    mmw_timing = mmw_timing_config(cfg);
    cfg.mmw_conn_slot_slots = mmw_timing.CONN_SLOT_SLOTS;
    % Legacy integer-slot value (198 us).  Saturation uses
    % cfg.mmw_real_conn_slot_us (162.5 us); do not use this for Tp.
    cfg.mmw_conn_slot_us = mmw_timing.CONN_SLOT_US;
    % Real-time (non slot-aligned) timing for sf_cb and sb_cb, matching
    % sf_cb_lightload_study/protocol_timing.m (plan section 2).  These are
    % NOT integer multiples of the 9 us mmWave slot, so the sf_cb/sb_cb
    % simulators use their own event-driven engines while sf_cf, sb_cf and
    % s7 keep the legacy integer-slot timing above.
    cfg.mmw_real_rts_us = 14.5;
    cfg.mmw_real_sifs_us = 16;
    cfg.mmw_real_difs_us = 34;
    cfg.mmw_real_cts_us = 14.5;
    cfg.mmw_real_n_sectors = cfg.n_sectors;
    cfg.mmw_real_cts_sweep_us = cfg.mmw_real_cts_us * cfg.n_sectors;
    cfg.mmw_real_conn_slot_us = cfg.mmw_real_rts_us + cfg.mmw_real_sifs_us + ...
        cfg.mmw_real_cts_sweep_us + cfg.mmw_real_sifs_us;
    cfg.mmw_real_cts_timeout_us = cfg.mmw_real_sifs_us + ...
        cfg.mmw_real_cts_sweep_us;
    cfg.topology_seed = 20260325;
    cfg.traffic_seed_base = 20260722;
    cfg.protocol_seed_base = 731927;

    cfg.q_coarse = unique([10.^(-5:0.25:0), 0.05:0.05:1.0]);
    cfg.q_refine_points = 9;
    cfg.q_two_stage_tuning = false;
    cfg.q_coarse_tune_runs = 1;
    cfg.q_fine_tune_runs = 3;
    cfg.q_fine_points = 5;
    cfg.q_max_refinement_passes = 1;
    cfg.q_refine_neighbor_span = 1;
    cfg.q_preferred_neighbor_radius = 1;
    cfg.q_validation_runs = 0;
    cfg.q_validation_max_candidates = 1;
    cfg.q_refine_scale = 'auto';
    cfg.q_refine_floor = 1e-7;
    cfg.q_require_stable_neighbors = true;
    cfg.q_fallback_self_stable = true;
    cfg.adaptive_q_grid = false;
    cfg.q_grid_light = [];
    cfg.q_grid_medium = [];
    cfg.q_grid_heavy = [];
    cfg.q_grid_light_max_aggregate_pkt_s = NaN;
    cfg.q_grid_medium_max_aggregate_pkt_s = NaN;
    cfg.protocol_q_grids_enabled = false;
    cfg.protocol_q_grids = struct( ...
        'sf_cf',[], 'sf_cb',[], 'sb_cf',[], 'sb_cb',[], ...
        's7_clean',[], 's7_busy',[], 'unslotted',[]);
    cfg.tune_min_expected_arrivals = 0;
    cfg.tune_measure_max_us = NaN;
    cfg.tuning_rate_screen = true;
    cfg.common_arrivals_by_effective_rate = true;
    cfg.parallel = true;
    cfg.n_workers = 4;
    cfg.condition_timeout_s = 1800;
    cfg.tune_warmup_us = 0;
    cfg.tune_measure_us = 2e6;
    cfg.tune_drain_max_us = 5e6;

    cfg.payload_bits_M1 = NaN;
    cfg.stats_sample_us = 1000;
    cfg.collect_packet_log = true;
    cfg.collect_diagnostics = true;
    cfg.collect_debug_trace = false;
    cfg.run_preflight_tests = true;
    cfg.results_root = fullfile(pwd, 'results_v2');
    cfg.resume = true;
    cfg.condition_filter = {};

    cfg.cca_mode = 'directional';           % directional | oracle | disabled
    cfg.rx_sens_dbm = -62;
    cfg.noise_dbm = -81;
    cfg.data_sinr_th_db = 21;
    cfg.cts_sinr_th_db = 6;
    % Deprecated compatibility alias. RTS now uses a classic collision
    % model; this threshold is used only for CTS decoding.
    cfg.ctrl_sinr_th_db = cfg.cts_sinr_th_db;
    cfg.rx_sens_sweep_dbm = [-72, -67, -62, -57, -52];
    cfg.cca_ablation_modes = {'directional', 'oracle', 'disabled'};
    cfg.run_cca_ablation = false;
    cfg.ablation_lambda_values = cfg.lambda_values;
    cfg.ablation_M_values = cfg.M_values;
    cfg.ablation_load_modes = {'fixed_packet'};
    cfg.n_ablation_runs = 3;
    cfg.run_topology_robustness = false;
    cfg.robustness_topology_seeds = 20260325 + (1:5);
    cfg.robustness_lambda_values = [5, 30];
    cfg.robustness_M_values = [1, 3, 6];
    cfg.robustness_protocols = cfg.protocols;
    cfg.n_robustness_runs = 1;

    cfg.stability_rate_tolerance = 0.05;
    cfg.stability_censor_tolerance = 0.01;
    cfg.stability_slope_fraction = 0.05;
    cfg.stability_require_slope = true;

    switch cfg.profile
        case 'smoke'
            cfg.lambda_values = 30;
            cfg.M_values = [1, 3];
            cfg.load_modes = {'fixed_packet'};
            cfg.warmup_us = 0;
            cfg.measure_us = 2e4;
            cfg.drain_max_us = 2e4;
            cfg.n_tune_runs = 1;
            cfg.n_eval_runs = 1;
            cfg.q_coarse = [0.01, 0.05, 0.1, 0.2, 0.5, 1.0];
            cfg.q_refine_points = 0;
            cfg.parallel = false;
            cfg.stability_rate_tolerance = 0.25;
            cfg.stability_censor_tolerance = 0.10;
            cfg.stability_slope_fraction = 1.0;
            cfg.tune_warmup_us = 0;
            cfg.tune_measure_us = cfg.measure_us;
            cfg.tune_drain_max_us = cfg.drain_max_us;
        case 'pilot'
            cfg.warmup_us = 2e5;
            cfg.measure_us = 2e6;
            cfg.drain_max_us = 5e6;
            cfg.n_tune_runs = 3;
            cfg.n_eval_runs = 3;
            cfg.tune_measure_us = 5e5;
            cfg.tune_drain_max_us = 1e6;
        case 'scaled'
            % Reproducible, all-axis engineering validation.  It is useful
            % for finding logic/performance regressions but is intentionally
            % too short to replace the publication-scale full profile.
            cfg.warmup_us = 5e3;
            cfg.measure_us = 5e4;
            cfg.drain_max_us = 1e5;
            cfg.n_tune_runs = 1;
            cfg.n_eval_runs = 1;
            cfg.tune_measure_us = 2e4;
            cfg.tune_drain_max_us = 4e4;
            % Keep the engineering matrix bounded.  The full profile still
            % uses the complete logarithmic/high-probability coarse grid and
            % nine-point refinement required for publication runs.
            cfg.q_coarse = [0.001 0.003 0.01 0.025 0.05 0.1 0.3 0.5 0.8 1];
            cfg.q_refine_points = 0;
            cfg.stats_sample_us = 500;
            cfg.stability_rate_tolerance = 0.50;
            cfg.stability_censor_tolerance = 0.25;
            cfg.stability_slope_fraction = 0.50;
            cfg.stability_require_slope = false;
            cfg.run_cca_ablation = true;
            cfg.ablation_lambda_values = 10;
            cfg.ablation_M_values = [1 3 6];
            cfg.n_ablation_runs = 1;
            cfg.run_topology_robustness = true;
            cfg.robustness_topology_seeds = 20260325 + (1:2);
            cfg.robustness_protocols = {'sf_cb','sb_cb'};
            cfg.n_robustness_runs = 1;
        case 'analysis'
            % Main-matrix analysis profile: all protocols, loads and M values,
            % using a one-second evaluation window. CCA and topology studies
            % are intentionally not repeated here; use the scaled/full
            % profiles or enable them explicitly when needed.
            cfg.lambda_values = [1 5 10];
            cfg.warmup_us = 2e5;
            cfg.measure_us = 1e6;
            cfg.drain_max_us = 1e6;
            cfg.n_tune_runs = 3;
            cfg.n_eval_runs = 3;
            cfg.tune_warmup_us = 2e5;
            cfg.tune_measure_us = 1e6;
            cfg.tune_drain_max_us = 1e6;
            cfg.q_coarse = [0.001 0.003 0.01 0.025 0.05 0.1 0.3 0.5 0.8 1];
            cfg.q_refine_points = 0;
            cfg.q_two_stage_tuning = true;
            cfg.q_coarse_tune_runs = 3;
            cfg.q_fine_tune_runs = 3;
            cfg.q_fine_points = 15;
            cfg.q_max_refinement_passes = 3;
            cfg.q_refine_neighbor_span = 2;
            cfg.q_preferred_neighbor_radius = 2;
            cfg.q_validation_runs = 2;
            cfg.q_validation_max_candidates = 3;
            cfg.q_refine_scale = 'auto';
            cfg.q_refine_floor = 1e-7;
            cfg.q_require_stable_neighbors = true;
            cfg.q_fallback_self_stable = true;
            cfg.adaptive_q_grid = false;
            cfg.protocol_q_grids_enabled = true;
            cfg.protocol_q_grids.sf_cf = ...
                [1e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.sf_cb = ...
                [1e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.sb_cf = ...
                [1e-5 2e-5 5e-5 1e-4 2e-4 5e-4 1e-3 2e-3 ...
                 5e-3 1e-2 2e-2 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.sb_cb = ...
                [1e-4 2e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.s7_clean = ...
                [1e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.s7_busy = ...
                [1e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.protocol_q_grids.unslotted = ...
                [1e-4 5e-4 1e-3 2e-3 5e-3 1e-2 2e-2 ...
                 5e-2 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1];
            cfg.q_grid_light = [0.001 0.003 0.01 0.025 0.05 0.1 0.2 0.5 1];
            cfg.q_grid_medium = [0.005 0.01 0.025 0.05 0.1 0.2 0.3 0.5 0.7];
            cfg.q_grid_heavy = [0.01 0.025 0.05 0.1 0.15 0.2 0.3 0.5 0.7];
            cfg.q_grid_light_max_aggregate_pkt_s = 200;
            cfg.q_grid_medium_max_aggregate_pkt_s = 500;
            cfg.tune_min_expected_arrivals = 20;
            cfg.tune_measure_max_us = 1e6;
            cfg.stats_sample_us = 500;
            cfg.stability_rate_tolerance = 0.05;
            cfg.stability_censor_tolerance = 0.01;
            cfg.stability_slope_fraction = 0.05;
            cfg.stability_require_slope = true;
            cfg.run_cca_ablation = false;
            cfg.run_topology_robustness = false;
        case 'full'
            cfg.warmup_us = 2e6;
            cfg.measure_us = 1e7;
            cfg.drain_max_us = 5e7;
            cfg.n_tune_runs = 3;
            cfg.n_eval_runs = 10;
            cfg.n_ablation_runs = 10;
            cfg.run_cca_ablation = true;
            cfg.run_topology_robustness = true;
        otherwise
            error('default_experiment_config:BadProfile', ...
                  ['Unknown profile "%s". Use smoke, scaled, analysis, pilot, ', ...
                   'or full.'], profile);
    end

    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
end


