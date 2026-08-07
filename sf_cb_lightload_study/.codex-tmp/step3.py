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

# ---- 3. process_tick ST_READY sb_cb ----
old = """        if strcmp(mode,'sb_cb')
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % Freeze backoff: save remaining time, go back to sensing.
                backoff_remaining(u) = max(0, backoff_end(u) - t_now);
                node_state(u) = ST_SENSE;
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = busy_end;
                return;
            end
            if t_now >= backoff_end(u)
                flag = true;
            else
                next_tick(u) = min(backoff_end(u), t_now + slot_us);
            end
        else"""
new = """        if strcmp(mode,'sb_cb')
            [busy, busy_end] = sense_busy(u, t_now);
            if busy
                % Channel became busy during this slot: go back to sensing
                % from the busy end.
                node_state(u) = ST_SENSE;
                sense_count(u) = 0;
                sense_start(u) = busy_end;
                next_tick(u) = ceil(busy_end / slot_us) * slot_us;
                return;
            end
            % Slot boundary decision: Bernoulli(q), transmit immediately
            % if drawn, otherwise wait for the next boundary.
            if rand(stream) < q
                flag = true;
            else
                next_tick(u) = t_now + slot_us;
            end
        else"""
src = sub_exact(src, old, new, '3.ST_READY_sb_cb')
if src is None: sys.exit(1)

with io.open(path, 'w', encoding='utf-8-sig', newline='') as f:
    f.write(src)
print('STEP 3 saved')
