t = mtree('C:/Users/Administrator/Documents/delay/simulate_sb_cf_v2.m','-file');
e = find(t.iskind('ERR'));
fprintf('errors: %d\n', numel(e));
for k = 1:numel(e)
    n = e(k);
    fprintf('ERR at node %d: %s\n', n, char(t.select(n).string));
end
