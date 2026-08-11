addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

tune_cfg = cfg;
tune_cfg.warmup_us = cfg.tune_warmup_us;
tune_cfg.measure_us = cfg.tune_measure_us;
tune_cfg.drain_max_us = cfg.tune_drain_max_us;
tune_cfg.arrival_end_us = tune_cfg.warmup_us + tune_cfg.measure_us;
tune_cfg.sim_hard_end_us = tune_cfg.arrival_end_us + tune_cfg.drain_max_us;

fprintf('=== Tune trace (coarse scan, 1 seed) ===\n');
tr = generate_arrival_trace(1, tune_cfg, cfg.traffic_seed_base);
for proto = {'unslotted','sb_cb'}
    p = proto{1};
    result = simulate_sfcb_lightload_variant(p, tr, scenario, tune_cfg, 1, 1, cfg.protocol_seed_base);
    s = result.summary;
    fprintf('%-12s tune: delay=%-8.2f cr=%.4f stable=%d\n', p, s.mean_delay_us, s.completion_ratio, s.stable);
end

fprintf('\n=== Eval traces (3 seeds) ===\n');
for s_idx = 1:3
    tr_s = generate_arrival_trace(1, cfg, cfg.traffic_seed_base + 100*s_idx);
    fprintf('Seed +%d:\n', 100*s_idx);
    for proto = {'unslotted','sb_cb'}
        p = proto{1};
        result = simulate_sfcb_lightload_variant(p, tr_s, scenario, cfg, 1, 1, cfg.protocol_seed_base + s_idx);
        s = result.summary;
        fprintf('  %-12s delay=%-8.2f cr=%.4f stable=%d\n', p, s.mean_delay_us, s.completion_ratio, s.stable);
    end
end
