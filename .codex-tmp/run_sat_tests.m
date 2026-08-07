cd('C:/Users/Administrator/Documents/delay');
addpath(pwd);
try
    run_saturation_tests
    fprintf('SAT TESTS PASSED\n');
catch ME
    fprintf('SAT TESTS FAILED: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
