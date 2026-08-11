addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

tr = generate_arrival_trace(1, cfg, cfg.traffic_seed_base);
fprintf('Tune trace: n_packets=%d, seed=%d\n', tr.n_packets, cfg.traffic_seed_base);

result = simulate_sfcb_lightload_variant('sf_cb', tr, scenario, cfg, 1, 1, cfg.protocol_seed_base);

pkt = result.packet_log;
arr = pkt.arrival_us;
comp = pkt.completion_us;
cmpl = isfinite(comp);
n_cmpl = sum(cmpl);

cohort = arr >= 200000 & arr < 1200000;
fprintf('Cohort: %d arrived, %d completed\n', sum(cohort), sum(cohort & cmpl));

% Show incomplete packets
incomplete = cohort & ~cmpl;
if any(incomplete)
    fprintf('\nIncomplete packets in cohort:\n');
    idx = find(incomplete);
    for i = 1:numel(idx)
        pid = idx(i);
        fprintf('  pkt %d: node=%d arrival=%.0f us attempts=%d hol=%.0f first_attempt=%.0f\n', ...
            pid, pkt.node_id(pid), arr(pid), pkt.attempts(pid), pkt.hol_us(pid), pkt.first_attempt_us(pid));
    end
end

% Show collision stats
fprintf('\nDiagnostics:\n');
diag = result.diagnostics;
if isfield(diag,'rts_success'), fprintf('  rts_success=%d\n', diag.rts_success); end
if isfield(diag,'rts_fail_total'), fprintf('  rts_fail_total=%d\n', diag.rts_fail_total); end
if isfield(diag,'rts_fail_collision'), fprintf('  rts_fail_collision=%d\n', diag.rts_fail_collision); end
if isfield(diag,'collision_slots'), fprintf('  collision_slots=%d\n', diag.collision_slots); end
if isfield(diag,'idle_slots'), fprintf('  idle_slots=%d\n', diag.idle_slots); end
fprintf('  sim_end_us=%.0f\n', result.summary.sim_end_us);

% All packets attempt distribution
atts = pkt.attempts(cohort);
fprintf('\nAttempts distribution (cohort):\n');
for a = 0:max(atts)
    n = sum(atts == a);
    if n > 0, fprintf('  attempts=%d: %d packets\n', a, n); end
end
fprintf('  mean attempts (completed cohort)=%.2f\n', mean(atts(cohort & cmpl)));
