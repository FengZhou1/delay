
function bench_four()
cfg = default_lightload_sfcb_config('analysis','delay');
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
lambda = 10;
trace = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base);
M = 6;
for q = [1, 0.5]
    t0 = tic;
    r = simulate_sfcb_lightload_variant('sf_cb', trace, scenario, cfg, M, q, 1001);
    t1 = toc(t0);
    d = r.diagnostics;
    fprintf('BENCH sf_cb M=6 lambda=10 q=%g: %.3f s\n', q, t1);
    fprintf('  fields: %s\n', strjoin(fieldnames(d), ','));
end
end
