addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

% Generate same trace as the full run (lambda=1, eval seed base)
lambda = 1;
eval_cfg = cfg;
tr = generate_arrival_trace(lambda, eval_cfg, cfg.traffic_seed_base);

fprintf('=== λ=1, M=1, q=1 (3 eval seeds) ===\n\n');

for protocol = {'sf_cb','batch_clear'}
    proto = protocol{1};
    delays = zeros(1,3);
    for s = 1:3
        tr_s = generate_arrival_trace(lambda, eval_cfg, cfg.traffic_seed_base + 100*s);
        result = simulate_sfcb_lightload_variant(proto, tr_s, scenario, eval_cfg, 1, 1, cfg.protocol_seed_base + s);
        delays(s) = result.summary.mean_delay_us;
    end
    fprintf('%-12s  q=1.0  delay=[%.2f, %.2f, %.2f]  mean=%.2f us  std=%.2f us\n', ...
        proto, delays(1), delays(2), delays(3), mean(delays), std(delays));
end

% Also show theoretical
tm = protocol_timing(cfg);
conn = tm.CONN_SLOT_US;
fprintf('\n--- Theory ---\n');
fprintf('conn_slot = %.2f us, DATA = %.2f us\n', conn, conn);
fprintf('Transaction = RTS(%.1f)+SIFS(%.0f)+CTS(%.0f)+SIFS(%.0f)+DATA(%.1f) = %.1f us\n', ...
    tm.RTS_US, tm.SIFS_US, tm.CTS_SWEEP_US, tm.SIFS_US, conn, ...
    tm.RTS_US+tm.SIFS_US+tm.CTS_SWEEP_US+tm.SIFS_US+conn);
fprintf('With q=1: boundary_wait_mean = %.2f, total_expected = %.2f us\n', ...
    conn/2, conn/2 + tm.RTS_US+tm.SIFS_US+tm.CTS_SWEEP_US+tm.SIFS_US+conn);
