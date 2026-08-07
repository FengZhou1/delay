# -*- coding: utf-8 -*-
import io, sys

path = r'C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\simulate_lightload_continuous.m'
with io.open(path, 'r', encoding='utf-8-sig', newline='') as f:
    src = f.read()

def sub_exact(src, old, new, label):
    n = src.count(old)
    if n == 0:
        print('FAIL (0 matches):', label)
        return None
    if n > 1:
        print('WARN %d matches:' % n, label)
    return src.replace(old, new)

# ---- 2. process_tick ST_SENSE ----
old = """        if node_state(u) == ST_SENSE
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % The channel is (or stays) busy: DIFS restarts from the
                % instant the channel becomes idle again.
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = busy_observe_tick(busy_end);
                return;
            end
            if t_now >= sense_start(u) + difs_us
                % DIFS (34 us) complete. Draw a backoff window or resume
                % from a previous freeze.
                if backoff_remaining(u) > 0
                    % Resume: restore backoff end from remaining time
                    backoff_end(u) = t_now + backoff_remaining(u);
                    backoff_remaining(u) = 0;
                else
                    % Fresh backoff: T ~ Uniform(0, W)
                    T = rand(stream) * W_us;
                    backoff_end(u) = t_now + T;
                    if ~is_saturation
                        pid = head_packet_id(u);
                        if pid > 0
                            probability_wait_us(pid) = probability_wait_us(pid) + T;
                        end
                    end
                end
                node_state(u) = ST_READY;
                sense_count(u) = 0;
            else
                % Still inside DIFS: keep the 9 us periodic busy check and
                % schedule the exact DIFS-completion event.
                next_tick(u) = t_now + slot_us;
                if sense_start(u) + difs_us < next_tick(u)
                    next_tick(u) = sense_start(u) + difs_us;
                end
                return;
            end
        end"""
new = """        if node_state(u) == ST_SENSE
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % The channel is (or stays) busy: DIFS restarts from the
                % instant the channel becomes idle again.
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = ceil(busy_end / slot_us) * slot_us;
                return;
            end
            if t_now >= sense_start(u) + sifs_us
                % DIFS complete: align to the next boundary after
                % (sense_start + SIFS), then count 2 full idle slots.
                difs_ok = ceil((sense_start(u) + sifs_us) / slot_us) * slot_us;
                if t_now >= difs_ok + 2 * slot_us
                    node_state(u) = ST_READY;
                    sense_count(u) = 0;
                else
                    next_tick(u) = difs_ok + 2 * slot_us;
                    return;
                end
            else
                next_tick(u) = t_now + slot_us;
                return;
            end
        end"""
src = sub_exact(src, old, new, '2.ST_SENSE')
if src is None: sys.exit(1)

with io.open(path, 'w', encoding='utf-8-sig', newline='') as f:
    f.write(src)
print('STEP 2 saved')
