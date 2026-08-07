d = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/throughput_data.mat');
data = d.data;
fprintf('Throughput results: %d rows\n', numel(data.results));
fprintf('\n%-12s %4s %10s %12s %12s\n', 'protocol','M','best_q','throughput','std');
for k = 1:numel(data.results)
    r = data.results(k);
    fprintf('%-12s %4d %10.4g %12.4f %12.4f\n', r.protocol, r.M, r.best_q, r.throughput, r.throughput_std);
end
