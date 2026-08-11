d = 'results_v2/20260811_004855_3e6f919c7b60/checkpoints';
fs = dir(fullfile(d, '*.mat'));
n = length(fs);
prot = cell(n,1); lam = zeros(n,1); Mv = zeros(n,1);
q_ok = false(n,1); delay = nan(n,1); bestq = nan(n,1); compl = nan(n,1);
for i = 1:n
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        prot{i} = char(row.protocol);
        lam(i) = row.lambda_effective;
        Mv(i) = row.M;
        q_ok(i) = row.q_validation_passed;
        if q_ok(i) && isfinite(row.mean_delay_us)
            delay(i) = row.mean_delay_us / 1e3;
            bestq(i) = row.best_q;
            compl(i) = row.completion_ratio;
        end
    catch
    end
end
T = table(prot, lam, Mv, q_ok, delay, bestq, compl);
T = sortrows(T, {'prot','lam','Mv'});
writetable(T, 'tmp_full_check.csv');
fprintf('Written tmp_full_check.csv, %d rows\n', height(T));
