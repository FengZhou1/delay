function [th, queue_delays, access_delays, miss_prob, mean_qlen] = proto_csma_basic(arrivals, n_nodes, q, proto, phy)
    SENS = 10^((phy.RX_SENS_DBM - 30)/10);
    DIFS_LIMIT = proto.DIFS;
    N_DATA = proto.N_DATA;
    Int_Matrix = phy.Int_Matrix;
    steps = size(arrivals, 1);

    is_tx = false(n_nodes, 1); 
    tx_timer = zeros(n_nodes, 1); 
    difs = zeros(n_nodes, 1); 
    col = false(n_nodes, 1);

    queues = cell(n_nodes, 1);
    hol_become_time = zeros(n_nodes, 1);

    success_slots = 0;
    total_sensing_events = 0;
    missed_detection_events = 0;

    max_delays = ceil(steps / N_DATA) * n_nodes;
    queue_delays = zeros(max_delays, 1);
    access_delays = zeros(max_delays, 1);
    d_idx = 0;

    qlen_accum = 0;          % 时间平均队列长度累积量 (包*slot)

    for t = 1:steps
        % --- 1. Arrivals --- (arrivals update hol_become_time when queue was empty)
        a_idx = find(arrivals(t, :));
        for k = 1:numel(a_idx)
            u = a_idx(k);
            if isempty(queues{u})
                hol_become_time(u) = t;
            end
            queues{u}(end+1) = t;
        end

        % --- 采样当前 slot 队列长度 (到达后状态) ---
        sum_q = 0;
        for u = 1:n_nodes
            sum_q = sum_q + numel(queues{u});
        end
        qlen_accum = qlen_accum + sum_q;

        listeners = ~is_tx;

        if any(is_tx)
            rx_power = sum(Int_Matrix(is_tx, :), 1)';
            sensed_busy = (rx_power > SENS) & listeners;

            n_listeners = sum(listeners);
            total_sensing_events = total_sensing_events + n_listeners;
            missed_detection_events = missed_detection_events + sum(listeners & ~sensed_busy);
        else
            sensed_busy = false(n_nodes, 1);
        end

        blocked = is_tx | sensed_busy;
        difs(blocked) = 0;
        difs(~blocked) = difs(~blocked) + 1;

        has_packet = false(n_nodes,1);
        for u = 1:n_nodes, has_packet(u) = ~isempty(queues{u}); end

        can_tx = listeners & has_packet & (difs > DIFS_LIMIT);

        if any(can_tx)
            will_tx = can_tx & (rand(n_nodes, 1) < q);
            if any(will_tx)
                is_tx(will_tx) = true;
                tx_timer(will_tx) = N_DATA;
                difs(will_tx) = 0;
            end
        end

        n_tx = sum(is_tx);
        if n_tx > 1
            col(is_tx) = true;
        end

        if any(is_tx)
            tx_timer(is_tx) = tx_timer(is_tx) - 1;

            finished = is_tx & (tx_timer == 0);
            if any(finished)
                success = finished & ~col;
                collision = finished & col;

                s_idx = find(success);
                for k = 1:numel(s_idx)
                    u = s_idx(k);
                    success_slots = success_slots + N_DATA;
                    d_idx = d_idx + 1;
                    if d_idx > numel(queue_delays)
                        queue_delays(end+1000) = 0;
                        access_delays(end+1000) =  0;
                    end
                    queue_delays(d_idx) = hol_become_time(u) - queues{u}(1);
                    access_delays(d_idx) = t - hol_become_time(u);
                    queues{u}(1) = [];
                    if ~isempty(queues{u})
                        hol_become_time(u) = t;
                    end
                end

                col(collision) = false;
                is_tx(finished) = false;
            end
        end
    end

    for u = 1:n_nodes
        for j = 1:numel(queues{u})
            d_idx = d_idx + 1;
            if d_idx > numel(queue_delays)
                queue_delays(end+1000) = 0;
                access_delays(end+1000) =  0;
            end
            if j == 1
                queue_delays(d_idx) = hol_become_time(u) - queues{u}(j);
            else
                queue_delays(d_idx) = steps - queues{u}(j);
            end
            access_delays(d_idx) = NaN;
        end
    end

    queue_delays = queue_delays(1:d_idx);
    access_delays = access_delays(1:d_idx);
    th = success_slots / steps;

    if total_sensing_events > 0
        miss_prob = missed_detection_events / total_sensing_events;
    else
        miss_prob = 0;
    end

    if steps > 0
        mean_qlen = qlen_accum / steps;
    else
        mean_qlen = 0;
    end
end
