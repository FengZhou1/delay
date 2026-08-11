addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
lambda = 1;

% Check seed 1 trace (the tuning trace)
tr_tune = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base);
fprintf('Tune trace (seed base=%d): n_packets=%d\n', cfg.traffic_seed_base, tr_tune.n_packets);

% Run sf_cb with tune trace, q=1
result = simulate_sfcb_lightload_variant('sf_cb', tr_tune, scenario, cfg, 1, 1, cfg.protocol_seed_base);
s = result.summary;
fprintf('sf_cb q=1 tune trace: delay=%.2f cr=%.4f stable=%d n_arrived=%d n_completed=%d\n', ...
    s.mean_delay_us, s.completion_ratio, s.stable, s.n_arrived, s.n_completed);

% Run sf_cb with eval seed 1, q=1  
tr1 = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base + 100);
result1 = simulate_sfcb_lightload_variant('sf_cb', tr1, scenario, cfg, 1, 1, cfg.protocol_seed_base + 1);
s1 = result1.summary;
fprintf('sf_cb q=1 eval seed 1: delay=%.2f cr=%.4f stable=%d n_arrived=%d n_completed=%d\n', ...
    s1.mean_delay_us, s1.completion_ratio, s1.stable, s1.n_arrived, s1.n_completed);

% Run sf_cb with eval seed 2
tr2 = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base + 200);
result2 = simulate_sfcb_lightload_variant('sf_cb', tr2, scenario, cfg, 1, 1, cfg.protocol_seed_base + 2);
s2 = result2.summary;
fprintf('sf_cb q=1 eval seed 2: delay=%.2f cr=%.4f stable=%d n_arrived=%d n_completed=%d\n', ...
    s2.mean_delay_us, s2.completion_ratio, s2.stable, s2.n_arrived, s2.n_completed);
