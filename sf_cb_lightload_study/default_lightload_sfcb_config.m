function cfg = default_lightload_sfcb_config(profile)
%DEFAULT_LIGHTLOAD_SFCB_CONFIG Independent SF-CB light-load study config.

    if nargin < 1 || isempty(profile)
        profile = 'analysis';
    end
    profile = lower(char(profile));

    cfg = default_experiment_config('analysis');
    cfg.study_type = 'sf_cb_lightload_mac_variants';
    cfg.study_schema_version = '1.0';
    cfg.profile = profile;
    cfg.protocols = {'sf_cb'};
    cfg.variants = {'baseline','fast_first','unslotted','batch_clear'};
    cfg.lambda_values = [1 3 5];
    cfg.M_values = 1:6;
    cfg.load_modes = {'fixed_packet'};

    cfg.warmup_us = 2e5;
    cfg.measure_us = 2e6;
    cfg.drain_max_us = 5e6;
    cfg.tune_warmup_us = 2e5;
    cfg.tune_measure_us = 1e6;
    cfg.tune_drain_max_us = 5e6;
    cfg.n_tune_runs = 3;
    cfg.n_validation_runs = 5;
    cfg.n_eval_runs = 5;

    cfg.q_coarse = [0.01 0.025 0.05 0.1 0.2 0.3 0.4 0.5 ...
        0.6 0.7 0.8 0.9 0.95 0.975 1.0];
    cfg.q_fine_points = 9;
    cfg.min_tune_completion_ratio = 0.99;
    cfg.min_validation_completion_ratio = 0.995;
    cfg.q_delay_tie_fraction = 0.01;
    % A high-q slotted-Aloha point can look excellent while one or two
    % contenders are active, yet enter a very long collision avalanche
    % after the contender set grows.  Validate recovery from a moderately
    % sized synchronized burst before allowing q into the delay search.
    cfg.q_stress_nodes = 12;
    cfg.q_stress_horizon_us = 2e6;
    cfg.q_stress_runs = 5;
    cfg.stats_sample_us = 500;
    cfg.parallel = false;
    cfg.run_preflight_tests = true;
    cfg.resume = false;
    cfg.output_root = fullfile(fileparts(mfilename('fullpath')),'results');
    cfg.collect_packet_log = true;
    cfg.collect_diagnostics = true;

    % Stability remains diagnostic in this low-arrival-count study. Delay
    % selection uses the completed measurement cohort and separately reports
    % completion/censoring instead of suppressing a finite conditional mean.
    cfg.stability_rate_tolerance = 0.20;
    cfg.stability_censor_tolerance = 0.02;
    cfg.stability_slope_fraction = 0.10;
    cfg.stability_require_slope = false;

    switch profile
        case 'smoke'
            cfg.lambda_values = 3;
            cfg.M_values = [1 3];
            cfg.warmup_us = 0;
            cfg.measure_us = 1e5;
            cfg.drain_max_us = 5e5;
            cfg.tune_warmup_us = 0;
            cfg.tune_measure_us = 5e4;
            cfg.tune_drain_max_us = 2e5;
            cfg.n_tune_runs = 1;
            cfg.n_validation_runs = 1;
            cfg.n_eval_runs = 1;
            cfg.q_coarse = [0.1 0.5 1];
            cfg.q_fine_points = 5;
        case 'analysis'
            % Defaults above.
        otherwise
            error('default_lightload_sfcb_config:BadProfile', ...
                'Expected profile analysis or smoke.');
    end

    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
    cfg = validate_experiment_config(cfg);
end
