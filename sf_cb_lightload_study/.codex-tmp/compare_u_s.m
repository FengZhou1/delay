d = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/throughput_data.mat');
data = d.data;
fprintf('%-4s %-14s %-14s %-10s %-14s %-14s\n', 'M', 'unsl_q', 'sb_q', 'delta_q', 'unsl_tput', 'sb_tput');
for k = 1:numel(data.results)
    r = data.results(k);
    if strcmp(r.protocol,'unslotted')
        uq(r.M) = r.best_q; ut(r.M) = r.throughput;
    elseif strcmp(r.protocol,'sb_cb')
        sq(r.M) = r.best_q; st(r.M) = r.throughput;
    end
end
for M = 1:6
    fprintf('%-4d %-14.5g %-14.5g %-10.3g %-14.4f %-14.4f\n', M, uq(M), sq(M), abs(uq(M)-sq(M)), ut(M), st(M));
end
