c = checkcode('simulate_sb_cb_v2.m','-struct');
fprintf('num issues: %d\n', numel(c));
parse_errors = 0;
for i = 1:numel(c)
    m = char(c(i).message);
    if contains(lower(m),'parse') || contains(lower(m),'syntax') || contains(lower(m),'??')
        parse_errors = parse_errors + 1;
        fprintf('PARSE L%d: %s\n', c(i).line, m);
    end
end
fprintf('potential parse issues: %d\n', parse_errors);
