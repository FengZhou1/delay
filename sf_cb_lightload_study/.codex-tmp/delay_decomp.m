d = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_data.mat');
data = d.data;
Tp = 164.1; % conn-slot us
fprintf('=== ??????? (us) ===\n');
fprintf('%-10s %10s %10s\n','M','sf_cb/batch','unslotted');
for M = 1:6
    fprintf('%-10d %10.1f %10.1f\n', M, (1+M)*Tp, (1+M)*Tp);
end
fprintf('\n=== ??+???? (?? - ?????) us ===\n');
fprintf('%-4s %-10s %8s %8s %8s %8s\n', 'lam','M','sf_cb','batch','unslot','sb_cb');
for li = 1:numel(data.lambda_values)
    lam = data.lambda_values(li);
    for Mi = 1:numel(data.M_values)
        M = data.M_values(Mi);
        row = data.results([data.results.lambda]==lam & [data.results.M]==M);
        vals = containers.Map();
        for k = 1:numel(row)
            vals(row(k).protocol) = row(k).delay_us - (1+M)*Tp;
        end
        fprintf('%-4d %-10d %8.1f %8.1f %8.1f %8.1f\n', lam, M, ...
            vals('sf_cb'), vals('batch_clear'), vals('unslotted'), vals('sb_cb'));
    end
    fprintf('\n');
end
fprintf('=== ??+?????? (??/??) ===\n');
fprintf('%-4s %-10s %8s %8s %8s %8s\n', 'lam','M','sf_cb','batch','unslot','sb_cb');
for li = 1:numel(data.lambda_values)
    lam = data.lambda_values(li);
    for Mi = 1:numel(data.M_values)
        M = data.M_values(Mi);
        row = data.results([data.results.lambda]==lam & [data.results.M]==M);
        vals = containers.Map();
        for k = 1:numel(row)
            vals(row(k).protocol) = 100*(row(k).delay_us - (1+M)*Tp)/row(k).delay_us;
        end
        fprintf('%-4d %-10d %7.1f%% %7.1f%% %7.1f%% %7.1f%%\n', lam, M, ...
            vals('sf_cb'), vals('batch_clear'), vals('unslotted'), vals('sb_cb'));
    end
    fprintf('\n');
end
