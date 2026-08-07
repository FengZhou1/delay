t = mtree('C:/Users/Administrator/Documents/delay/simulate_sb_cf_v2.m','-file');
fprintf('valid: %d\n', t.valid);
if ~t.valid
    [l,c] = t.lint(0);
    % try to print lints
    for k = 1:numel(l)
        fprintf('lint L%d: %s\n', l(k), '');
    end
end
