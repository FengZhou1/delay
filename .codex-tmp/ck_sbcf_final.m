t = mtree('C:/Users/Administrator/Documents/delay/simulate_sb_cf_v2.m','-file');
e = find(t.iskind('ERR'));
fprintf('mtree errors: %d\n', numel(e));
for k = 1:numel(e)
    n = e(k);
    fprintf('ERR: %s\n', char(t.select(n).string));
end
