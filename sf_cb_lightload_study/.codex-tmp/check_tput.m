p = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/throughput_partial_analysis.mat');
keys = p.keys_save;
fprintf('Throughput cells done: %d / 24 (6 M x 4 protocols)\n', numel(keys));
for k = 1:numel(keys)
    fprintf('  %s\n', keys{k});
end
rows = p.rows_save;
if numel(rows) > 0
    fprintf('\nLast 2 rows (protocol M q throughput):\n');
    for k = max(1,numel(rows)-1):numel(rows)
        r = rows{k};
        fprintf('  %s M=%d q=%.4g throughput=%.4f\n', r.protocol, r.M, r.best_q, r.throughput);
    end
end
