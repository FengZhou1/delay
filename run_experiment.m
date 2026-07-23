function experiment = run_experiment(cfg)
%RUN_EXPERIMENT Tune and evaluate all requested v2 protocol conditions.
% Results are written to a versioned results_v2 directory and never replace
% legacy files in results/.

    if nargin < 1 || isempty(cfg)
        cfg = default_experiment_config('smoke');
    end
    cfg = validate_experiment_config(cfg);
    [cfg_hash,code_fingerprint] = experiment_config_hash(cfg);

    if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
        output_dir = cfg.output_dir;
    else
        run_stamp = char(datetime('now','Format','yyyyMMdd_HHmmss'));
        output_dir = fullfile(cfg.results_root, [run_stamp '_' cfg_hash]);
    end
    if exist(output_dir,'dir')
        entries = dir(output_dir);
        entries = entries(~ismember({entries.name},{'.','..'}));
        if ~isempty(entries)
            manifest_path = fullfile(output_dir,'manifest.json');
            if ~exist(manifest_path,'file')
                error('run_experiment:UnsafeOutputDirectory', ...
                    'Non-empty output_dir has no v2 manifest: %s',output_dir);
            end
            old_manifest = jsondecode(fileread(manifest_path));
            if ~isfield(old_manifest,'config_hash') || ...
                    ~strcmp(char(old_manifest.config_hash),cfg_hash)
                error('run_experiment:ConfigHashMismatch', ...
                    ['Refusing to reuse output_dir with a different config ', ...
                     'hash: %s'],output_dir);
            end
            if ~cfg.resume
                error('run_experiment:ExistingOutputNoResume', ...
                    ['output_dir already contains this experiment. Set ', ...
                     'cfg.resume=true or choose a new directory.']);
            end
        end
    else
        mkdir(output_dir);
    end
    checkpoint_dir = fullfile(output_dir, 'checkpoints');
    if ~exist(checkpoint_dir, 'dir'), mkdir(checkpoint_dir); end

    verification_status = 'UNVERIFIED';
    manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
                             'running',verification_status);
    write_json(fullfile(output_dir, 'manifest.json'), manifest);
    save(fullfile(output_dir, 'config.mat'), 'cfg');

    fprintf('\n=== v2 experiment %s | profile=%s ===\n', cfg_hash, cfg.profile);
    fprintf('Output: %s\n', output_dir);
    started = tic;

    if cfg.run_preflight_tests
        verification_dir=fullfile(output_dir,'verification');
        run_v2_tests(verification_dir);
        validate_aloha_theory_v2(fullfile(verification_dir,'aloha_controlled'));
        verification_status='VERIFIED';
        manifest=make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
                               'running',verification_status);
        write_json(fullfile(output_dir,'manifest.json'),manifest);
    end

    scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
    save(fullfile(output_dir,'scenario.mat'),'scenario','-v7.3');
    maybe_start_pool(cfg);

    condition_rows = struct([]);
    condition_files = {};
    row_idx = 0;
    cond_total = numel(cfg.load_modes)*numel(cfg.lambda_values)* ...
                 numel(cfg.M_values)*numel(cfg.protocols);
    if ~isempty(cfg.condition_filter)
        cond_total = numel(cfg.condition_filter);
    end
    cond_done = 0;

    for li = 1:numel(cfg.load_modes)
        load_mode = cfg.load_modes{li};
        for bi = 1:numel(cfg.lambda_values)
            lambda_base = cfg.lambda_values(bi);
            for mi = 1:numel(cfg.M_values)
                M = cfg.M_values(mi);
                if strcmp(load_mode, 'fixed_payload')
                    lambda_eff = lambda_base / M;
                else
                    lambda_eff = lambda_base;
                end

                for pi = 1:numel(cfg.protocols)
                    protocol = cfg.protocols{pi};
                    tag = sprintf('%s_%s_lam%g_M%d', ...
                                  protocol, load_mode, lambda_base, M);
                    if ~isempty(cfg.condition_filter) && ...
                            ~ismember(tag,cfg.condition_filter)
                        continue;
                    end
                    cond_done = cond_done + 1;
                    checkpoint = fullfile(checkpoint_dir, [tag '.mat']);
                    fprintf('[%d/%d] %s (lambda_eff=%.6g)\n', ...
                            cond_done, cond_total, tag, lambda_eff);
                    condition_started = tic;

                    if cfg.resume && exist(checkpoint, 'file')
                        condition = load_condition_checkpoint(checkpoint, ...
                            cfg_hash,code_fingerprint);
                        fprintf('  resumed checkpoint\n');
                    else
                        tune = tune_condition(protocol, trace_spec(li,bi), ...
                            scenario, cfg, M, lambda_eff, lambda_base, li, bi, pi);
                        if isfinite(tune.best_q)
                            eval_results = evaluate_jobs(protocol, tune.best_q, ...
                                cfg.n_eval_runs, 10000, scenario, cfg, M, ...
                                lambda_eff, lambda_base, li, bi, pi);
                        else
                            eval_results = {};
                        end
                        condition = summarize_condition(protocol, load_mode, ...
                            lambda_base, lambda_eff, M, tune, eval_results);
                        condition.elapsed_s = toc(condition_started);
                        condition.timeout_exceeded = ...
                            condition.elapsed_s > cfg.condition_timeout_s;
                        condition.row.condition_elapsed_s = condition.elapsed_s;
                        condition.row.timeout_exceeded = condition.timeout_exceeded;
                        condition.config_hash=cfg_hash;
                        condition.code_fingerprint=code_fingerprint;
                        save_checkpoint_atomic(checkpoint, condition);
                    end
                    if ~isfield(condition.row,'condition_elapsed_s')
                        condition.row.condition_elapsed_s = NaN;
                        condition.row.timeout_exceeded = false;
                    end
                    if condition.row.timeout_exceeded
                        warning('run_experiment:ConditionTimeout', ...
                            'Condition %s exceeded %.1f seconds.', ...
                            tag,cfg.condition_timeout_s);
                    end

                    row_idx = row_idx + 1;
                    if isempty(condition_rows)
                        condition_rows = condition.row;
                    else
                        condition_rows(row_idx) = condition.row; %#ok<AGROW>
                    end
                    condition_files{row_idx,1} = checkpoint; %#ok<AGROW>
                end
            end
        end
    end

    if isempty(condition_rows)
        summary_table = table();
    else
        summary_table = struct2table(condition_rows);
    end
    writetable(summary_table, fullfile(output_dir, 'summary.csv'));

    extended = struct('cca_ablation',table(),'topology_robustness',table());
    if cfg.run_cca_ablation
        extended.cca_ablation = run_cca_ablation(summary_table,scenario,cfg, ...
            output_dir,cfg_hash,code_fingerprint);
        writetable(extended.cca_ablation, ...
                   fullfile(output_dir,'cca_ablation.csv'));
    end
    if cfg.run_topology_robustness
        extended.topology_robustness = run_topology_robustness( ...
            summary_table,cfg,output_dir,cfg_hash,code_fingerprint);
        writetable(extended.topology_robustness, ...
                   fullfile(output_dir,'topology_robustness.csv'));
    end
    save(fullfile(output_dir, 'experiment.mat'), ...
         'summary_table', 'condition_files', 'extended', 'cfg', '-v7.3');

    manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
                             'completed',verification_status);
    manifest.duration_s = toc(started);
    manifest.n_conditions = height(summary_table);
    write_json(fullfile(output_dir, 'manifest.json'), manifest);

    experiment = struct('output_dir',output_dir, 'config',cfg, ...
                        'summary',summary_table, 'extended',extended, ...
                        'manifest',manifest);
    fprintf('=== completed in %.1f s ===\n', manifest.duration_s);
