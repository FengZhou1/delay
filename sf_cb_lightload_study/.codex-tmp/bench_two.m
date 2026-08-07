
function bench_two()
cfg = default_lightload_sfcb_config('analysis','delay');
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
lambda = 10;
trace = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base);
M = 6;
for q = [0.5, 0.1, 0.01]
    t0 = tic;
    r = simulate_sfcb_lightload_variant('unslotted', trace, scenario, cfg, M, q, 1001);
    t1 = toc(t0);
    fprintf('BENCH unslotted M=6 lambda=10 q=%g: %.3f s (attempts=%d)\n', q, t1, r.diagnostics.rts_attempts);
end
end
