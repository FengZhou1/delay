results_dir = 'results_v2/20260808_194358_8f3976df61f6';
T = readtable(fullfile(results_dir, 'summary.csv'), 'VariableNamingRule', 'preserve');

% 找出所有NaN/异常的时延结果
fprintf('=== 时延异常点 ===\n');
bad = isnan(T.mean_delay_us) | isnan(T.stable_fraction) | T.stable_fraction < 0.9;
fprintf('Protocol,lambda,M,Tp,best_q,stable_frac,mean_delay\n');
for i = find(bad)'
    fprintf('%s,lambda=%d,M=%d,Tp=%d,q=%.4f,stable=%.2f,delay=%s\n', ...
        T.protocol{i}, T.lambda_effective(i), T.M(i), T.Tp_us(i), ...
        T.best_q(i), T.stable_fraction(i), num2str(T.mean_delay_us(i)));
end

% 找出完成率低的结果
fprintf('\n=== 完成率异常点 ===\n');
low = T.completion_ratio < 0.95 & ~isnan(T.completion_ratio);
for i = find(low)'
    fprintf('%s,lambda=%d,M=%d,Tp=%d,q=%.4f,comp=%.4f,delay=%s\n', ...
        T.protocol{i}, T.lambda_effective(i), T.M(i), T.Tp_us(i), ...
        T.best_q(i), T.completion_ratio(i), num2str(T.mean_delay_us(i)));
end

% 统计各协议完成情况
fprintf('\n=== 各协议统计 ===\n');
protos = unique(T.protocol);
for p = 1:length(protos)
    idx = strcmp(T.protocol, protos{p});
    n = sum(idx);
    n_good = sum(idx & ~isnan(T.mean_delay_us) & T.stable_fraction >= 0.9);
    fprintf('%s: %d/%d good, %d missing/bad\n', protos{p}, n_good, n, n-n_good);
end

% 找validation_failed的
fprintf('\n=== Validation Failed ===\n');
vf = strcmp(T.q_selection_mode, 'validation_failed');
for i = find(vf)'
    fprintf('%s, lambda=%d, M=%d, Tp=%d, q=%.4f\n', ...
        T.protocol{i}, T.lambda_effective(i), T.M(i), T.Tp_us(i), T.best_q(i));
end

% no_stable_q
fprintf('\n=== No Stable Q ===\n');
ns = strcmp(T.q_selection_mode, 'no_stable_q');
for i = find(ns)'
    fprintf('%s, lambda=%d, M=%d, Tp=%d, q=%.4f\n', ...
        T.protocol{i}, T.lambda_effective(i), T.M(i), T.Tp_us(i), T.best_q(i));
end
