function [th, miss_prob] = proto_aloha_conn(steps, n_nodes, q, proto)
% PROTO_ALOHA_CONN 连接型ALOHA协议仿真（饱和模式）

    queues = cell(n_nodes, 1);
    success_slots = 0;

    CONN_LEN = proto.CONN_SLOT;
    num_rounds = floor(steps / CONN_LEN);
    busy_rem = 0;
    active = 0;

    for r = 1:num_rounds
        curr = (r - 1) * CONN_LEN;

        if busy_rem > 0
            busy_rem = busy_rem - 1;
            if busy_rem == 0 && active > 0
                success_slots = success_slots + proto.N_DATA;
                queues{active}(1) = [];
                active = 0;
            end
        else
            % 空闲时发起竞争
            attempts = [];
            for u = 1:n_nodes
                if ~isempty(queues{u}) && queues{u}(1) <= curr && rand() < q
                    attempts(end+1) = u;
                end
            end

            if isscalar(attempts)
                active = attempts(1);
                busy_rem = max(1, ceil(proto.M_BATCH));
            end
        end

        % 饱和到达：每个空队列节点产生新包
        for u = 1:n_nodes
            if isempty(queues{u})
                queues{u}(end+1) = curr;
            end
        end
    end

    th = success_slots / steps;
    miss_prob = 0;
end
