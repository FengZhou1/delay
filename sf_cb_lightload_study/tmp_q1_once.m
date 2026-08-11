addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

% Use the SAME seeds as the scan: tune trace + eval seed+100
fprintf('=== sf_cb & batch_clear, q=1, 单次 eval (seed+100) ===\n\n');
tr = generate_arrival_trace(1, cfg, cfg.traffic_seed_base + 100);

for proto = {'sf_cb','batch_clear'}
    p = proto{1};
    result = simulate_sfcb_lightload_variant(p, tr, scenario, cfg, 1, 1, cfg.protocol_seed_base + 1);
    s = result.summary;
    fprintf('%-12s: delay=%s  cr=%.4f  n_arrived=%d  n_completed=%d  stable=%d\n', ...
        p, mat2str(s.mean_delay_us,3), s.completion_ratio, s.n_arrived, s.n_completed, s.stable);
end

fprintf('\n这个 seed+100 就是 eval 的第一个种子，cr=0.32，q=1 翻车。\n');
