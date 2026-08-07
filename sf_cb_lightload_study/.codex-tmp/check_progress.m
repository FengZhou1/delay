p = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_partial_analysis.mat');
keys = p.keys_save;
fprintf('Total cells done: %d (expected 3*6*4 = 72)\n', numel(keys));
for k = 1:numel(keys)
    fprintf('  %s\n', keys{k});
end
rows = p.rows_save;
if numel(rows) > 0
    fprintf('\nSample row: protocol=%s lambda=%g M=%d best_q=%g delay=%.1f us completion=%.3f\n', ...
        rows{1}.protocol, rows{1}.lambda, rows{1}.M, rows{1}.best_q, rows{1}.delay_us, rows{1}.completion_ratio);
end
