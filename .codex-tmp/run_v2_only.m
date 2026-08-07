cd('C:/Users/Administrator/Documents/delay');
addpath(pwd);
try
    r = run_v2_tests();
    fprintf('V2: %d/%d passed\n', r.n_passed, numel(r.names));
catch ME
    fprintf('V2 FAILED: %s\n', ME.message);
end
