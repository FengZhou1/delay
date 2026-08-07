c = checkcode('simulate_s7_v2.m','-struct');
fprintf('issues: %d\n', numel(c));
pe = 0;
for i=1:numel(c)
  m = char(c(i).message);
  if contains(lower(m),'parse')||contains(lower(m),'syntax')||contains(lower(m),'end')||contains(lower(m),'??')
    pe=pe+1; fprintf('P L%d: %s\n', c(i).line, m);
  end
end
fprintf('parse issues: %d\n', pe);