end

function spec = trace_spec(load_idx, lambda_idx)
    spec = struct('load_idx',load_idx, 'lambda_idx',lambda_idx);
end

function tune = tune_condition(protocol, spec, scenario, cfg, M, ...
                               lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx)
    tune_cfg = cfg;
    tune_cfg.warmup_us = cfg.tune_warmup_us;
    tune_cfg.measure_us = cfg.tune_measure_us;
    if isfield(cfg,'tune_min_expected_arrivals') && ...
            cfg.tune_min_expected_arrivals>0 && lambda_eff>0
        aggregate_rate=cfg.n_nodes*lambda_eff;
        required_us=cfg.tune_min_expected_arrivals/aggregate_rate*1e6;
        if isfield(cfg,'tune_measure_max_us') && ...
                isfinite(cfg.tune_measure_max_us)
            required_us=min(required_us,cfg.tune_measure_max_us);
        end
        required_us=ceil(required_us/cfg.arrival_tick_us)*cfg.arrival_tick_us;
        tune_cfg.measure_us=max(tune_cfg.measure_us,required_us);
    end
    tune_cfg.drain_max_us = cfg.tune_drain_max_us;
    tune_cfg.arrival_end_us = tune_cfg.warmup_us + tune_cfg.measure_us;
    tune_cfg.sim_hard_end_us = tune_cfg.arrival_end_us + ...
                               tune_cfg.drain_max_us;
    tune_cfg.collect_diagnostics = false;
    q_values = condition_q_values(cfg,protocol,lambda_eff,M);
    coarse = evaluate_q_grid(protocol, q_values, cfg.n_tune_runs, 0, ...
        scenario, tune_cfg, M, lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx);
    [best_q, best_index] = select_best_q(coarse, cfg.n_tune_runs);

    refine = struct([]);
    if isfinite(best_q) && cfg.q_refine_points > 0 && numel(q_values) > 1
        lo_idx = max(1, best_index-1);
        hi_idx = min(numel(q_values), best_index+1);
        q_lo = q_values(lo_idx); q_hi = q_values(hi_idx);
        refine_q = unique(logspace(log10(q_lo), log10(q_hi), cfg.q_refine_points));
        refine_q = setdiff(refine_q, q_values);
        if ~isempty(refine_q)
            refine = evaluate_q_grid(protocol, refine_q, cfg.n_tune_runs, 0, ...
                scenario, tune_cfg, M, lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx);
            combined = [coarse(:); refine(:)];
            [~, order] = sort([combined.q]); combined = combined(order);
            [best_q, ~] = select_best_q(combined, cfg.n_tune_runs);
        else
            combined = coarse;
        end
    else
        combined = coarse;
    end

    tune = struct('best_q',best_q, 'grid',combined, ...
                  'coarse_grid',coarse, 'refined_grid',refine, ...
                  'trace_spec',spec);
