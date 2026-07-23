function [th, queue_delays, access_delays, miss_prob, mean_qlen] = proto_aloha_conn(arrivals, n_nodes, q, proto)
    queues = cell(n_nodes, 1);
    hol_become_time = zeros(n_nodes, 1);
    queue_delays = [];
    access_delays = [];
    success_slots = 0;
    qlen_accum = 0;          % 时间平均队列长度累积量 (包*slot)
    n_slots_sampled = 0;

    CONN_LEN = proto.CONN_SLOT;
    steps = size(arrivals, 1);
    num_rounds = floor(steps / CONN_LEN);
    busy_rem = 0;
    active = 0;

    for r = 1:num_rounds
        curr = (r-1) * CONN_LEN;

        if busy_rem > 0
            busy_rem = busy_rem - 1;
            if busy_rem == 0 && active > 0
                success_slots = success_slots + proto.N_DATA;
                completion = curr + CONN_LEN;
                queue_delays(end+1)  = hol_become_time(active) - queues{active}(1);
                access_delays(end+1) = completion - hol_become_time(active);
                queues{active}(1) = [];
                if ~isempty(queues{active})
                    hol_become_time(active) = completion;
                end
                active = 0;
            end
        else
            attempts = [];
            for u = 1:n_nodes
                if ~isempty(queues{u}) && queues{u}(1) <= curr && rand() < q
                    attempts(end+1) = u;
                end
            end

            if isscalar(attempts)
                u = attempts(1);
                active = u;
                data_rounds = max(1, ceil(proto.M_BATCH));
                busy_rem = data_rounds;
            end
        end

        for k = 1:CONN_LEN
            t_idx = curr + k;
            if t_idx > steps
                break;
            end
            a_idx = find(arrivals(t_idx, :));
            for ki = 1:numel(a_idx)
                u = a_idx(ki);
                if isempty(queues{u})
                    hol_become_time(u) = t_idx;
                end
                queues{u}(end+1) = t_idx;
            end
        end

        % ---- 采样本周期末队列长度 (近似为周期内恒定) ----
        sum_q = 0;
        for u = 1:n_nodes
            sum_q = sum_q + numel(queues{u});
        end
        qlen_accum = qlen_accum + sum_q * CONN_LEN;
        n_slots_sampled = n_slots_sampled + CONN_LEN;
    end

    for u = 1:n_nodes
        for j = 1:numel(queues{u})
            if j == 1
                queue_delays(end+1)  = hol_become_time(u) - queues{u}(j);
            else
                queue_delays(end+1)  = steps - queues{u}(j);
            end
            access_delays(end+1) = NaN;
        end
    end

    th = success_slots / steps;
    miss_prob = 0;
    if n_slots_sampled > 0
        mean_qlen = qlen_accum / n_slots_sampled;
    else
        mean_qlen = 0;
    end
end
