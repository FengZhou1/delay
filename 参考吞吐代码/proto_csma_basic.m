function [th, miss_prob] = proto_csma_basic(steps, n_nodes, q, proto, phy)
% PROTO_CSMA_BASIC 毫米波CSMA/CA基本模式（饱和模式，无RTS/CTS）
% 所有节点始终有包待发送

    SENS = 10^((phy.RX_SENS_DBM - 30)/10);
    DIFS_LIMIT = proto.DIFS;
    N_DATA = proto.N_DATA;
    Int_Matrix = phy.Int_Matrix;

    is_tx = false(n_nodes, 1);
    tx_timer = zeros(n_nodes, 1);
    difs = zeros(n_nodes, 1);
    col = false(n_nodes, 1);

    queues = cell(n_nodes, 1);
    success_slots = 0;
    total_sensing_events = 0;
    missed_detection_events = 0;

    for t = 1:steps
        % --- 1. 饱和到达 ---
        for u = 1:n_nodes
            if isempty(queues{u})
                queues{u}(end+1) = t;
            end
        end

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

        has_packet = false(n_nodes, 1);
        for u = 1:n_nodes
            has_packet(u) = ~isempty(queues{u});
        end

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
                    queues{u}(1) = [];
                end

                col(collision) = false;
                is_tx(finished) = false;
            end
        end
    end

    th = success_slots / steps;

    if total_sensing_events > 0
        miss_prob = missed_detection_events / total_sensing_events;
    else
        miss_prob = 0;
    end
end
