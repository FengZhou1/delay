c = checkcode('simulate_sb_cb_v2.m');
fprintf('total: %d\n', numel(c));
for i = 1:min(40,numel(c))
    fprintf('L%d C%d: %s\n', c(i).line, c(i).column, c(i).message);
end
