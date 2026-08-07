c = checkcode('simulate_sb_cf_v2.m','-struct');
fprintf('num issues: %d\n', numel(c));
for i = 1:min(25,numel(c))
    fprintf('L%d C%d: %s\n', c(i).line, c(i).column, char(c(i).message));
end
