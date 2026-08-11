addpath('C:\Users\Administrator\Documents\delay');
addpath('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study');

data = load('C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\results\delay_data.mat');
r = data.data.results;
fprintf('=== ALL RESULTS (delay_data.mat, stored Tp_us shows version) ===\n');
for i = 1:numel(r)
    fprintf('[%2d] %-12s λ=%-4g M=%-2d Tp=%-7.2f best_q=%-8.4f delay=%-10.3f std=%-8.3f cr=%.4f\n', ...
        i, r(i).protocol, r(i).lambda, r(i).M, r(i).Tp_us, r(i).best_q, ...
        r(i).delay_us, r(i).delay_std_us, r(i).completion_ratio);
end
