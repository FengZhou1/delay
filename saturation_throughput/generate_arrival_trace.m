function trace = generate_arrival_trace(lambda_per_node, cfg, seed)
%GENERATE_ARRIVAL_TRACE Sparse Bernoulli arrivals on the common mmWave grid.
% Arrivals are generated once and reused by every protocol.  Event time zero
% is valid, and arrivals at a decision boundary are enqueued before that
% boundary's protocol decision.

    tick_us = cfg.arrival_tick_us;
    horizon_us = cfg.arrival_end_us;
    n_nodes = cfg.n_nodes;
    n_ticks = ceil(horizon_us / tick_us);
    p = lambda_per_node * tick_us * 1e-6;
    if p > 1
        error('generate_arrival_trace:ProbabilityAboveOne', ...
              'lambda*arrival_tick exceeds one Bernoulli arrival per tick.');
    end

    stream = RandStream('mt19937ar', 'Seed', double(seed));
    chunk = 2e5;
    times_parts = cell(ceil(n_ticks/chunk), 1);
    nodes_parts = cell(ceil(n_ticks/chunk), 1);
    part = 0;
    for first = 1:chunk:n_ticks
        last = min(n_ticks, first + chunk - 1);
        mask = rand(stream, last-first+1, n_nodes) < p;
        [rows, nodes] = find(mask);
        part = part + 1;
        times_parts{part} = (double(first + rows - 2) * tick_us);
        nodes_parts{part} = double(nodes);
    end

    times_us = vertcat(times_parts{1:part});
    node_id = vertcat(nodes_parts{1:part});
    if ~isempty(times_us)
        ordered = sortrows([times_us, node_id], [1, 2]);
        times_us = ordered(:,1);
        node_id = ordered(:,2);
    end

    n_packets = numel(times_us);
    packet_ids_by_node = cell(n_nodes, 1);
    for u = 1:n_nodes
        packet_ids_by_node{u} = find(node_id == u).';
    end

    trace = struct();
    trace.times_us = times_us;
    trace.node_id = node_id;
    trace.packet_ids_by_node = packet_ids_by_node;
    trace.n_packets = n_packets;
    trace.lambda_per_node = lambda_per_node;
    trace.bernoulli_p = p;
    trace.tick_us = tick_us;
    trace.warmup_us = cfg.warmup_us;
    trace.measure_us = cfg.measure_us;
    trace.arrival_end_us = cfg.arrival_end_us;
    trace.hard_end_us = cfg.sim_hard_end_us;
    trace.seed = seed;
end
