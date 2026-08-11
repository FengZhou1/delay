addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

fprintf('=== sf_cb & batch_clear, q=1, 3 eval seeds ===\n\n');
for proto = {'sf_cb','batch_clear'}
    p = proto{1};
    delays = zeros(1,3);
    crs = zeros(1,3);
    for s = 1:3
        tr_s = generate_arrival_trace(1, cfg, cfg.traffic_seed_base + 100*s);
        result = simulate_sfcb_lightload_variant(p, tr_s, scenario, cfg, 1, 1, cfg.protocol_seed_base + s);
        delays(s) = result.summary.mean_delay_us;
        crs(s) = result.summary.completion_ratio;
    end
    fprintf('%-12s: [%.2f, %.2f, %.2f]  mean=%.2f us  cr=[%.2f,%.2f,%.2f]\n', ...
        p, delays(1), delays(2), delays(3), mean(delays,'omitnan'), crs(1), crs(2), crs(3));
end
fprintf('\n扫描选的: sf_cb=420.36(q=0.9562)  batch_clear=433.57(q=0.9500)\n');
