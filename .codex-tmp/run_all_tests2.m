cd('C:/Users/Administrator/Documents/delay');
addpath(pwd);
try
    run_v2_tests
    fprintf('V2 TESTS PASSED\n');
catch ME
    fprintf('V2 FAILED: %s\n', ME.message);
end
try
    run_saturation_tests
    fprintf('SAT TESTS PASSED\n');
catch ME
    fprintf('SAT FAILED: %s\n', ME.message);
    for k=1:numel(ME.stack)
        fprintf('  at %s line %d\n', ME.stack(k).name, ME.stack(k).line);
    end
end
