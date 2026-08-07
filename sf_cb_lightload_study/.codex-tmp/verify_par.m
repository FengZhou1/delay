
function verify_par()
disp('checking parpool...');
if isempty(gcp('nocreate'))
    try
        p = parpool('local', 4);
        fprintf('parpool started with %d workers\n', p.NumWorkers);
    catch ME
        fprintf('parpool FAILED: %s\n', ME.message);
        return;
    end
end
% test parfor
n = 8;
out = zeros(n,1);
parfor i = 1:n
    out(i) = i^2;
end
fprintf('parfor OK, sum=%g\n', sum(out));
delete(gcp('nocreate'));
end
