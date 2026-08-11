d = 'results_v2/20260811_004855_3e6f919c7b60/checkpoints';
fs = dir(fullfile(d, '*.mat'));
rows = {};
for i = 1:length(fs)
    try
        c = load(fullfile(d, fs(i).name));
        row = c.condition.row;
        rows{end+1} = [char(row.protocol), row.lambda_effective, row.M, ...
            row.q_validation_passed, row.mean_delay_us, row.best_q, row.completion_ratio];
    catch
    end
end
for i = 1:length(rows)
    r = rows{i};
    fprintf('%-12s lam=%-4d M=%-3d q_ok=%-5d delay=%-10.1f best_q=%-6.4f compl=%.3f\n', ...
        r{1}, r{2}, r{3}, r{4}, r{5}, r{6}, r{7});
end
