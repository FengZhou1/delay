try
    c = checkcode('simulate_sb_cb_v2.m','-struct');
    fprintf('num issues: %d\n', numel(c));
    parse_errors = 0;
    for i = 1:numel(c)
        m = c(i).message;
        if contains(lower(char(m)), 'parse') || contains(lower(char(m)), 'syntax') || contains(lower(char(m)), 'end') || contains(lower(char(m)), '??')
            parse_errors = parse_errors + 1;
            fprintf('PARSE L%d: %s\n', c(i).line, char(m));
        end
    end
    fprintf('potential parse issues: %d\n', parse_errors);
catch ME
    fprintf('ERROR: %s\n', ME.message);
end
