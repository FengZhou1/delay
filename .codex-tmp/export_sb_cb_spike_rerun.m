repo_dir = fileparts(fileparts(mfilename('fullpath')));
run_dir = fullfile(repo_dir,'results_v2','20260726_191557_a6ccf7195cee');
saved = load(fullfile(run_dir,'checkpoints', ...
    'sb_cb_fixed_packet_lam10_M4.mat'),'condition');
condition = saved.condition;

grid = condition.tuning.grid;
tuning_rows = struct([]);
for i = 1:numel(grid)
    tuning_rows(i).q = grid(i).q; %#ok<SAGROW>
    tuning_rows(i).selected = ...
        abs(grid(i).q-condition.tuning.best_q)<1e-15;
    tuning_rows(i).stable_fraction = grid(i).stable_fraction;
    tuning_rows(i).mean_delay_us = grid(i).mean_delay_us;
    tuning_rows(i).se_delay_us = grid(i).se_delay_us;
    tuning_rows(i).mean_p95_us = grid(i).mean_p95_us;
    tuning_rows(i).mean_collision_waste_us = ...
        grid(i).mean_collision_waste_us;
    tuning_rows(i).rate_screen_rejected_fraction = ...
        grid(i).rate_screen_rejected_fraction;
end

eval_rows = struct([]);
for i = 1:numel(condition.evaluation)
    s = condition.evaluation{i}.summary;
    d = condition.evaluation{i}.diagnostics;
    eval_rows(i).run = i; %#ok<SAGROW>
    eval_rows(i).q = s.q;
    eval_rows(i).seed = scalar_or_nan(d,'seed');
    eval_rows(i).stable = s.stable;
    eval_rows(i).arrival_rate_pkt_s = s.arrival_rate_pkt_s;
    eval_rows(i).goodput_pkt_s = s.goodput_pkt_s;
    eval_rows(i).completion_ratio = s.completion_ratio;
    eval_rows(i).final_backlog = s.final_backlog;
    eval_rows(i).backlog_slope_pkt_s = s.backlog_slope_pkt_s;
    eval_rows(i).mean_delay_us = s.mean_delay_us;
    eval_rows(i).p50_delay_us = s.p50_delay_us;
    eval_rows(i).p95_delay_us = s.p95_delay_us;
    eval_rows(i).p99_delay_us = s.p99_delay_us;
    eval_rows(i).mean_queue_delay_us = s.mean_queue_delay_us;
    eval_rows(i).mean_access_delay_us = s.mean_access_delay_us;
    eval_rows(i).mean_probability_wait_us = s.mean_probability_wait_us;
    eval_rows(i).mean_busy_nav_wait_us = s.mean_busy_nav_wait_us;
    eval_rows(i).mean_collision_delay_us = s.mean_collision_delay_us;
    eval_rows(i).little_relative_error = s.little_relative_error;
    eval_rows(i).mean_attempts_completed = s.mean_attempts_completed;
    names = {'rts_attempts','rts_fail_total','rts_fail_ap_busy_start', ...
        'rts_fail_sinr','rts_response_timeouts','late_start_handshake', ...
        'late_start_data','nav_fail','nav_protected_violations', ...
        'data_attempts','data_success','data_fail','data_fail_sinr', ...
        'data_fail_cts','data_collision_events','data_collision_us', ...
        'cca_raw_miss_rate','cca_eligible_fnr', ...
        'harmful_missed_opportunities','reservation_waste_us'};
    for j = 1:numel(names)
        eval_rows(i).(names{j}) = scalar_or_nan(d,names{j});
    end
end

tuning_table = struct2table(tuning_rows);
evaluation_table = struct2table(eval_rows);
writetable(tuning_table,fullfile(run_dir,'sb_cb_M4_tuning_grid.csv'));
writetable(evaluation_table,fullfile(run_dir,'sb_cb_M4_evaluation_runs.csv'));

row = condition.row;
fprintf(['ROW q=%.9g stable=%.6g delay=%.9g p95=%.9g ', ...
    'arrival=%.9g goodput=%.9g backlog=%.9g slope=%.9g little=%.9g\n'], ...
    row.best_q,row.stable_fraction,row.mean_delay_us,row.p95_delay_us, ...
    row.arrival_rate_pkt_s,row.goodput_pkt_s,row.final_backlog, ...
    row.backlog_slope_pkt_s,row.little_relative_error);
fprintf('TUNING_ROWS=%d EVAL_ROWS=%d\n', ...
    height(tuning_table),height(evaluation_table));

function value = scalar_or_nan(source,name)
    if isfield(source,name) && isnumeric(source.(name)) && ...
            isscalar(source.(name))
        value = double(source.(name));
    else
        value = NaN;
    end
end
