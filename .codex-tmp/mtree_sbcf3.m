t = mtree('C:/Users/Administrator/Documents/delay/simulate_sb_cf_v2.m','-file');
if t.isempty, disp('empty'); end
% list all nodes of kind FUNCTION and check ends
roots = t.root;
idx = find(t.iskind('FUNCTION'));
fprintf('functions: %d\n', numel(idx));
for k = 1:numel(idx)
    fprintf('func %d at line %d\n', k, t.lineno(idx(k)));
end
e = find(t.iskind('ERR'));
fprintf('errors: %d\n', numel(e));
for k = 1:numel(e)
    fprintf('ERR L%d: %s\n', t.lineno(e(k)), t.string(e(k)));
end
