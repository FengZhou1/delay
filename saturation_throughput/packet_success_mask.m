function [n_ok,mask] = packet_success_mask(txop_start,data_slot_us,M,intervals)
%PACKET_SUCCESS_MASK Per-packet DATA success under selective retransmission.

    if M <= 0 || ~isfinite(M)
        error('packet_success_mask:BadM','M must be positive and finite.');
    end
    if M < 1-1e-12
        payload_end = txop_start + M*data_slot_us;
        overlap = 0;
        for ii = 1:size(intervals,1)
            overlap = overlap + max(0, ...
                min(payload_end,intervals(ii,2)) - ...
                max(txop_start,intervals(ii,1)));
        end
        mask = overlap <= 1e-9;
        n_ok = M * double(mask);
        return;
    end

    n_packets = round(M);
    mask = true(1,n_packets);
    for pp = 1:n_packets
        pkt_start = txop_start + (pp-1)*data_slot_us;
        pkt_end = pkt_start + data_slot_us;
        for ii = 1:size(intervals,1)
            if min(pkt_end,intervals(ii,2)) > ...
                    max(pkt_start,intervals(ii,1)) + 1e-9
                mask(pp) = false;
                break;
            end
        end
    end
    n_ok = sum(mask);
end
