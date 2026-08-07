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

# ---- 4. process_timeout sb_cb ----
old = """        if strcmp(mode,'sb_cb')
            % Re-sense from the exact timeout instant; DIFS completes at
            % t_now + 34 us if the channel stays idle, then a backoff
            % window is drawn.
            node_state(u) = ST_SENSE;
            sense_start(u) = t_now;
            next_tick(u) = t_now;
        else"""
new = """        if strcmp(mode,'sb_cb')
            % Re-sense from the timeout instant; DIFS completes at
            % align_up(sense_start + SIFS) + 2*slot, RTS at a boundary.
            node_state(u) = ST_SENSE;
            sense_start(u) = t_now;
            next_tick(u) = ceil(t_now / slot_us) * slot_us;
        else"""
src = sub_exact(src, old, new, '4.process_timeout')
if src is None: sys.exit(1)

# ---- 5. ST_NAV -> sb_cb ----
old = """        if node_state(u) == ST_NAV
            if strcmp(mode,'sb_cb')
                node_state(u) = ST_SENSE;
                sense_start(u) = t_now;
            else"""
new = """        if node_state(u) == ST_NAV
            if strcmp(mode,'sb_cb')
                node_state(u) = ST_SENSE;
                sense_start(u) = t_now;
                next_tick(u) = ceil(t_now / slot_us) * slot_us;
                sense_count(u) = 0;
                return;
            else"""
src = sub_exact(src, old, new, '5.ST_NAV_sb_cb')
if src is None: sys.exit(1)

with io.open(path, 'w', encoding='utf-8-sig', newline='') as f:
    f.write(src)
print('STEPS 4-5 saved')
