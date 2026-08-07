d = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_data.mat');
data = d.data;
fprintf('Delay results: %d rows\n', numel(data.results));
fprintf('\n%-12s %5s %4s %10s %12s %10s\n', 'protocol','lambda','M','best_q','delay_us','completion');
for k = 1:numel(data.results)
    r = data.results(k);
    fprintf('%-12s %5g %4d %10.4g %12.1f %10.3f\n', r.protocol, r.lambda, r.M, r.best_q, r.delay_us, r.completion_ratio);
end
