function experiment = run_all_delay(lambda_values,sim_time_total_us,n_runs)
%RUN_ALL_DELAY Compatibility batch entry using all six v2 protocols.
    if nargin<1 || isempty(lambda_values), lambda_values=[5 15 30]; end
    if nargin<2 || isempty(sim_time_total_us), sim_time_total_us=1e7; end
    if nargin<3 || isempty(n_runs), n_runs=1; end
    cfg=default_experiment_config('pilot');
    cfg.lambda_values=lambda_values;
    cfg.M_values=1:6;
    cfg.load_modes={'fixed_packet'};
    cfg.warmup_us=min(2e6,0.2*sim_time_total_us);
    cfg.measure_us=sim_time_total_us;
    cfg.drain_max_us=min(5e7,max(5e6,2*sim_time_total_us));
    cfg.n_tune_runs=max(3,n_runs);
    cfg.n_eval_runs=n_runs;
    cfg.arrival_end_us=cfg.warmup_us+cfg.measure_us;
    cfg.sim_hard_end_us=cfg.arrival_end_us+cfg.drain_max_us;
    experiment=run_experiment(cfg);
    analyze_experiment_v2(experiment.output_dir);
end
