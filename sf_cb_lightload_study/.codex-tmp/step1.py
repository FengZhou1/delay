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

# ---- 1. enter_hol sb_cb ----
old = """        elseif strcmp(mode,'sb_cb')
            % Start sensing immediately at the HOL instant (no 9 us
            % alignment); DIFS (34 us) completes in process_tick, then a
            % backoff window is drawn.
            node_state(u) = ST_SENSE;
            sense_count(u) = 0;
            sense_start(u) = t_hol;
            next_tick(u) = t_hol;"""
new = """        elseif strcmp(mode,'sb_cb')
            % Sensing starts at the next 9 us boundary after the HOL
            % instant; DIFS completes at align_up(sense_start + SIFS) +
            % 2*slot, and the RTS is transmitted at a boundary.
            node_state(u) = ST_SENSE;
            sense_count(u) = 0;
            sense_start(u) = t_hol;
            next_tick(u) = ceil(t_hol / slot_us) * slot_us;"""
src = sub_exact(src, old, new, '1.enter_hol_sb_cb')
if src is None: sys.exit(1)

with io.open(path, 'w', encoding='utf-8-sig', newline='') as f:
    f.write(src)
print('STEP 1 saved')
