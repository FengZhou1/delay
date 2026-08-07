t = mtree('C:/Users/Administrator/Documents/delay/simulate_sb_cf_v2.m','-file');
[l,c] = lint(t,0);
fprintf('num lints: %d\n', numel(l));
for k = 1:min(10,numel(l))
    fprintf('L%d: %s\n', l(k), char(c(k)));
end
dump(t);
