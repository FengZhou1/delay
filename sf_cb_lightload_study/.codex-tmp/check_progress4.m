p = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_partial_analysis.mat');
keys = p.keys_save;
fprintf('Total cells done: %d / 72\n', numel(keys));
fprintf('Last 4 keys:\n');
for k = max(1,numel(keys)-3):numel(keys)
    fprintf('  %s\n', keys{k});
end
rows = p.rows_save;
fprintf('\nLast 2 rows (protocol lambda M q delay completion):\n');
for k = max(1,numel(rows)-1):numel(rows)
    r = rows{k};
    fprintf('  %s lambda=%g M=%d q=%.4g delay=%.1f comp=%.3f\n', r.protocol, r.lambda, r.M, r.best_q, r.delay_us, r.completion_ratio);
end
