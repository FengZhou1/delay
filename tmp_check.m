d = 'results_v2/20260811_004855_3e6f919c7b60/checkpoints';
fs = dir(fullfile(d, '*.mat'));
fprintf('%-12s %5s %4s %10s %10s %12s\n', 'Protocol', 'lam', 'M', 'delay_ms', 'best_q', 'q_passed');
fprintf('%s\n', repmat('-', 1, 60));
for i = 1:length(fs)
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        lam = row.lambda_effective;
        M = row.M;
        prot = char(row.protocol);
        q_ok = row.q_validation_passed;
        if q_ok && isfinite(row.mean_delay_us)
            dly = row.mean_delay_us / 1e3;
            fprintf('%-12s %5d %4d %10.3f %10.4f %12s\n', prot, lam, M, dly, row.best_q, 'OK');
        else
            fprintf('%-12s %5d %4d %10s %10s %12s\n', prot, lam, M, 'FAIL', '-', 'FAIL');
        end
    catch
    end
end