end

function q_values=condition_q_values(cfg,protocol,lambda_eff,M) %#ok<INUSD>
    q_values=cfg.q_coarse;
    if isfield(cfg,'protocol_q_grids_enabled') && ...
            cfg.protocol_q_grids_enabled
        q_values=cfg.protocol_q_grids.(char(protocol));
    elseif isfield(cfg,'adaptive_q_grid') && cfg.adaptive_q_grid
        aggregate_rate=cfg.n_nodes*lambda_eff;
        if aggregate_rate<=cfg.q_grid_light_max_aggregate_pkt_s
            q_values=cfg.q_grid_light;
        elseif aggregate_rate<=cfg.q_grid_medium_max_aggregate_pkt_s
            q_values=cfg.q_grid_medium;
        else
            q_values=cfg.q_grid_heavy;
        end
    end
    q_values=unique(double(q_values(:).'));
    if isempty(q_values) || any(~isfinite(q_values) | q_values<=0 | q_values>1)
        error('run_experiment:BadConditionQGrid', ...
            'The condition-specific q grid must contain values in (0,1].');
    end
end

function grid = evaluate_q_grid(protocol, q_values, n_runs, seed_offset, ...
        scenario, cfg, M, lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx)
    n_q = numel(q_values);
    grid = repmat(struct('q',NaN,'mean_delay_us',NaN,'se_delay_us',NaN, ...
        'mean_p95_us',NaN,'stable_fraction',0,'mean_collision_waste_us',NaN, ...
        'rate_screen_rejected_fraction',0,'run_summaries',[]), n_q, 1);

    [traces, protocol_seeds] = make_job_inputs(protocol, n_runs, seed_offset, ...
        cfg, M, lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx);
    n_jobs = n_q * n_runs;
    job_results = cell(n_jobs,1);
    use_parallel = cfg.parallel && n_jobs > 1 && ...
                   license('test','Distrib_Computing_Toolbox');
    if use_parallel
        parfor job = 1:n_jobs
            qi = ceil(job/n_runs);
            ri = mod(job-1,n_runs)+1;
            job_results{job} = run_tuning_job(protocol,traces{ri}, ...
                scenario,cfg,M,q_values(qi),protocol_seeds(ri));
        end
    else
        for job = 1:n_jobs
            qi = ceil(job/n_runs);
            ri = mod(job-1,n_runs)+1;
            job_results{job} = run_tuning_job(protocol,traces{ri}, ...
                scenario,cfg,M,q_values(qi),protocol_seeds(ri));
        end
    end

    for qi = 1:n_q
        first = (qi-1)*n_runs+1;
        runs = job_results(first:first+n_runs-1);
        run_structs = [runs{:}];
        summaries = [run_structs.summary];
        delays = [summaries.mean_delay_us];
        p95 = [summaries.p95_delay_us];
        stable = [summaries.stable];
        wastes = nan(1,numel(runs));
        for ri = 1:numel(runs)
            d = runs{ri}.diagnostics;
            if isfield(d,'collision_channel_time_us')
                wastes(ri)=d.collision_channel_time_us;
            elseif isfield(d,'collision_waste_us')
                wastes(ri)=d.collision_waste_us;
            elseif isfield(d,'collision_wasted_us')
                wastes(ri)=d.collision_wasted_us;
            end
        end
        grid(qi).q = q_values(qi);
        grid(qi).mean_delay_us = mean(delays,'omitnan');
        n_valid = nnz(isfinite(delays));
        if n_valid >= 2
            grid(qi).se_delay_us = std(delays,'omitnan')/sqrt(n_valid);
        end
        grid(qi).mean_p95_us = mean(p95,'omitnan');
        grid(qi).stable_fraction = mean(stable);
        grid(qi).rate_screen_rejected_fraction = ...
            mean([summaries.tuning_rate_screen_rejected]);
        grid(qi).mean_collision_waste_us = mean(wastes,'omitnan');
        grid(qi).run_summaries = summaries;
    end
end

function compact = run_tuning_job(protocol,trace,scenario,cfg,M,q,seed)
%RUN_TUNING_JOB Keep worker traffic bounded without changing simulation.
% The protocol still builds and validates its packet log locally.  Only the
% summary and the collision wall-clock metric used for q tie-breaking cross
% the worker boundary; formal evaluation continues to retain every packet.
% A no-drain screen may reject a q only when its measurement-window
% departure rate already makes the final stability predicate impossible.
% Drain completions cannot change that rate, so this is an exact rejection,
% not a heuristic early stop.
    if cfg.tuning_rate_screen && cfg.sim_hard_end_us > cfg.arrival_end_us
        screen_cfg = cfg;
        screen_cfg.drain_max_us = 0;
        screen_cfg.sim_hard_end_us = cfg.arrival_end_us;
        screen_trace = trace;
        screen_trace.hard_end_us = cfg.arrival_end_us;
        screened = run_protocol_v2(protocol,screen_trace,scenario,screen_cfg,M,q,seed);
        s = screened.summary;
        rate_tolerance = cfg.stability_rate_tolerance * ...
                         max(s.arrival_rate_pkt_s,1);
        impossible = s.n_arrived == 0 || ...
            abs(s.goodput_pkt_s-s.arrival_rate_pkt_s) > rate_tolerance;
        if impossible
            s.stable = false;
            s.tuning_rate_screen_rejected = true;
            compact = compact_tuning_result(s,screened.diagnostics,true);
            return;
        end
    end
    full = run_protocol_v2(protocol,trace,scenario,cfg,M,q,seed);
    full.summary.tuning_rate_screen_rejected = false;
    compact = compact_tuning_result(full.summary,full.diagnostics,false);
end

function compact = compact_tuning_result(summary,d,screen_rejected)
    compact_diagnostics = struct();
    aliases = {'collision_channel_time_us','collision_waste_us', ...
               'collision_wasted_us'};
    for i = 1:numel(aliases)
        if isfield(d,aliases{i})
            compact_diagnostics.(aliases{i}) = d.(aliases{i});
        end
    end
    compact_diagnostics.tuning_rate_screen_rejected = screen_rejected;
    compact = struct('summary',summary, ...
                     'diagnostics',compact_diagnostics);
end

function runs = evaluate_jobs(protocol, q, n_runs, seed_offset, scenario, cfg, M, ...
        lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx)
    [traces, protocol_seeds] = make_job_inputs(protocol, n_runs, seed_offset, ...
        cfg, M, lambda_eff, lambda_base, load_idx, lambda_idx, protocol_idx);

    runs = cell(n_runs,1);
    use_parallel = cfg.parallel && n_runs > 1 && ...
                   license('test','Distrib_Computing_Toolbox');
    if use_parallel
        parfor r = 1:n_runs
            runs{r} = run_protocol_v2(protocol, traces{r}, scenario, cfg, ...
                                      M, q, protocol_seeds(r));
        end
    else
        for r = 1:n_runs
            runs{r} = run_protocol_v2(protocol, traces{r}, scenario, cfg, ...
                                      M, q, protocol_seeds(r));
        end
    end
    if ~cfg.collect_packet_log
        for r = 1:n_runs
            runs{r}.packet_log = struct();
        end
    end
end

function [traces,protocol_seeds] = make_job_inputs(protocol,n_runs,seed_offset, ...
        cfg,M,lambda_eff,lambda_base,load_idx,lambda_idx,protocol_idx) %#ok<INUSD>
    traces = cell(n_runs,1);
    protocol_seeds = zeros(n_runs,1);
    for r = 1:n_runs
        arrival_seed = bounded_seed(cfg.traffic_seed_base + seed_offset + ...
            load_idx*1000000 + lambda_idx*10000 + r);
        traces{r} = cached_arrival_trace(lambda_eff,cfg,arrival_seed);
        % Common random numbers across q candidates reduce tuning noise.
        % Protocols retain independent streams because their decision-event
        % calendars are not commensurate.
        protocol_seeds(r) = bounded_seed(cfg.protocol_seed_base + seed_offset + ...
            protocol_idx*1000000 + M*10000 + r);
    end
end

function trace = cached_arrival_trace(lambda_eff,cfg,arrival_seed)
    persistent trace_cache
    if isempty(trace_cache)
        trace_cache = containers.Map('KeyType','char','ValueType','any');
    end
    key = sprintf('l%.17g_s%d_n%d_t%d_a%.17g_h%.17g',lambda_eff, ...
        arrival_seed,cfg.n_nodes,cfg.arrival_tick_us,cfg.arrival_end_us, ...
        cfg.sim_hard_end_us);
    if isKey(trace_cache,key)
        trace = trace_cache(key);
    else
        trace = generate_arrival_trace(lambda_eff,cfg,arrival_seed);
        trace_cache(key) = trace;
    end
end

function output = run_cca_ablation(primary,scenario,cfg,output_dir, ...
                                   cfg_hash,code_fingerprint)
    protocols = intersect(cfg.protocols,{'sb_cf','sb_cb'},'stable');
    load_modes = intersect(cfg.load_modes,cfg.ablation_load_modes,'stable');
    lambdas = cfg.ablation_lambda_values;
    M_values = cfg.ablation_M_values;
    variants = struct('name',{},'mode',{},'sensitivity',{});
    for i=1:numel(cfg.cca_ablation_modes)
        mode=cfg.cca_ablation_modes{i};
        variants(end+1)=struct('name',mode,'mode',mode, ... %#ok<AGROW>
            'sensitivity',cfg.rx_sens_dbm);
    end
    for sensitivity=cfg.rx_sens_sweep_dbm
        if sensitivity==cfg.rx_sens_dbm, continue; end
        variants(end+1)=struct('name',sprintf('directional_%gdBm',sensitivity), ... %#ok<AGROW>
            'mode','directional','sensitivity',sensitivity);
    end

    checkpoint_dir=fullfile(output_dir,'checkpoints_cca');
    if ~exist(checkpoint_dir,'dir'), mkdir(checkpoint_dir); end
    rows=struct([]); row_index=0;
    total=numel(protocols)*numel(load_modes)*numel(lambdas)* ...
          numel(M_values)*numel(variants);
    done=0;
    for li=1:numel(load_modes)
        load_mode=load_modes{li};
        original_load_idx=find(strcmp(cfg.load_modes,load_mode),1);
        for bi=1:numel(lambdas)
            lambda_base=lambdas(bi);
            original_lambda_idx=find(cfg.lambda_values==lambda_base,1);
            if isempty(original_lambda_idx), original_lambda_idx=bi+100; end
            for M=M_values
                if strcmp(load_mode,'fixed_payload')
                    lambda_eff=lambda_base/M;
                else
                    lambda_eff=lambda_base;
                end
                for pi=1:numel(protocols)
                    protocol=protocols{pi};
                    protocol_idx=find(strcmp(cfg.protocols,protocol),1);
                    [q_ref,q_source]=reference_q(primary,protocol,load_mode, ...
                        lambda_base,M,cfg.n_nodes);
                    for vi=1:numel(variants)
                        done=done+1;
                        variant=variants(vi);
                        fprintf('[CCA %d/%d] %s %s lambda=%g M=%d\n', ...
                            done,total,protocol,variant.name,lambda_base,M);
                        safe_variant=regexprep(variant.name,{'-','\.'},{'m','p'});
                        tag=sprintf('%s_%s_lam%g_M%d_%s',protocol,load_mode, ...
                                    lambda_base,M,safe_variant);
                        checkpoint=fullfile(checkpoint_dir,[tag '.mat']);
                        if cfg.resume && exist(checkpoint,'file')
                            condition=load_condition_checkpoint(checkpoint, ...
                                cfg_hash,code_fingerprint);
                        else
                            variant_cfg=cfg;
                            variant_cfg.cca_mode=variant.mode;
                            variant_cfg.rx_sens_dbm=variant.sensitivity;
                            variant_cfg.run_cca_ablation=false;
                            variant_cfg.run_topology_robustness=false;
                            eval_results=evaluate_jobs(protocol,q_ref, ...
                                cfg.n_ablation_runs,20000,scenario, ...
                                variant_cfg,M,lambda_eff,lambda_base, ...
                                original_load_idx,original_lambda_idx,protocol_idx);
                            tune=struct('best_q',q_ref,'grid',[], ...
                                'q_source',q_source);
                            condition=summarize_condition(protocol,load_mode, ...
                                lambda_base,lambda_eff,M,tune,eval_results);
                            condition.row.cca_variant=string(variant.name);
                            condition.row.cca_mode=string(variant.mode);
                            condition.row.rx_sens_dbm=variant.sensitivity;
                            condition.row.q_source=string(q_source);
                            condition.config_hash=cfg_hash;
                            condition.code_fingerprint=code_fingerprint;
                            save_checkpoint_atomic(checkpoint,condition);
                        end
                        row_index=row_index+1;
                        if isempty(rows), rows=condition.row;
                        else, rows(row_index)=condition.row; end %#ok<AGROW>
                    end
                end
            end
        end
    end
    if isempty(rows), output=table(); else, output=struct2table(rows); end
end

function output = run_topology_robustness(primary,cfg,output_dir, ...
                                          cfg_hash,code_fingerprint)
    checkpoint_dir=fullfile(output_dir,'checkpoints_topology');
    if ~exist(checkpoint_dir,'dir'), mkdir(checkpoint_dir); end
    rows=struct([]); row_index=0;
    protocols=intersect(cfg.protocols,cfg.robustness_protocols,'stable');
    load_modes=cfg.load_modes;
    total=numel(cfg.robustness_topology_seeds)*numel(protocols)* ...
        numel(load_modes)*numel(cfg.robustness_lambda_values)* ...
        numel(cfg.robustness_M_values);
    done=0;
    for si=1:numel(cfg.robustness_topology_seeds)
        topology_seed=cfg.robustness_topology_seeds(si);
        topology=prepare_scenario_v2(cfg,topology_seed);
        for li=1:numel(load_modes)
            load_mode=load_modes{li};
            for bi=1:numel(cfg.robustness_lambda_values)
                lambda_base=cfg.robustness_lambda_values(bi);
                lambda_idx=find(cfg.lambda_values==lambda_base,1);
                if isempty(lambda_idx), lambda_idx=bi+200; end
                for M=cfg.robustness_M_values
                    if strcmp(load_mode,'fixed_payload')
                        lambda_eff=lambda_base/M;
                    else
                        lambda_eff=lambda_base;
                    end
                    for pi=1:numel(protocols)
                        protocol=protocols{pi};
                        done=done+1;
                        fprintf('[TOPO %d/%d] seed=%d %s lambda=%g M=%d\n', ...
                            done,total,topology_seed,protocol,lambda_base,M);
                        [q_ref,q_source]=reference_q(primary,protocol, ...
                            load_mode,lambda_base,M,cfg.n_nodes);
                        tag=sprintf('topo%d_%s_%s_lam%g_M%d',topology_seed, ...
                            protocol,load_mode,lambda_base,M);
                        checkpoint=fullfile(checkpoint_dir,[tag '.mat']);
                        if cfg.resume && exist(checkpoint,'file')
                            condition=load_condition_checkpoint(checkpoint, ...
                                cfg_hash,code_fingerprint);
                        else
                            eval_results=evaluate_jobs(protocol,q_ref, ...
                                cfg.n_robustness_runs,40000,topology, ...
                                cfg,M,lambda_eff,lambda_base,li,lambda_idx,pi);
                            tune=struct('best_q',q_ref,'grid',[], ...
                                'q_source',q_source);
                            condition=summarize_condition(protocol,load_mode, ...
                                lambda_base,lambda_eff,M,tune,eval_results);
                            condition.row.topology_seed=topology_seed;
                            condition.row.q_source=string(q_source);
                            condition.config_hash=cfg_hash;
                            condition.code_fingerprint=code_fingerprint;
                            save_checkpoint_atomic(checkpoint,condition);
                        end
                        row_index=row_index+1;
                        if isempty(rows), rows=condition.row;
                        else, rows(row_index)=condition.row; end %#ok<AGROW>
                    end
                end
            end
        end
    end
    if isempty(rows), output=table(); else, output=struct2table(rows); end
end

function [q,q_source] = reference_q(primary,protocol,load_mode,lambda_base,M,n_nodes)
    q=NaN;
    if ~isempty(primary)
        mask=string(primary.protocol)==string(protocol) & ...
             string(primary.load_mode)==string(load_mode) & ...
             primary.lambda_base==lambda_base & primary.M==M;
        found=find(mask,1);
        if ~isempty(found), q=primary.best_q(found); end
    end
    if isfinite(q) && q>0 && q<=1
        q_source='primary_tuned';
    else
        q=1/n_nodes;
        q_source='fallback_1_over_N';
    end
end

function [best_q, best_idx] = select_best_q(grid, n_runs)
    best_q = NaN; best_idx = NaN;
    if isempty(grid), return; end
    % A q is eligible only when every independent tuning seed is stable.
    % This prevents a censored run's deceptively short conditional delay
    % from making an unstable q look optimal.
    required_fraction = 1;
    eligible = [grid.stable_fraction] >= required_fraction & ...
               isfinite([grid.mean_delay_us]);
    idx = find(eligible);
    if isempty(idx), return; end
    means = [grid(idx).mean_delay_us];
    [~, local] = min(means);
    candidate = idx(local);
    candidate_se = grid(candidate).se_delay_us;
    if ~isfinite(candidate_se), candidate_se = 0; end
    threshold = grid(candidate).mean_delay_us + max(0,candidate_se);
    tied = idx([grid(idx).mean_delay_us] <= threshold);
    if numel(tied) > 1
        p95 = [grid(tied).mean_p95_us];
        finite_p95 = isfinite(p95);
        if any(finite_p95)
            min_p95 = min(p95(finite_p95));
            tied = tied(finite_p95 & p95 == min_p95);
        end
    end
    if numel(tied) > 1
        waste = [grid(tied).mean_collision_waste_us];
        waste(~isfinite(waste)) = inf;
        [~, k] = min(waste);
        candidate = tied(k);
    else
        candidate = tied(1);
    end
    best_q = grid(candidate).q;
    best_idx = candidate;
end

function condition = summarize_condition(protocol, load_mode, lambda_base, ...
        lambda_eff, M, tune, eval_results)
    row = empty_row(protocol, load_mode, lambda_base, lambda_eff, M, tune.best_q);
    if ~isempty(eval_results)
        run_structs = [eval_results{:}];
        summaries = [run_structs.summary];
        row.stable_fraction = mean([summaries.stable]);
        metrics = condition_metric_names();
        for i = 1:numel(metrics)
            values = [summaries.(metrics{i})];
            row.(metrics{i}) = mean(values,'omitnan');
            row.([metrics{i} '_ci95']) = ci95(values);
        end
        if row.stable_fraction < 1
            steady = {'mean_delay_us','mean_queue_delay_us', ...
                'mean_access_delay_us','p50_delay_us','p95_delay_us', ...
                'p99_delay_us','mean_boundary_wait_us','mean_difs_wait_us', ...
                'mean_probability_wait_us','mean_busy_nav_wait_us', ...
                'mean_collision_delay_us','mean_control_delay_us', ...
                'mean_data_delay_us','mean_other_access_delay_us', ...
                'little_relative_error'};
            for i=1:numel(steady)
                row.(steady{i})=NaN;
                row.([steady{i} '_ci95'])=NaN;
            end
        end
    end
    condition = struct('row',row, 'tuning',tune, ...
                       'evaluation',{eval_results});
end

function row = empty_row(protocol, load_mode, lambda_base, lambda_eff, M, best_q)
    row = struct('protocol',string(protocol), 'load_mode',string(load_mode), ...
        'lambda_base',lambda_base, 'lambda_effective',lambda_eff, ...
        'M',M, 'Tp_us',190*M, 'best_q',best_q, 'stable_fraction',0);
    metrics = condition_metric_names();
    for i=1:numel(metrics)
        row.(metrics{i}) = NaN;
        row.([metrics{i} '_ci95']) = NaN;
    end
end

function metrics = condition_metric_names()
    metrics = { ...
        'n_arrived','n_completed','n_censored','final_backlog', ...
        'mean_delay_us','mean_queue_delay_us','mean_access_delay_us', ...
        'conditional_mean_delay_us','p50_delay_us','p95_delay_us', ...
        'p99_delay_us','conditional_p50_delay_us', ...
        'conditional_p95_delay_us','conditional_p99_delay_us', ...
        'mean_boundary_wait_us','mean_difs_wait_us', ...
        'mean_probability_wait_us','mean_busy_nav_wait_us', ...
        'mean_collision_delay_us','mean_control_delay_us', ...
        'mean_data_delay_us','mean_other_access_delay_us', ...
        'arrival_rate_pkt_s','goodput_pkt_s','normalized_offered_units_s', ...
        'normalized_goodput_units_s','goodput_bit_s','payload_airtime', ...
        'mean_system_packets','mean_waiting_packets','mean_service_packets', ...
        'backlog_slope_pkt_s','completion_ratio','little_relative_error', ...
        'jain_fairness','attempts_total','retransmissions_completed_cohort', ...
        'mean_attempts_completed','collision_waste_us_total', ...
        'collision_channel_time_us_total','collision_tx_airtime_us_total', ...
        'collision_channel_time_us_measure','collision_tx_airtime_us_measure'};
end

function value = ci95(values)
    values = values(isfinite(values));
    n = numel(values);
    if n < 2
        value = NaN;
    else
        value = tinv(0.975,n-1)*std(values)/sqrt(n);
    end
end

function condition=load_condition_checkpoint(path,cfg_hash,code_fingerprint)
    saved=load(path,'condition');
    condition=saved.condition;
    if ~isfield(condition,'config_hash') || ...
            ~strcmp(char(condition.config_hash),cfg_hash) || ...
            ~isfield(condition,'code_fingerprint') || ...
            ~strcmp(char(condition.code_fingerprint),code_fingerprint)
        error('run_experiment:StaleCheckpoint', ...
            'Checkpoint does not match current config/code: %s',path);
    end
end

function save_checkpoint_atomic(path, condition)
    tmp = [path '.tmp.mat'];
    save(tmp, 'condition', '-v7.3');
    movefile(tmp, path, 'f');
end

function maybe_start_pool(cfg)
    if ~cfg.parallel || ~license('test','Distrib_Computing_Toolbox')
        return;
    end
    pool = gcp('nocreate');
    if isempty(pool)
        parpool('local', cfg.n_workers);
    end
end

function seed = bounded_seed(value)
    seed = mod(double(value), 2^31-2) + 1;
end

function manifest = make_manifest(cfg,cfg_hash,code_fingerprint,output_dir, ...
                                  status,verification_status)
    manifest = struct();
    manifest.schema_version = cfg.schema_version;
    manifest.config_hash = cfg_hash;
    manifest.code_fingerprint = code_fingerprint;
    manifest.profile = cfg.profile;
    manifest.status = status;
    manifest.created_at = char(datetime('now', ...
        'Format','yyyy-MM-dd''T''HH:mm:ss'));
    manifest.matlab_version = version;
    manifest.computer = computer;
    manifest.output_dir = output_dir;
    manifest.material_passport = struct( ...
        'origin_skill','experiment-agent', 'origin_mode','run/validate', ...
        'origin_date','2026-07-22', ...
        'verification_status',verification_status, ...
        'version_label','exp_result_v2');
end

function write_json(path, value)
    fid = fopen(path, 'w');
    if fid < 0, error('run_experiment:ManifestWrite', 'Cannot write %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid, jsonencode(value, 'PrettyPrint', true), 'char');
end
