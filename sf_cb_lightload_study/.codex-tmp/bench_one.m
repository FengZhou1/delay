
function bench_one()
cfg = default_lightload_sfcb_config('analysis','delay');
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
lambda = 10;
trace = generate_arrival_trace(lambda, cfg, cfg.traffic_seed_base);
M = 6;
q = 0.5;
t0 = tic;
r = simulate_sfcb_lightload_variant('unslotted', trace, scenario, cfg, M, q, 1001);
t1 = toc(t0);
fprintf('BENCH unslotted M=6 lambda=10 q=0.5: %.3f s\n', t1);
fprintf('rts_attempts=%d sim_end_us=%.0f\n', r.diagnostics.rts_attempts, r.summary.sim_end_us);
end
