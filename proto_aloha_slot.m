function [th, queue_delays, access_delays, miss_prob, mean_qlen] = proto_aloha_slot(arrivals, n_nodes, q, proto)
    SLOT_LEN = proto.N_DATA;
    steps = size(arrivals, 1);
    num_rounds = floor(steps / SLOT_LEN);
    queues = cell(n_nodes, 1);
    hol_become_time = zeros(n_nodes, 1);
    queue_delays = [];
    access_delays = [];
    success_slots = 0;
    qlen_accum = 0;          % 时间平均队列长度累积量 (包*slot)
    n_slots_sampled = 0;

    for r = 1:num_rounds
        curr = (r-1) * SLOT_LEN;

        % ---- 竞争发送 ----
        attempts = [];
        for u = 1:n_nodes
            if ~isempty(queues{u}) && queues{u}(1) <= curr && rand() < q
                attempts(end+1) = u;
            end
        end

        if isscalar(attempts)
            u = attempts(1);
            success_slots = success_slots + SLOT_LEN;
            % 总时延 = (到达时间 → 传输完成时刻)
            % 传输完成 = curr + SLOT_LEN
            completion = curr + SLOT_LEN;
            queue_delays(end+1)   = hol_become_time(u) - queues{u}(1);
            access_delays(end+1)  = completion - hol_become_time(u);
            queues{u}(1) = [];
            if ~isempty(queues{u})
                hol_become_time(u) = completion;
            end
        end

        % ---- 本周期内新到达的包 ----
        for k = 1:SLOT_LEN
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
        qlen_accum = qlen_accum + sum_q * SLOT_LEN;
        n_slots_sampled = n_slots_sampled + SLOT_LEN;
    end

    % ---- 回填未完成的包（统计队列中所有包，作为下限） ----
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

    th = success_slots / (num_rounds * SLOT_LEN);
    miss_prob = 0;
    if n_slots_sampled > 0
        mean_qlen = qlen_accum / n_slots_sampled;
    else
        mean_qlen = 0;
    end
end
