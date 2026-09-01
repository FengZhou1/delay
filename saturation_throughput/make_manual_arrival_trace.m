function trace = make_manual_arrival_trace(times_us, node_id, cfg)
%MAKE_MANUAL_ARRIVAL_TRACE Build a deterministic trace for unit tests.
    times_us = double(times_us(:));
    node_id = double(node_id(:));
    if numel(times_us) ~= numel(node_id)
        error('make_manual_arrival_trace:SizeMismatch', ...
              'times_us and node_id must have the same length.');
    end
    if any(node_id < 1 | node_id > cfg.n_nodes | node_id ~= round(node_id))
        error('make_manual_arrival_trace:BadNode', 'Invalid node identifier.');
    end
    if any(times_us < 0 | times_us >= cfg.arrival_end_us)
        error('make_manual_arrival_trace:BadTime', ...
              'Manual arrivals must fall in [0, arrival_end_us).');
    end
    ordered = sortrows([times_us,node_id],[1,2]);
    times_us = ordered(:,1); node_id = ordered(:,2);
    ids = cell(cfg.n_nodes,1);
    for u=1:cfg.n_nodes
        ids{u}=find(node_id==u).';
    end
    trace = struct('times_us',times_us,'node_id',node_id, ...
        'packet_ids_by_node',{ids},'n_packets',numel(times_us), ...
        'lambda_per_node',NaN,'bernoulli_p',NaN,'tick_us',cfg.arrival_tick_us, ...
        'warmup_us',cfg.warmup_us,'measure_us',cfg.measure_us, ...
        'arrival_end_us',cfg.arrival_end_us,'hard_end_us',cfg.sim_hard_end_us, ...
        'seed',NaN);
end
