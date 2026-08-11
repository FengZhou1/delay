function cfg = default_lightload_sfcb_config(profile, mode)
%DEFAULT_LIGHTLOAD_SFCB_CONFIG Config for the four-protocol light-load study.
%   cfg = default_lightload_sfcb_config()                 % analysis, delay
%   cfg = default_lightload_sfcb_config('smoke')          % fast end-to-end
%   cfg = default_lightload_sfcb_config('analysis','saturation')
%
% Scientific axes: n_nodes=40, n_sectors=8, lambda=[1 5 10] pkt/s per node,
% M=1:6.  The study uses its own real-time timings (see protocol_timing.m)
% and never modifies the shared parent timing config.  PHY and topology
% defaults are inherited from the parent default_experiment_config.

    if nargin < 1 || isempty(profile)
        profile = 'analysis';
    end
    if nargin < 2 || isempty(mode)
        mode = 'delay';
    end
    profile = lower(char(profile));
    mode = lower(char(mode));
    if ~ismember(profile, {'smoke','analysis'})
        error('default_lightload_sfcb_config:BadProfile', ...
            'Expected profile smoke or analysis.');
    end
    if ~ismember(mode, {'delay','saturation'})
        error('default_lightload_sfcb_config:BadMode', ...
            'Expected mode delay or saturation.');
    end

    cfg = default_experiment_config(profile);
    cfg.schema_version = '3.0-lightload-study';
    cfg.profile = profile;
    cfg.mode = mode;
    cfg.study_type = 'sf_cb_lightload_study';
    cfg.protocols = {'sf_cb','batch_clear','unslotted','sb_cb'};
    cfg.lambda_values = [1 5 10];
    cfg.M_values = 1:6;
    cfg.load_modes = {'fixed_packet'};
    cfg.n_nodes = 40;
    cfg.n_sectors = 8;
    cfg.arrival_tick_us = 9;

    % q search common defaults (overridden per mode/profile below).
    cfg.q_coarse = unique([10.^(-5:0.25:0), 0.05:0.05:1.0]);
    cfg.q_fine_points = 9;
    cfg.q_refine_floor = 1e-7;
    cfg.q_refine_scale = 'auto';
    cfg.min_tune_completion_ratio = 0.99;
    cfg.min_eval_completion_ratio = 0.99;
    cfg.n_tune_runs = 1;
    cfg.n_eval_runs = 3;
    cfg.stats_sample_us = 500;
    cfg.parallel = true;
    cfg.run_preflight_tests = false;
    cfg.resume = true;
    % Safety caps for the continuous-time protocols (unslotted, sb_cb) at
    % high load: the exponential/slot retry delay shrinks with q and the
    % per-run cost can reach tens of seconds.  q_max_light = 1 keeps the
    % full delay-optimal region (q ~ 0.5..1) intact and only guards against
    % pathological configs; q_max_sat trims the saturation grids where the
    % optimum is known to lie at q ~ 1e-3..0.03.
    cfg.q_max_light = 0.99;
    cfg.q_max_sat = 0.1;
    cfg.output_root = fullfile(fileparts(mfilename('fullpath')),'results');
    cfg.collect_packet_log = true;
    cfg.collect_diagnostics = true;

    % Stability stays diagnostic; q selection uses the completed measurement
    % cohort and separately reports completion/censoring.
    cfg.stability_rate_tolerance = 0.20;
    cfg.stability_censor_tolerance = 0.02;
    cfg.stability_slope_fraction = 0.10;
    cfg.stability_require_slope = false;

    if strcmp(mode,'saturation')
        cfg.traffic_mode = 'saturation';
        cfg.warmup_us = 2e5;
        cfg.measure_us = 1e6;
        cfg.drain_max_us = 0;
        cfg.q_fine_points = 7;
        cfg.n_eval_runs = 3;
        cfg.protocol_q_grids = struct();
        cfg.protocol_q_grids.sf_cb = unique([logspace(-3,-1,9), 0.025]);
        cfg.protocol_q_grids.batch_clear = ...
            unique([logspace(-3,-1,9), 0.025]);
        cfg.protocol_q_grids.unslotted = unique([ ...
            logspace(-5,-2,14), 1e-3, 3e-3, 1e-2]);
        cfg.protocol_q_grids.sb_cb = unique([ ...
            logspace(-5,-2,14), 1e-3, 3e-3, 1e-2]);
    else
        cfg.traffic_mode = 'light_load';
        cfg.warmup_us = 2e5;
        cfg.measure_us = 2e6;
        cfg.drain_max_us = 5e6;
        cfg.tune_warmup_us = 2e5;
        cfg.tune_measure_us = 1e6;
        cfg.tune_drain_max_us = 5e6;
    end

    switch profile
        case 'smoke'
            cfg.lambda_values = [1 5 10];
            cfg.M_values = [1 3];
            cfg.warmup_us = 0;
            cfg.measure_us = 1e5;
            cfg.drain_max_us = 5e5;
            cfg.tune_warmup_us = 0;
            cfg.tune_measure_us = 5e4;
            cfg.tune_drain_max_us = 2e5;
            cfg.n_eval_runs = 1;
            cfg.q_coarse = [0.1 0.5 1];
            cfg.q_fine_points = 5;
            if strcmp(mode,'saturation')
                cfg.warmup_us = 0;
                cfg.measure_us = 2e4;
                cfg.q_fine_points = 3;
                cfg.protocol_q_grids.sf_cb = [1e-2 0.025 1e-1];
                cfg.protocol_q_grids.batch_clear = [1e-2 0.025 1e-1];
                cfg.protocol_q_grids.unslotted = [1e-3 1e-2 1e-1];
                cfg.protocol_q_grids.sb_cb = [1e-3 1e-2 1e-1];
            end
        case 'analysis'
            % Defaults above: delay 0.2s warmup + 2s measure + 5s drain;
            % saturation 0.2s warmup + 1s measure, no drain.
    end

    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
    % NOTE: the parent validate_experiment_config rejects the study's own
    % protocol names, so the study keeps its config self-contained.
    cfg.output_root = fullfile(fileparts(mfilename('fullpath')),'results');
end