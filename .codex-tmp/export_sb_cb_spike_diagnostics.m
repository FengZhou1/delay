repo_dir = fileparts(fileparts(mfilename('fullpath')));
checkpoint_dir = fullfile(repo_dir,'results_v2', ...
    '20260726_181043_20f5418a8885','combined_view','checkpoints');
output_dir = fullfile(repo_dir,'results_v2', ...
    '20260726_181043_20f5418a8885','sb_cb_lam10_M4_diagnostic');
if ~isfolder(output_dir), mkdir(output_dir); end

tuning_rows = struct([]);
eval_rows = struct([]);
ti = 0;
ei = 0;
for M = [3 4 5]
    saved = load(fullfile(checkpoint_dir, ...
        sprintf('sb_cb_fixed_packet_lam10_M%d.mat',M)),'condition');
    condition = saved.condition;
    grid = condition.tuning.grid;
    for gi = 1:numel(grid)
        ti = ti + 1;
        tuning_rows(ti).M = M; %#ok<SAGROW>
        tuning_rows(ti).q = grid(gi).q;
        tuning_rows(ti).mean_delay_us = grid(gi).mean_delay_us;
        tuning_rows(ti).se_delay_us = grid(gi).se_delay_us;
        tuning_rows(ti).mean_p95_us = grid(gi).mean_p95_us;
        tuning_rows(ti).stable_fraction = grid(gi).stable_fraction;
        tuning_rows(ti).mean_collision_waste_us = ...
            grid(gi).mean_collision_waste_us;
        tuning_rows(ti).rate_screen_rejected_fraction = ...
            grid(gi).rate_screen_rejected_fraction;
        tuning_rows(ti).selected = ...
            abs(grid(gi).q-condition.tuning.best_q)<1e-15;
    end

    for ri = 1:numel(condition.evaluation)
        result = condition.evaluation{ri};
        s = result.summary;
        d = result.diagnostics;
        ei = ei + 1;
        eval_rows(ei).M = M; %#ok<SAGROW>
        eval_rows(ei).run = ri;
        eval_rows(ei).q = s.q;
        eval_rows(ei).seed = scalar_or_nan(d,'seed');
        eval_rows(ei).stable = s.stable;
        eval_rows(ei).arrival_rate_pkt_s = s.arrival_rate_pkt_s;
        eval_rows(ei).goodput_pkt_s = s.goodput_pkt_s;
        eval_rows(ei).completion_ratio = s.completion_ratio;
        eval_rows(ei).final_backlog = s.final_backlog;
        eval_rows(ei).backlog_slope_pkt_s = s.backlog_slope_pkt_s;
        eval_rows(ei).mean_delay_us = s.mean_delay_us;
        eval_rows(ei).p50_delay_us = s.p50_delay_us;
        eval_rows(ei).p95_delay_us = s.p95_delay_us;
        eval_rows(ei).p99_delay_us = s.p99_delay_us;
        eval_rows(ei).mean_queue_delay_us = s.mean_queue_delay_us;
        eval_rows(ei).mean_access_delay_us = s.mean_access_delay_us;
        eval_rows(ei).mean_difs_wait_us = s.mean_difs_wait_us;
        eval_rows(ei).mean_probability_wait_us = ...
            s.mean_probability_wait_us;
        eval_rows(ei).mean_busy_nav_wait_us = s.mean_busy_nav_wait_us;
        eval_rows(ei).mean_collision_delay_us = s.mean_collision_delay_us;
        eval_rows(ei).mean_control_delay_us = s.mean_control_delay_us;
        eval_rows(ei).mean_data_delay_us = s.mean_data_delay_us;
        eval_rows(ei).little_relative_error = s.little_relative_error;
        eval_rows(ei).mean_attempts_completed = s.mean_attempts_completed;
        eval_rows(ei).collision_channel_time_us_measure = ...
            s.collision_channel_time_us_measure;
        names = { ...
            'cca_raw_miss_rate','cca_eligible_fnr','cca_eligible_fpr', ...
            'harmful_missed_opportunities','false_alarm_opportunities', ...
            'rts_attempts','rts_simultaneous_attempts', ...
            'rts_simultaneous_events','rts_capture_success', ...
            'rts_fail_total','rts_fail_ap_busy_start', ...
            'rts_fail_ap_became_busy','rts_fail_sinr', ...
            'rts_response_timeouts','late_start_handshake', ...
            'late_start_data','icr_expected','icr_decoded', ...
            'icr_miss_halfduplex','icr_miss_low_sinr', ...
            'icr_miss_timing','nav_expected','nav_set','nav_fail', ...
            'nav_protected_violations','data_attempts','data_success', ...
            'data_fail','data_fail_sinr','data_fail_cts', ...
            'data_collision_events','data_partial_collision_events', ...
            'data_full_collision_events','data_collision_us', ...
            'data_late_rts_interference_ticks','rts_wasted_us', ...
            'reservation_waste_us'};
        for ni = 1:numel(names)
            eval_rows(ei).(names{ni}) = scalar_or_nan(d,names{ni});
        end
    end
end

tuning_table = struct2table(tuning_rows);
eval_table = struct2table(eval_rows);
writetable(tuning_table,fullfile(output_dir,'tuning_grid_M3_M4_M5.csv'));
writetable(eval_table,fullfile(output_dir,'evaluation_runs_M3_M4_M5.csv'));
fprintf('TUNING_ROWS=%d EVAL_ROWS=%d OUTPUT=%s\n', ...
    height(tuning_table),height(eval_table),output_dir);

function value = scalar_or_nan(source,name)
    if isfield(source,name) && isnumeric(source.(name)) && ...
            isscalar(source.(name))
        value = double(source.(name));
    else
        value = NaN;
    end
end
