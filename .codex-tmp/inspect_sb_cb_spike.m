repo_dir = fileparts(fileparts(mfilename('fullpath')));
checkpoint_dir = fullfile(repo_dir,'results_v2', ...
    '20260726_181043_20f5418a8885','combined_view','checkpoints');

for M = [3 4 5]
    checkpoint = fullfile(checkpoint_dir, ...
        sprintf('sb_cb_fixed_packet_lam10_M%d.mat',M));
    saved = load(checkpoint,'condition');
    condition = saved.condition;
    row = condition.row;
    fprintf(['ROW M=%d q=%.9g stable=%.6g delay=%.9g p95=%.9g ', ...
        'arrival=%.9g goodput=%.9g backlog=%.9g slope=%.9g\n'], ...
        M,row.best_q,row.stable_fraction,row.mean_delay_us,row.p95_delay_us, ...
        row.arrival_rate_pkt_s,row.goodput_pkt_s,row.final_backlog, ...
        row.backlog_slope_pkt_s);
    fprintf('EVAL_RUNS M=%d n=%d\n',M,numel(condition.evaluation));
end

saved = load(fullfile(checkpoint_dir, ...
    'sb_cb_fixed_packet_lam10_M4.mat'),'condition');
condition = saved.condition;
disp('TUNING_FIELDS');
disp(fieldnames(condition.tuning));
disp('GRID_FIELDS');
disp(fieldnames(condition.tuning.grid));
disp('SUMMARY_FIELDS');
disp(fieldnames(condition.evaluation{1}.summary));
disp('DIAGNOSTIC_FIELDS');
disp(fieldnames(condition.evaluation{1}.diagnostics));
