function trace = make_saturation_trace(cfg)
%MAKE_SATURATION_TRACE One persistent virtual HOL packet per MLO station.
%
% Protocol simulators reuse each node's packet id after a successful
% completion when cfg.traffic_mode is saturation.  This avoids an artificial
% finite reservoir while leaving all non-saturated queue paths unchanged.

    n = double(cfg.n_nodes);
    trace = struct();
    trace.times_us = zeros(n,1);
    trace.node_id = (1:n).';
    trace.n_packets = n;
    trace.lambda_per_node = NaN;
    trace.packet_ids_by_node = cell(n,1);
    for u = 1:n
        trace.packet_ids_by_node{u} = u;
    end
    trace.arrival_end_us = double(cfg.arrival_end_us);
    trace.hard_end_us = double(cfg.sim_hard_end_us);
    trace.saturated = true;
end
