%% ===== DIAGNOSTIC 2: Check real data and run full λ=1,M=1 with 40 nodes =====
addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

% First, check what is in delay_data.mat
fprintf('=== LOADING delay_data.mat ===\n');
data = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\delay_data.mat');
fprintf('Fields: %s\n', strjoin(fieldnames(data), ', '));

% Find unslotted, λ=1, M=1 entry
if isfield(data, 'results')
    r = data.results;
    for i = 1:numel(r)
        s = r{i}.summary;
        if strcmp(s.protocol, 'unslotted') && s.lambda_per_node == 1 && s.M == 1
            fprintf('\n=== Found unslotted λ=1 M=1 in results ===\n');
            fprintf('  mean_delay_us = %.6f\n', s.mean_delay_us);
            fprintf('  q = %.6f\n', s.q);
            fprintf('  completion_ratio = %.6f\n', s.completion_ratio);
            fprintf('  attempts = %d\n', s.attempts_completed_cohort);
            fprintf('  retransmissions = %d\n', s.retransmissions_completed_cohort);
            fprintf('  mean_attempts = %.6f\n', s.mean_attempts_completed);
            fprintf('  n_arrived = %d\n', s.n_arrived);
            fprintf('  n_completed = %d\n', s.n_completed);
        end
    end
else
    fprintf('No ''results'' field found.\n');
end

fprintf('\n=== RUNNING FULL DIAGNOSTIC: 40 nodes, λ=1, M=1, q=1, random trace ===\n');
cfg = default_lightload_sfcb_config('analysis','delay');
cfg.topology_seed = 42;
rng(12345);
scenario = prepare_scenario_v2(cfg, cfg.topology_seed);

% Generate an arrival trace
tr = generate_arrival_trace(cfg, 1, 1, 12345);

fprintf('  Trace: n_packets=%d, arrival_end=%d us, hard_end=%d us\n', ...
    tr.n_packets, tr.arrival_end_us, tr.hard_end_us);

result = simulate_unslotted_sf_cb(tr, scenario, cfg, 1, 1, 12345);
s = result.summary;
fprintf('  mean_delay_us = %.6f\n', s.mean_delay_us);
fprintf('  q = %.6f\n', s.q);
fprintf('  completion_ratio = %.6f\n', s.completion_ratio);
fprintf('  n_arrived = %d, n_completed = %d\n', s.n_arrived, s.n_completed);
fprintf('  retransmissions = %d\n', s.retransmissions_completed_cohort);
fprintf('  mean_attempts = %.6f\n', s.mean_attempts_completed);

% Check per-packet delay distribution
pkt = result.packet_log;
cohort = pkt.arrival_us >= cfg.warmup_us & pkt.arrival_us < cfg.arrival_end_us;
cohort_comp = cohort & isfinite(pkt.completion_us);
delays = pkt.total_delay_us(cohort_comp);
fprintf('  n_cohort_completed = %d\n', sum(cohort_comp));
fprintf('  min_delay = %.3f, max_delay = %.3f, std_delay = %.3f\n', ...
    min(delays), max(delays), std(delays(~isnan(delays))));
fprintf('  fraction with delay > 325.001 = %.6f\n', mean(delays > 325.001));
