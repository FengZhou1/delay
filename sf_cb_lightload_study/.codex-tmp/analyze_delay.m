d = load('C:/Users/Administrator/Documents/delay/sf_cb_lightload_study/results/delay_data.mat');
data = d.data;
fprintf('=== ?????? (??????? us) ===\n');
fprintf('%-4s %-10s %8s %8s %8s %8s\n', 'lam','M','sf_cb','batch','unslot','sb_cb');
for li = 1:numel(data.lambda_values)
    lam = data.lambda_values(li);
    for Mi = 1:numel(data.M_values)
        M = data.M_values(Mi);
        row = data.results([data.results.lambda]==lam & [data.results.M]==M);
        vals = containers.Map();
        for k = 1:numel(row)
            vals(row(k).protocol) = row(k).delay_us;
        end
        fprintf('%-4d %-10d %8.1f %8.1f %8.1f %8.1f\n', lam, M, ...
            vals('sf_cb'), vals('batch_clear'), vals('unslotted'), vals('sb_cb'));
    end
    fprintf('\n');
end
fprintf('=== ?? q ?? ===\n');
fprintf('%-4s %-10s %8s %8s %8s %8s\n', 'lam','M','sf_cb','batch','unslot','sb_cb');
for li = 1:numel(data.lambda_values)
    lam = data.lambda_values(li);
    for Mi = 1:numel(data.M_values)
        M = data.M_values(Mi);
        row = data.results([data.results.lambda]==lam & [data.results.M]==M);
        vals = containers.Map();
        for k = 1:numel(row)
            vals(row(k).protocol) = row(k).best_q;
        end
        fprintf('%-4d %-10d %8.3g %8.3g %8.3g %8.3g\n', lam, M, ...
            vals('sf_cb'), vals('batch_clear'), vals('unslotted'), vals('sb_cb'));
    end
    fprintf('\n');
end
