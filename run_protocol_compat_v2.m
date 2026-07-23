function experiment = run_protocol_compat_v2(protocol,lambda_val, ...
        sim_time_total_us,n_runs,q_values)
%RUN_PROTOCOL_COMPAT_V2 Keep legacy script names on the verified v2 engine.
    if nargin<2 || isempty(lambda_val), lambda_val=5; end
    if nargin<3 || isempty(sim_time_total_us), sim_time_total_us=1e7; end
    if nargin<4 || isempty(n_runs), n_runs=1; end

    cfg = default_experiment_config('pilot');
    cfg.protocols = {char(protocol)};
    cfg.lambda_values = lambda_val;
    cfg.M_values = 1:6;
    cfg.load_modes = {'fixed_packet'};
    cfg.warmup_us = min(2e6,0.2*sim_time_total_us);
    cfg.measure_us = sim_time_total_us;
    cfg.drain_max_us = min(5e7,max(5e6,2*sim_time_total_us));
    cfg.n_tune_runs = max(3,n_runs);
    cfg.n_eval_runs = n_runs;
    if nargin>=5 && ~isempty(q_values)
        cfg.q_coarse = unique(double(q_values(:).'));
    end
    cfg.arrival_end_us = cfg.warmup_us + cfg.measure_us;
    cfg.sim_hard_end_us = cfg.arrival_end_us + cfg.drain_max_us;
    experiment = run_experiment(cfg);
    analyze_experiment_v2(experiment.output_dir);
end
