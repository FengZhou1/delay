function [th, miss_prob] = proto_csma_rts(steps, n_nodes, q, proto, phy, node_sectors, n_sectors)
% PROTO_CSMA_RTS 毫米波定向CSMA/CA协议仿真（饱和模式，RTS/CTS�?% 核心机制：RTS竞争 -> AP扇区扫描(CTS) -> 定向数据传输
% 所有节点始终有包待发�?
    % ===================== 1. 初始化参�?=====================
    SENS = 10^((phy.RX_SENS_DBM - 30)/10);
    Int_Matrix = phy.Int_Matrix;
    Int_Matrix_T = Int_Matrix.';
    AP_Sector_Tx_Matrix = phy.AP_Sector_Tx_Matrix;
    AP_Rx_Matrix = phy.AP_Rx_Matrix;

    DIFS_LIMIT = proto.DIFS;
    N_RTS = proto.N_RTS;
    N_CTS = proto.N_CTS;
    N_DATA = proto.N_DATA;
    SIFS = proto.SIFS;
    DATA_SINR_TH = 21;
    CTS_SINR_TH = 6;
    NOISE_LINEAR = 10^((-90 - 30) / 10);
    SWEEP_DUR = n_sectors * N_CTS;
    ICR_TIMEOUT = SIFS + SWEEP_DUR + 2;

    STA_IDLE = 0; STA_TX_RTS = 1; STA_WAIT_ICR = 2; STA_TX_DATA = 3; STA_WAIT_TX = 4;
    AP_IDLE = 0; AP_SIFS = 1; AP_SWEEP = 2; AP_RX_DATA = 3; AP_SIFSPOST = 4;

    sta_state = zeros(n_nodes, 1);
    sta_timer = zeros(n_nodes, 1);
    nav = zeros(n_nodes, 1);
    difs = zeros(n_nodes, 1);
    rts_col = false(n_nodes, 1);

    ap_state = AP_IDLE;
    ap_timer = 0;
    winner_sta_id = 0;
    is_current_data_collided = false;
    cts_sector_id = 0;
    cts_sector_seen_slots = 0;
    cts_sector_all_ok = false(n_nodes, 1);

    has_packet = false(n_nodes, 1);
    success_slots = 0;
    total_sensing_events = 0;
    missed_detection_events = 0;

    sector_masks = false(n_nodes, n_sectors);
    for s = 1:n_sectors
        sector_masks(:, s) = (node_sectors == s);
    end

    % ===================== 2. 主仿真循�?=====================
    for t = 1:steps
        sweep_to_data_after_slot = false;

        % --- 2.1 饱和到达 ---
        new_pkt = ~has_packet;
        if any(new_pkt)
            has_packet(new_pkt) = true;
        end

        % --- 2.2 AP 状态与波束方向 ---
        ap_sending_energy = false; ap_current_sector = 0;
        if ap_state == AP_SWEEP
            time_swept = SWEEP_DUR - ap_timer;
            ap_current_sector = min(floor(time_swept / N_CTS) + 1, n_sectors);
            ap_sending_energy = true;
        end

        % --- 2.3 信道侦听 (CCA) ---
        tx_mask = (sta_state == STA_TX_RTS) | (sta_state == STA_TX_DATA);
        listeners = ~tx_mask;
        has_sta_tx = any(tx_mask);
        is_any_tx = has_sta_tx || ap_sending_energy;

        if has_sta_tx
            pwr_inter = Int_Matrix_T * double(tx_mask);
        elseif ap_sending_energy
            pwr_inter = zeros(n_nodes, 1);
        else
            pwr_inter = [];
        end

        if ap_sending_energy && ap_current_sector > 0
            ap_pwr = AP_Sector_Tx_Matrix(:, ap_current_sector);
            pwr_inter = pwr_inter + ap_pwr;
        end

        if is_any_tx
            sensed_busy = (pwr_inter > SENS) & listeners;
        else
            sensed_busy = false(n_nodes, 1);
        end
        is_channel_busy = sensed_busy;

        if is_any_tx
            n_listeners = sum(listeners);
            total_sensing_events = total_sensing_events + n_listeners;
            missed_detection_events = missed_detection_events + sum(listeners & ~sensed_busy);
        end

        % --- 2.4 Backoff ---
        nav(nav > 0) = nav(nav > 0) - 1;
        can_count = (sta_state == STA_IDLE) & (nav == 0) & ~is_channel_busy;
        difs(~can_count) = 0;
        difs(can_count) = difs(can_count) + 1;

        % --- 2.5 TX Decision (RTS) ---
        ready = (sta_state == STA_IDLE) & has_packet & (difs > DIFS_LIMIT);
        if any(ready)
            will_tx = ready & (rand(n_nodes, 1) < q);
            if any(will_tx)
                sta_state(will_tx) = STA_TX_RTS;
                sta_timer(will_tx) = N_RTS;
                difs(will_tx) = 0;
                rts_col(will_tx) = false;
            end
        end

        % --- 2.6 RTS Collision Check ---
        tx_rts = (sta_state == STA_TX_RTS);
        if nnz(tx_rts) > 1, rts_col(tx_rts) = true; end
        if ap_state ~= AP_IDLE, rts_col(tx_rts) = true; end

        finishing_rts = tx_rts & (sta_timer == 1);
        if any(finishing_rts) && ap_state == AP_IDLE
            if nnz(finishing_rts) == 1
                fin_idx = find(finishing_rts, 1);
                if ~rts_col(fin_idx)
                    winner_sta_id = fin_idx;
                    ap_state = AP_SIFS; ap_timer = SIFS;
                end
            end
        end

        % --- 2.7 AP State Machine ---
        if ap_state ~= AP_IDLE
            if ap_state == AP_SWEEP && ap_timer == 1
                sweep_to_data_after_slot = true;
            else
                ap_timer = ap_timer - 1;
                if ap_timer == 0
                    switch ap_state
                        case AP_SIFS
                            ap_state = AP_SWEEP;
                            ap_timer = SWEEP_DUR;

                        case AP_SIFSPOST
                            ap_state = AP_RX_DATA;
                            ap_timer = N_DATA;

                        case AP_RX_DATA
                            ap_state = AP_IDLE;
                    end
                end
            end
        end

        % Data Phase SINR Check (Uplink)
        if ap_state == AP_RX_DATA && winner_sta_id > 0 && ~is_current_data_collided
            if sta_state(winner_sta_id) == STA_TX_DATA
                P_A = AP_Rx_Matrix(winner_sta_id, winner_sta_id);
                if any(tx_rts)
                    I_sinr = sum(AP_Rx_Matrix(winner_sta_id, tx_rts));
                else
                    I_sinr = 0;
                end
                SINR_dB = 10 * log10(P_A / (NOISE_LINEAR + I_sinr + eps));
                if SINR_dB < DATA_SINR_TH, is_current_data_collided = true; end
            else
                is_current_data_collided = true;
            end
        end

        % --- 2.8 AP Sweep Logic & CTS Reception (Downlink) ---
        if ap_state == AP_SWEEP && ap_current_sector > 0
            rem_sweep = ap_timer;
            total_nav_dur = rem_sweep + SIFS + N_DATA;
            in_sector_all = sector_masks(:, ap_current_sector);

            if any(in_sector_all)
                if ap_current_sector ~= cts_sector_id
                    cts_sector_id = ap_current_sector;
                    cts_sector_seen_slots = 0;
                    cts_sector_all_ok = in_sector_all;
                end

                P_cts_all = AP_Sector_Tx_Matrix(:, ap_current_sector);

                if any(tx_rts)
                    P_inter_all = Int_Matrix_T * double(tx_rts);
                else
                    P_inter_all = zeros(n_nodes, 1);
                end

                SINR_all_dB = 10 * log10(P_cts_all ./ (P_inter_all + NOISE_LINEAR + eps));
                slot_decoded = in_sector_all & listeners & (SINR_all_dB >= CTS_SINR_TH);

                cts_sector_seen_slots = cts_sector_seen_slots + 1;
                if cts_sector_seen_slots == 1
                    cts_sector_all_ok = slot_decoded;
                else
                    cts_sector_all_ok = cts_sector_all_ok & slot_decoded;
                end

                if cts_sector_seen_slots >= N_CTS
                    cts_decoded_final = cts_sector_all_ok;

                    if winner_sta_id > 0 && in_sector_all(winner_sta_id)
                        if sta_state(winner_sta_id) == STA_WAIT_ICR && cts_decoded_final(winner_sta_id)
                            sta_state(winner_sta_id) = STA_WAIT_TX;
                            sta_timer(winner_sta_id) = rem_sweep + SIFS - 1;
                        end
                        cts_decoded_final(winner_sta_id) = false;
                    end

                    nav_update_mask = in_sector_all & cts_decoded_final;
                    if any(nav_update_mask)
                        nav(nav_update_mask) = max(nav(nav_update_mask), total_nav_dur);

                        reset_icr = nav_update_mask & (sta_state == STA_WAIT_ICR);
                        if any(reset_icr)
                            sta_state(reset_icr) = STA_IDLE;
                            difs(reset_icr) = 0;
                        end
                    end

                    cts_sector_seen_slots = 0;
                    cts_sector_all_ok(:) = false;
                end
            end
        end

        % --- 2.9 STA State Machine Update ---
        active = (sta_state ~= STA_IDLE);
        if any(active)
            sta_timer(active) = sta_timer(active) - 1;
            finished = active & (sta_timer == 0);

            if any(finished)
                curr_states = sta_state;

                fin_rts = finished & (curr_states == STA_TX_RTS);
                if any(fin_rts), sta_state(fin_rts) = STA_WAIT_ICR; sta_timer(fin_rts) = ICR_TIMEOUT; end

                fin_icr = finished & (curr_states == STA_WAIT_ICR);
                if any(fin_icr), sta_state(fin_icr) = STA_IDLE; difs(fin_icr) = 0; end

                fin_wait = finished & (curr_states == STA_WAIT_TX);
                if any(fin_wait), sta_state(fin_wait) = STA_TX_DATA; sta_timer(fin_wait) = N_DATA; end

                fin_data = finished & (curr_states == STA_TX_DATA);
                if any(fin_data)
                    if winner_sta_id > 0 && fin_data(winner_sta_id) && ~is_current_data_collided
                        success_slots = success_slots + N_DATA;
                        has_packet(winner_sta_id) = false;
                    end
                    sta_state(fin_data) = STA_IDLE;
                    difs(fin_data) = 0;
                end
            end
        end

        if sweep_to_data_after_slot
            ap_state = AP_SIFSPOST;
            ap_timer = SIFS;
            is_current_data_collided = false;
        end
    end

    th = success_slots / steps;
    if total_sensing_events > 0
        miss_prob = missed_detection_events / total_sensing_events;
    else
        miss_prob = 0;
    end
end
