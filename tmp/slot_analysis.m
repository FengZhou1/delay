function slot_analysis()
sat_dir = dir('results_v2/saturation/20260808_143553_*');
sat_dir = fullfile('results_v2/saturation', sat_dir(1).name);
S = readtable(fullfile(sat_dir, 'saturation_summary.csv'), 'VariableNamingRule', 'preserve');
D = readtable('results_v2/20260808_194358_8f3976df61f6/summary.csv', 'VariableNamingRule', 'preserve');
D5 = D(D.lambda_effective == 5, :);

conn = 198; RTS = 18; CTS = 18; SIFS = 18; DIFS_us = 36; n_sec = 8;

% success_cycle = overhead + M*conn
% sf_cb:    conn_slot(198) + M*conn = 198+M*198
% sf_cf:    conn_slot(198) + M*conn = 198+M*198
% sb_cb:    DIFS+RTS+SIFS+CTS_sweep+SIFS + M*conn = 36+18+18+144+18+M*198 = 234+M*198
% sb_cf:    DIFS+RTS+SIFS + M*conn = 36+18+18+M*198 = 72+M*198
% unslotted:RTS+SIFS+CTS_sweep+SIFS + M*conn = 18+18+144+18+M*198 = 198+M*198
% s7_*:     conn_slot(198) + M*conn = 198+M*198

overhead = struct('sf_cb',198,'sf_cf',198,'sb_cb',234,'sb_cf',72,'unslotted',198,'s7_clean',198,'s7_busy',198);
protos = {'sf_cb','sb_cb','sf_cf','sb_cf','unslotted','s7_clean','s7_busy'};

fprintf('\n===== PROTOCOL-SPECIFIC SATURATION CHECK (9us integer timing) =====\n');
fprintf('Timing: RTS=18 CTS=18 SIFS=18 DIFS=36 conn_slot=198 us\n');
fprintf('lambda=5*40=200 pkt/s system offered\n\n');

fprintf('%-10s %3s %6s %8s %10s %10s %8s %8s %8s %s\n', ...
    'Protocol','M','OH_us','succ_us','off','max_cap','off/suc','max/suc','stable','Verdict');
fprintf('%s\n', repmat('-',1,98));

for p = 1:length(protos)
    pr = protos{p};
    oh = overhead.(pr);
    si = strcmp(S.protocol, pr); sM = S.effective_M(si); sF = S.payload_airtime_fraction_mean(si);
    di = strcmp(D5.protocol, pr); dM = D5.M(di);
    
    for j = 1:length(dM)
        M = dM(j);
        succ = oh + M*conn;
        [~, ci] = min(abs(sM - M));
        max_pkt_s = sF(ci) * 1e6 / (M * conn);
        off_per_succ = 200 * succ / 1e6;
        max_per_succ = sF(ci) * succ / (M * conn);
        st = D5.stable_fraction(di); st = st(j);
        gp = D5.normalized_goodput_units_s(di); gp = gp(j);
        if ~isnan(gp), actual = gp * 1e6 / (M * conn); else actual = NaN; end

        if 200 > max_pkt_s * 1.02
            judge = 'TRUE SAT';
        elseif st < 0.95
            judge = 'Q-FAIL';
        else
            judge = 'OK';
        end
        fprintf('%-10s %3d %6d %8d %10.1f %10.1f %8.4f %8.4f %8.2f %s', ...
            pr, M, oh, succ, 200.0, max_pkt_s, off_per_succ, max_per_succ, st, judge);
        if ~isnan(actual), fprintf(' (act=%.0f)', actual); end
        fprintf('\n');
    end
    fprintf('\n');
end
fprintf('off = system offered 200 pkt/s\n');
fprintf('max_cap = max pkts/s protocol can serve at this M (from saturation)\n');
fprintf('off/suc = offered pkts per success-cycle-duration\n');
fprintf('max/suc = max pkts per success-cycle-duration\n');
fprintf('TRUE SAT = offered > max capacity\n');
fprintf('Q-FAIL = capacity suffices but q-tuning failed\n');
end
