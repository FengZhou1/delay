%% R10 CTS mode 4 (winner-directed CTS) in a second MATLAB session, 1 worker.
%  Use this while another R10 run already owns a 4-worker pool.
%  R10_N_WORKERS is runtime-only: experiment_config_hash strips n_workers and
%  parallel, so the run identity, its output directory and its resume state are
%  exactly the same as a normal 4-worker run.
%
%  Just run this script in the new MATLAB session (or paste it in the Command
%  Window). Interrupting and re-running it resumes from the checkpoints.

project_root = 'C:\Users\Administrator\Documents\delay';
cd(project_root);

output_root = fullfile(project_root,'R10_results','20260914_201159');
assert(isfolder(output_root),'Missing run directory: %s',output_root);

% mode 4 reuses result1 (sf_cf / sb_cf / s7_an) of the same run directory.
for pkt = [162.5 650]
    ref = fullfile(output_root,'result1',sprintf('summary_pkt%g.csv',pkt));
    assert(isfile(ref),'Missing reference summary: %s',ref);
end

setenv('R10_N_WORKERS','1');    % one-worker pool for this session
% setenv('R10_PARALLEL','0');   % uncomment instead for fully serial (no parpool at all)

fprintf('mode 4 -> %s\n',output_root);
fprintf('workers = %s (parallel = %s)\n', ...
    getenv('R10_N_WORKERS'),getenv('R10_PARALLEL'));

run_R10_cts_mode(4,'txop',{},output_root);      % both packet durations