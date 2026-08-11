%% ===== DIAGNOSTIC: unslotted q=1 single packet timing =====
addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('smoke','delay');
cfg.n_nodes = 8;
cfg.n_sectors = 8;
cfg.rx_sens_dbm = -62;
cfg.warmup_us = 0;
cfg.measure_us = 10000;
cfg.arrival_end_us = 10000;
cfg.drain_max_us = 1000;
cfg.sim_hard_end_us = 11000;
cfg.topology_seed = 42;

scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

% Manual trace: ONE packet at t=5000, node 1
tr = struct();
tr.times_us = 5000;
tr.node_id = 1;
tr.packet_ids_by_node = cell(8,1);
tr.packet_ids_by_node{1} = 1;
for u = 2:8, tr.packet_ids_by_node{u} = []; end
tr.n_packets = 1;
tr.lambda_per_node = NaN;
tr.arrival_end_us = cfg.arrival_end_us;
tr.hard_end_us = cfg.sim_hard_end_us;

fprintf('=== DIAGNOSTIC: unslotted q=1, M=1, 8 nodes, 1 packet ===\n\n');

result = simulate_unslotted_sf_cb(tr, scenario, cfg, 1, 1, 12345);

pkt = result.packet_log;
fprintf('Packet timing:\n');
fprintf('  arrival_us       = %.6f\n', pkt.arrival_us(1));
fprintf('  hol_us           = %.6f\n', pkt.hol_us(1));
fprintf('  first_attempt_us = %.6f\n', pkt.first_attempt_us(1));
fprintf('  completion_us    = %.6f\n', pkt.completion_us(1));
fprintf('  attempts         = %d\n', pkt.attempts(1));
fprintf('\nDelay breakdown:\n');
fprintf('  total_delay      = %.6f us\n', pkt.total_delay_us(1));
fprintf('  queue_delay      = %.6f us (arrival->HOL)\n', pkt.queue_delay_us(1));
fprintf('  access_delay     = %.6f us (HOL->completion)\n', pkt.access_delay_us(1));
fprintf('  probability_wait = %.6f us\n', pkt.probability_wait_us(1));
fprintf('  collision_delay  = %.6f us\n', pkt.collision_delay_us(1));
fprintf('  control_delay    = %.6f us\n', pkt.control_delay_us(1));
fprintf('  data_delay       = %.6f us\n', pkt.data_delay_us(1));
fprintf('  boundary_wait    = %.6f us\n', pkt.boundary_wait_us(1));
fprintf('  difs_wait        = %.6f us\n', pkt.difs_wait_us(1));

fprintf('\nSummary:\n');
fprintf('  mean_delay_us    = %.6f\n', result.summary.mean_delay_us);
fprintf('  completion_ratio = %.6f\n', result.summary.completion_ratio);
fprintf('  final_backlog    = %d\n', result.summary.final_backlog);

fprintf('\nTheoretical: 325.0 us (RTS 14.5 + SIFS 16 + CTS_sweep 116 + SIFS 16 + DATA 162.5)\n');
fprintf('Difference:       %.6f us\n', result.summary.mean_delay_us - 325.0);
fprintf('\nAccess delay components: prob_wait=%.6f + control=%.6f + data=%.6f + coll=%.6f = %.6f\n', ...
    pkt.probability_wait_us(1), pkt.control_delay_us(1), pkt.data_delay_us(1), ...
    pkt.collision_delay_us(1), ...
    pkt.probability_wait_us(1)+pkt.control_delay_us(1)+pkt.data_delay_us(1)+pkt.collision_delay_us(1));
