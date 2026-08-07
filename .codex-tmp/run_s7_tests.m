cd('C:/Users/Administrator/Documents/delay');
addpath(pwd);
fns = {'test_s7_exact_timing','test_s7_collision_does_not_freeze_bystander'};
pc = 0; fc = 0;
for i = 1:numel(fns)
    try
        feval(fns{i});
        fprintf('PASS %s\n', fns{i}); pc = pc + 1;
    catch ME
        fprintf('FAIL %s: %s\n', fns{i}, ME.message); fc = fc + 1;
    end
end
fprintf('S7: %d pass, %d fail\n', pc, fc);
