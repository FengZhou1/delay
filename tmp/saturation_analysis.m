% Saturation analysis: compare lambda=5 input load with max throughput

% Load saturation data
sat_dir = '';
d = dir('results_v2/saturation');
for i = 1:length(d)
    if d(i).isdir && contains(d(i).name, '143553')
        sat_dir = fullfile('results_v2/saturation', d(i).name);
    end
end

S = readtable(fullfile(sat_dir, 'saturation_summary.csv'), 'VariableNamingRule', 'preserve');

% Load delay data
D = readtable('results_v2/20260808_194358_8f3976df61f6/summary.csv', 'VariableNamingRule', 'preserve');

% Focus on lambda=5
D5 = D(D.lambda_effective == 5, :);

% For each protocol, get the saturation max throughput for M=1:6
protos = {'sf_cb','sb_cb','sf_cf','sb_cf','unslotted','s7_clean','s7_busy'};
conn_slot_us = 198;  % from config

fprintf('\n');
fprintf('==========================================================================================================================\n');
fprintf('饱和判定分析: 各协议最大吞吐 vs 入=5 input load\n');
fprintf('conn_slot = %d us, 40 nodes\n', conn_slot_us);
fprintf('==========================================================================================================================\n');
fprintf('%-12s %3s %8s %10s %14s %14s %10s %10s\n', ...
    'Protocol','M','off_units','off_ch_frac','sat_max_frac','off_pkt/slot','饱和?','备注');
fprintf('---------------------------------------------------------------------------------------------------------------------------\n');

max_slots_per_sec = 1e6 / conn_slot_us;  % ~5050.5

for p = 1:length(protos)
    proto = protos{p};
    
    % Find saturation data for this protocol
    sat_idx = strcmp(S.protocol, proto);
    sat_Ms = S.effective_M(sat_idx);
    sat_fracs = S.payload_airtime_fraction_mean(sat_idx);
    
    % Find delay data
    del_idx = strcmp(D5.protocol, proto);
    del_Ms = D5.M(del_idx);
    
    for j = 1:length(del_Ms)
        M = del_Ms(j);
        
        % Offered load from delay data
        off_units = D5.normalized_offered_units_s(del_idx);
        off_units = off_units(j);
        off_ch_frac = off_units / max_slots_per_sec;
        
        % Max throughput from saturation (find closest M)
        [~, closest] = min(abs(sat_Ms - M));
        sat_max_frac = sat_fracs(closest);
        
        % Offered in pkt/slot: pkt_system/s / max_slots_per_sec
        off_pkt_per_slot = off_units / (M * max_slots_per_sec);
        
        % Is saturated?
        goodput = D5.normalized_goodput_units_s(del_idx);
        goodput = goodput(j);
        is_sat = off_units > goodput * 1.02;  % 2% tolerance
        stable = D5.stable_fraction(del_idx);
        stable = stable(j);
        
        note = '';
        if isnan(goodput) || isnan(stable)
            note = '无有效数据';
        elseif stable < 0.95
            note = sprintf('不稳定(stable=%.2f)', stable);
        end
        
        fprintf('%-12s %3d %8.1f %10.4f %14.4f %14.6f %10s %10s\n', ...
            proto, M, off_units, off_ch_frac, sat_max_frac, off_pkt_per_slot, ...
            ternary(is_sat,'饱和','不饱和'), note);
    end
    
    % Also print max throughput
    if ~isempty(sat_Ms)
        [max_frac, max_idx] = max(sat_fracs);
        fprintf('  -> Max throughput at M=%.1f: payload_airtime_frac=%.4f, goodput=%.0f units/s\n', ...
            sat_Ms(max_idx), max_frac, sat_fracs(max_idx)*max_slots_per_sec);
    end
    fprintf('\n');
end

function s = ternary(cond, t, f)
    if cond, s = t; else, s = f; end
end
