cd('C:/Users/Administrator/Documents/delay');
addpath(pwd);
r1 = run_v2_tests();
fprintf('V2: %d/%d passed\n', r1.n_passed, numel(r1.names));
r2 = run_saturation_tests();
fprintf('SAT: %d/%d passed\n', sum([r2.passed]), height(r2));
