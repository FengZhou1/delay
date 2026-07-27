script_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(script_dir);
result_dir = fullfile(root_dir,'results_v2','20260727_171921_656dc48da53d');
checkpoint_dir = fullfile(result_dir,'checkpoints');
out_dir = fullfile(root_dir,'.codex-tmp','latest_delay_audit');
if ~isfolder(out_dir)
    mkdir(out_dir);
end

c = load(fullfile(result_dir,'config.mat'),'cfg');
cfg = c.cfg;
files = dir(fullfile(checkpoint_dir,'*.mat'));

condition_tag = strings(0,1);
phase = strings(0,1);
q = zeros(0,1);
grid_stable_fraction = zeros(0,1);
mean_delay_us = zeros(0,1);
mean_goodput_pkt_s = zeros(0,1);
mean_backlog_slope_pkt_s = zeros(0,1);
rate_screen_rejected_fraction = zeros(0,1);
run_index = zeros(0,1);
run_stable = false(0,1);
n_arrived = zeros(0,1);
n_departures_window = zeros(0,1);
n_censored = zeros(0,1);
final_backlog = zeros(0,1);
arrival_rate_pkt_s = zeros(0,1);
goodput_pkt_s = zeros(0,1);
rate_relative_error = zeros(0,1);
backlog_slope_pkt_s = zeros(0,1);
completion_ratio = zeros(0,1);
tuning_rate_screen_rejected = false(0,1);
failure_reason = strings(0,1);

for fi = 1:numel(files)
    loaded = load(fullfile(files(fi).folder,files(fi).name),'condition');
    condition = loaded.condition;
    grids = {condition.tuning.coarse_grid,condition.tuning.refined_grid};
    phase_names = ["coarse","refined"];
    for pi = 1:numel(grids)
        grid = grids{pi};
        for gi = 1:numel(grid)
            runs = grid(gi).run_summaries;
            for ri = 1:numel(runs)
                s = runs(ri);
                condition_tag(end+1,1) = erase(string(files(fi).name),".mat"); %#ok<SAGROW>
                phase(end+1,1) = phase_names(pi); %#ok<SAGROW>
                q(end+1,1) = grid(gi).q; %#ok<SAGROW>
                grid_stable_fraction(end+1,1) = grid(gi).stable_fraction; %#ok<SAGROW>
                mean_delay_us(end+1,1) = grid(gi).mean_delay_us; %#ok<SAGROW>
                mean_goodput_pkt_s(end+1,1) = grid(gi).mean_goodput_pkt_s; %#ok<SAGROW>
                mean_backlog_slope_pkt_s(end+1,1) = grid(gi).mean_backlog_slope_pkt_s; %#ok<SAGROW>
                rate_screen_rejected_fraction(end+1,1) = ...
                    grid(gi).rate_screen_rejected_fraction; %#ok<SAGROW>
                run_index(end+1,1) = ri; %#ok<SAGROW>
                run_stable(end+1,1) = logical(s.stable); %#ok<SAGROW>
                n_arrived(end+1,1) = s.n_arrived; %#ok<SAGROW>
                n_departures_window(end+1,1) = s.n_departures_window; %#ok<SAGROW>
                n_censored(end+1,1) = s.n_censored; %#ok<SAGROW>
                final_backlog(end+1,1) = s.final_backlog; %#ok<SAGROW>
                arrival_rate_pkt_s(end+1,1) = s.arrival_rate_pkt_s; %#ok<SAGROW>
                goodput_pkt_s(end+1,1) = s.goodput_pkt_s; %#ok<SAGROW>
                rate_relative_error(end+1,1) = abs(s.goodput_pkt_s - ...
                    s.arrival_rate_pkt_s)/max(s.arrival_rate_pkt_s,1); %#ok<SAGROW>
                backlog_slope_pkt_s(end+1,1) = s.backlog_slope_pkt_s; %#ok<SAGROW>
                completion_ratio(end+1,1) = s.completion_ratio; %#ok<SAGROW>
                tuning_rate_screen_rejected(end+1,1) = ...
                    logical(s.tuning_rate_screen_rejected); %#ok<SAGROW>

                reasons = strings(0,1);
                if s.n_arrived <= 0 || s.n_completed <= 0
                    reasons(end+1) = "empty"; %#ok<SAGROW>
                end
                if rate_relative_error(end) > cfg.stability_rate_tolerance
                    reasons(end+1) = "rate"; %#ok<SAGROW>
                end
                if s.n_censored > floor(cfg.stability_censor_tolerance*s.n_arrived)
                    reasons(end+1) = "censor"; %#ok<SAGROW>
                end
                slope_tol = max(1,cfg.stability_slope_fraction* ...
                    max(s.arrival_rate_pkt_s,1));
                if cfg.stability_require_slope && ...
                        (~isfinite(s.backlog_slope_pkt_s) || ...
                         s.backlog_slope_pkt_s > slope_tol)
                    reasons(end+1) = "slope"; %#ok<SAGROW>
                end
                if isempty(reasons)
                    failure_reason(end+1,1) = "stable"; %#ok<SAGROW>
                else
                    failure_reason(end+1,1) = join(reasons,"+"); %#ok<SAGROW>
                end
            end
        end
    end
end

audit = table(condition_tag,phase,q,grid_stable_fraction,mean_delay_us, ...
    mean_goodput_pkt_s,mean_backlog_slope_pkt_s, ...
    rate_screen_rejected_fraction,run_index,run_stable,n_arrived, ...
    n_departures_window,n_censored,final_backlog,arrival_rate_pkt_s, ...
    goodput_pkt_s,rate_relative_error,backlog_slope_pkt_s,completion_ratio, ...
    tuning_rate_screen_rejected,failure_reason);
writetable(audit,fullfile(out_dir,'q_run_audit.csv'));

summary = readtable(fullfile(result_dir,'summary.csv'), ...
    'VariableNamingRule','preserve');
unstable = summary(double(summary.stable_fraction)<1-1e-12,:);
writetable(unstable,fullfile(out_dir,'unstable_summary.csv'));

fprintf('Audit rows: %d\n',height(audit));
fprintf('Non-fully-stable conditions: %d/%d\n',height(unstable),height(summary));
fprintf('Audit output: %s\n',out_dir);
