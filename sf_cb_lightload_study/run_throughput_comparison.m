function out = run_throughput_comparison(cfg)
%RUN_THROUGHPUT_COMPARISON Saturated normalized-throughput comparison.
%   out = run_throughput_comparison()          % analysis profile
%   out = run_throughput_comparison(cfg)       % custom / smoke config
%
% All four protocols share one deterministic saturation supply: every node
% receives one packet every M*162.5 us (the batch_clear queue model).  For
% each protocol and M the access probability q is scanned (protocol-specific
% coarse grid, one tuning run per point, local refinement, then
% n_eval_runs seeds on the fine grid) and the q maximizing the successful
% payload airtime fraction inside the measurement window is chosen.
%
% Performance notes: coarse and fine q scans run in parallel (parfor);
% results are saved incrementally after every (M, protocol) cell so a
% crashed run can be resumed from delay_partial-style state.
%
% Outputs: throughput_data.mat (results + best-q table),
% throughput_comparison.png (x = Tp = M*162.5 us, y = normalized
% throughput), throughput_q_table.csv.

    if nargin < 1 || isempty(cfg)
        cfg = default_lightload_sfcb_config('analysis','saturation');
    end
    if ~isfield(cfg,'mode') || ~strcmpi(char(cfg.mode),'saturation')
        error('run_throughput_comparison:BadMode', ...
            'Expected a saturation-mode config (mode = ''saturation'').');
    end

    timing = protocol_timing(cfg);
    scenario = prepare_scenario_v2(cfg, cfg.topology_seed);
    protocols = {'sf_cb','batch_clear','unslotted','sb_cb'};
    n_protocols = numel(protocols);
    n_fine = double(cfg.q_fine_points);
    n_eval = double(cfg.n_eval_runs);
    output_root = char(cfg.output_root);

    if ~exist(output_root,'dir'), mkdir(output_root); end
    prof_tag = 'smoke';
    if isfield(cfg,'profile') && ~isempty(cfg.profile)
        prof_tag = lower(char(cfg.profile));
    end
    partial_file = fullfile(output_root, sprintf('throughput_partial_%s.mat', prof_tag));
    if exist(partial_file,'file')
        partial = load(partial_file);
        done_keys = partial.keys_save;
        partial_rows = partial.rows_save;
        partial_qrows = partial.qrows_save;
        fprintf('[saturation] resuming: %d cells already complete\n', ...
            numel(done_keys));
    else
        done_keys = {};
        partial_rows = cell(0,1);
        partial_qrows = cell(0,1);
    end

    rows = partial_rows;
    qrows = partial_qrows;
    for Mi = 1:numel(cfg.M_values)
        M = double(cfg.M_values(Mi));
        trace = build_lightload_sat_trace(cfg, M);
        for pi = 1:n_protocols
            protocol = protocols{pi};
            coarse_q = double(cfg.protocol_q_grids.(protocol)(:).');
            proto_seed_base = cfg.protocol_seed_base + 100*pi;
            cell_key = sprintf('%s|M%d', protocol, M);
            if ismember(cell_key, done_keys)
                fprintf('[saturation] %s M=%d: cached\n', ...
                    protocol, M);
                continue;
            end
            if isfield(cfg,'q_max_sat') && ~isempty(cfg.q_max_sat) && ...
                    (strcmp(protocol,'unslotted') || strcmp(protocol,'sb_cb'))
                coarse_q = coarse_q(coarse_q <= cfg.q_max_sat);
                if isempty(coarse_q)
                    coarse_q = cfg.protocol_q_grids.(protocol)(1);
                end
            end
            fprintf('[saturation] %s M=%d: coarse scan (%d q)\n', ...
                protocol, M, numel(coarse_q));

            % ---- coarse tuning pass (one run per q) ----
            airtime = nan(numel(coarse_q),1);
            parfor i = 1:numel(coarse_q)
                result = simulate_sfcb_lightload_variant(protocol, trace, ...
                    scenario, cfg, M, coarse_q(i), cfg.protocol_seed_base + pi);
                airtime(i) = result.summary.payload_airtime_fraction;
            end
            [~, best_idx] = max(airtime);

            % ---- local refinement around the best coarse point ----
            [fine_q, ~] = build_refined_q_grid(coarse_q, best_idx, ...
                n_fine, cfg.q_refine_scale, cfg.q_refine_floor, 1);

            fprintf('[saturation] %s M=%d: fine eval (%d q x %d seeds)\n', ...
                protocol, M, numel(fine_q), n_eval);
            fine_airtime = nan(numel(fine_q), n_eval);
            for i = 1:numel(fine_q)
                if n_eval <= 1
                    result = simulate_sfcb_lightload_variant(protocol, ...
                        trace, scenario, cfg, M, fine_q(i), ...
                        proto_seed_base + 1);
                    fine_airtime(i,1) = ...
                        result.summary.payload_airtime_fraction;
                else
                    parfor s = 1:n_eval
                        result = simulate_sfcb_lightload_variant(protocol, ...
                            trace, scenario, cfg, M, fine_q(i), ...
                            proto_seed_base + s);
                        fine_airtime(i,s) = ...
                            result.summary.payload_airtime_fraction;
                    end
                end
            end
            mean_airtime = nanmean(fine_airtime,2);
            [best_airtime, fine_best_idx] = max(mean_airtime);
            best_q = fine_q(fine_best_idx);
            best_std = std(fine_airtime(fine_best_idx,:),0,2);

            rows{end+1,1} = struct( ... %#ok<AGROW>
                'protocol', protocol, ...
                'M', M, ...
                'Tp_us', timing.CONN_SLOT_US * M, ...
                'best_q', best_q, ...
                'throughput', best_airtime, ...
                'throughput_std', best_std, ...
                'n_eval_runs', n_eval);
            qrows{end+1,1} = struct( ... %#ok<AGROW>
                'protocol', protocol, ...
                'M', M, ...
                'q_coarse_best', coarse_q(best_idx), ...
                'q_coarse_throughput', airtime(best_idx), ...
                'q_fine_best', best_q, ...
                'q_fine_throughput', best_airtime, ...
                'fine_q', fine_q, ...
                'fine_throughput', mean_airtime);
            done_keys{end+1,1} = cell_key; %#ok<AGROW>
            rows_save = rows; qrows_save = qrows; keys_save = done_keys;
            save(partial_file, 'rows_save', 'qrows_save', 'keys_save', ...
                '-v7.3');
        end
    end

    table_rows = vertcat(rows{:});
    q_table = vertcat(qrows{:});
    data = struct();
    data.config = cfg;
    data.timing = timing;
    data.results = table_rows;
    data.q_table = q_table;
    data.protocols = protocols;
    data.M_values = double(cfg.M_values(:).');

    if ~exist(output_root,'dir'), mkdir(output_root); end
    save(fullfile(output_root,'throughput_data.mat'), 'data');

    qcsv = q_table_to_table(q_table);
    writetable(qcsv, fullfile(output_root,'throughput_q_table.csv'));

    tput_png = plot_throughput_comparison(data, ...
        fullfile(output_root,'throughput_comparison.png'));
    fprintf('[saturation] saved %s and throughput_q_table.csv\n', tput_png);

    out = struct();
    out.data = data;
    out.plot_file = tput_png;
end

% ---------------- saturation trace ----------------
function trace = build_lightload_sat_trace(cfg, M)
% One deterministic packet per node every M*162.5 us (batch_clear queue
% model).  Identical for all four protocols.
    timing = protocol_timing(cfg);
    Tp = timing.CONN_SLOT_US * double(M);
    horizon = double(cfg.sim_hard_end_us);
    n_periods = max(1, ceil(horizon / Tp));
    period_times = (0:n_periods).' * Tp;
    n_nodes = double(cfg.n_nodes);
    times_us = repmat(period_times.', n_nodes, 1);
    node_id = repmat((1:n_nodes).', 1, numel(period_times));
    times_us = times_us(:);
    node_id = node_id(:);
    [times_us, order] = sort(times_us);
    node_id = node_id(order);

    packet_ids_by_node = cell(n_nodes,1);
    for u = 1:n_nodes
        packet_ids_by_node{u} = find(node_id == u).';
    end

    trace = struct();
    trace.times_us = times_us;
    trace.node_id = node_id;
    trace.packet_ids_by_node = packet_ids_by_node;
    trace.n_packets = numel(times_us);
    trace.lambda_per_node = NaN;
    trace.arrival_end_us = double(cfg.arrival_end_us);
    trace.hard_end_us = double(cfg.sim_hard_end_us);
    trace.saturated = true;
end

% ---------------- helpers ----------------
function t = q_table_to_table(q_table)
    t = table();
    t.protocol = cellfun(@char, {q_table.protocol}.', 'UniformOutput', false);
    t.M = [q_table.M].';
    t.q_coarse_best = [q_table.q_coarse_best].';
    t.q_coarse_throughput = [q_table.q_coarse_throughput].';
    t.q_fine_best = [q_table.q_fine_best].';
    t.q_fine_throughput = [q_table.q_fine_throughput].';
end
