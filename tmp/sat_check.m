function sat_check()
sat_dir = dir('results_v2/saturation/20260808_143553_*');
sat_dir = fullfile('results_v2/saturation', sat_dir(1).name);
S = readtable(fullfile(sat_dir, 'saturation_summary.csv'), 'VariableNamingRule', 'preserve');
D = readtable('results_v2/20260808_194358_8f3976df61f6/summary.csv', 'VariableNamingRule', 'preserve');
D5 = D(D.lambda_effective == 5, :);
conn = 198; max_units = 1e6/conn;
protos = {'sf_cb','sb_cb','sf_cf','sb_cf','unslotted','s7_clean','s7_busy'};

fprintf('\n===== SATURATION ANALYSIS: lambda=5, 40 nodes, conn_slot=%d us =====\n\n', conn);
fprintf('%-12s %3s %8s %8s %12s %10s %10s %12s %s\n', ...
    'Protocol','M','off_frac','sat_max','off_units','sat_max_u','goodput_u','stable','Verdict');
fprintf('%s\n', repmat('-',1,100));

for p = 1:length(protos)
    pr = protos{p};
    si = strcmp(S.protocol, pr);
    sM = S.effective_M(si);
    sF = S.payload_airtime_fraction_mean(si);
    di = strcmp(D5.protocol, pr);
    dM = D5.M(di);
    
    for j = 1:length(dM)
        M = dM(j);
        [~, ci] = min(abs(sM - M));
        satF = sF(ci);
        off_units = D5.normalized_offered_units_s(di); off_units = off_units(j);
        offF = off_units / max_units;
        gp = D5.normalized_goodput_units_s(di); gp = gp(j);
        st = D5.stable_fraction(di); st = st(j);
        sat_max_u = satF * max_units;
        
        if offF > satF * 1.02
            judge = 'GENUINELY SATURATED';
        elseif st < 0.95
            judge = 'q-tune failed (NOT saturated)';
        else
            judge = 'OK';
        end
        fprintf('%-12s %3d %8.4f %8.4f %12.1f %10.0f %10.0f %12.2f %s\n', ...
            pr, M, offF, satF, off_units, sat_max_u, gp, st, judge);
    end
    fprintf('\n');
end

fprintf('\n--- KEY FINDINGS ---\n');
fprintf('off_frac = offered channel fraction (lambda*40*M*conn_slot/1e6)\n');
fprintf('sat_max = max achievable channel fraction (from saturation runs)\n');
fprintf('Verdict: "GENUINELY SATURATED" = offered > max capacity, impossible to serve\n');
fprintf('         "q-tune failed" = offered < max capacity but q-tuning did not find stable q\n');
end
