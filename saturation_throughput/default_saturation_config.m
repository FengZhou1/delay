function cfg = default_saturation_config(profile)
%DEFAULT_SATURATION_CONFIG Configuration for saturated-throughput studies.
%   cfg = default_saturation_config('smoke'|'analysis'|'full')
%
% Saturation experiments share the current v2 topology, PHY, timing, and
% protocol state machines.  They differ only in workload supply and in the
% objective used to select q: successful payload airtime is maximized.

    if nargin < 1 || isempty(profile)
        profile = 'smoke';
    end
    profile = lower(char(profile));

    % Start from the current v2 timing/PHY defaults.  Delay-only axes are
    % retained where prepare_scenario_v2 and the protocol simulators expect
    % them, but the saturation runner never generates stochastic arrivals.
    cfg = default_experiment_config('smoke');
    cfg.schema_version = '2.2-saturation';
    cfg.profile = profile;
    cfg.study_type = 'saturation_throughput';
    cfg.traffic_mode = 'saturation';
    cfg.protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};

    % All saturation protocols share the exact 162.5-us connection slot
    % (MMW_REAL.CONN_OVERHEAD_US).  Fractional M keeps the short-payload
    % portion of the legacy sweep, and DATA airtime is exactly M*162.5 us.
    cfg.M_values = [1/10, 1/5, 2/5, 3/5, 1:6, 8, 10, 15, 20];
    cfg.warmup_us = 2e5;
    cfg.measure_us = 1e6;
    cfg.drain_max_us = 0;
    cfg.n_tune_runs = 1;
    cfg.n_eval_runs = 3;
    cfg.q_fine_points = 7;
    cfg.q_refine_floor = 1e-7;

    % SF protocols use the exact classic-Aloha saturated optimum 1/N.
    % The remaining grids cover the ranges used by the legacy throughput
    % study, with logarithmic compression before local refinement.
    aloha_q = 1 / cfg.n_nodes;
    cfg.protocol_q_grids_enabled = true;
    cfg.protocol_q_grids = struct();
    cfg.protocol_q_grids.sf_cf = aloha_q;
    cfg.protocol_q_grids.sf_cb = aloha_q;
    cfg.protocol_q_grids.sb_cf = unique([ ...
        logspace(-5,log10(3e-2),13), 1e-3, 3e-3, 1e-2, 3e-2]);
    cfg.protocol_q_grids.sb_cb = unique([ ...
        logspace(-5,-2,13), 1e-3, 3e-3, 1e-2]);
    cfg.protocol_q_grids.s7_clean = ...
        [0.001 0.003 0.005 0.009 0.015 0.025 0.05 0.1 0.2 0.4 0.6 0.8 1];
    cfg.protocol_q_grids.s7_busy = ...
        [1e-4 3e-4 5e-4 1e-3 3e-3 5e-3 1e-2 2e-2 5e-2 0.1 0.2];
    cfg.protocol_q_grids.unslotted = unique([logspace(-5,log10(3e-2),15), 1e-3, 3e-3, 1e-2]);

    cfg.parallel = true;
    cfg.n_workers = 4;
    cfg.collect_packet_log = false;
    cfg.collect_diagnostics = true;
    cfg.collect_debug_trace = false;
    cfg.run_preflight_tests = true;
    cfg.resume = true;
    cfg.condition_filter = {};
    cfg.results_root = fullfile(pwd,'results');
    cfg.condition_timeout_s = 1800;

    switch profile
        case 'smoke'
            cfg.M_values = [1/10 1];
            cfg.warmup_us = 0;
            cfg.measure_us = 2e4;
            cfg.n_tune_runs = 1;
            cfg.n_eval_runs = 1;
            cfg.q_fine_points = 3;
            cfg.protocols = {'sf_cf','sf_cb','sb_cf','sb_cb','s7_clean','s7_busy','unslotted'};
            cfg.protocol_q_grids.sb_cf = [1e-3 1e-2 3e-2];
            cfg.protocol_q_grids.sb_cb = [1e-3 5e-3 1e-2];
            cfg.protocol_q_grids.s7_clean = [0.005 0.025 0.1];
            cfg.protocol_q_grids.s7_busy = [0.001 0.01 0.05];
            cfg.parallel = false;
        case 'analysis'
            % Defaults above: 0.2 s warm-up, 1 s measurement, one paired
            % tuning seed and three independent evaluation seeds.
        case 'full'
            cfg.warmup_us = 2e6;
            cfg.measure_us = 1e7;
            cfg.n_tune_runs = 3;
            cfg.n_eval_runs = 10;
            cfg.q_fine_points = 9;
        otherwise
            error('default_saturation_config:BadProfile', ...
                'Unknown profile "%s". Use smoke, analysis, or full.',profile);
    end

    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us;
end
