function [th, miss_prob] = proto_aloha_slot(steps, n_nodes, q, proto)
% PROTO_ALOHA_SLOT 时隙ALOHA协议仿真（饱和模式）

    SLOT_LEN = proto.N_DATA;
    num_rounds = floor(steps / SLOT_LEN);
    queues = cell(n_nodes, 1);
    success_slots = 0;

    for r = 1:num_rounds
        curr = (r - 1) * SLOT_LEN;

        % 先进行本轮竞争尝试
        attempts = [];
        for u = 1:n_nodes
            if ~isempty(queues{u}) && queues{u}(1) <= curr && rand() < q
                attempts(end+1) = u;
            end
        end

        if isscalar(attempts)
            u = attempts(1);
            success_slots = success_slots + SLOT_LEN;
            queues{u}(1) = [];
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
