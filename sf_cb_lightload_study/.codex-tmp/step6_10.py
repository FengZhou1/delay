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

# ---- 6. start_rts hearers: nb boundary-aligned ----
old = """            for v = hearers.'
                if drawers(v)
                    continue;
                end
                node_state(v) = ST_SENSE;

                sense_count(v) = 0;
                sense_start(v) = t_now + rts_us;
                nb = busy_observe_tick(t_now);
                if nb < next_tick(v)
                    next_tick(v) = nb;
                end
            end"""
new = """            for v = hearers.'
                if drawers(v)
                    continue;
                end
                node_state(v) = ST_SENSE;
                sense_count(v) = 0;
                sense_start(v) = t_now + rts_us;
                nb = ceil((t_now + rts_us) / slot_us) * slot_us;
                if nb < next_tick(v)
                    next_tick(v) = nb;
                end
            end"""
src = sub_exact(src, old, new, '6.start_rts_hearers')
if src is None: sys.exit(1)

# ---- 7. process_cts_sector_end hearers ----
old = """                for v = hearers.'
                    node_state(v) = ST_SENSE;

                    sense_count(v) = 0;
                    nb = busy_observe_tick(t_now);
                    if nb < next_tick(v)
                        next_tick(v) = nb;
                    end
                end"""
new = """                for v = hearers.'
                    node_state(v) = ST_SENSE;
                    sense_count(v) = 0;
                    nb = ceil(t_now / slot_us) * slot_us;
                    if nb <= t_now
                        nb = t_now + slot_us;
                    end
                    if nb < next_tick(v)
                        next_tick(v) = nb;
                    end
                end"""
src = sub_exact(src, old, new, '7.CTS_hearers')
if src is None: sys.exit(1)

# ---- 8. AP_SIFS_PRE hearers ----
old = """                    for v = hearers.'
                        node_state(v) = ST_SENSE;

                        sense_count(v) = 0;
                        sense_start(v) = t_now + cts_us;
                        nb = busy_observe_tick(t_now);
                        if nb < next_tick(v)
                            next_tick(v) = nb;
                        end
                    end"""
new = """                    for v = hearers.'
                        node_state(v) = ST_SENSE;
                        sense_count(v) = 0;
                        sense_start(v) = t_now + cts_us;
                        nb = ceil(t_now / slot_us) * slot_us;
                        if nb <= t_now
                            nb = t_now + slot_us;
                        end
                        if nb < next_tick(v)
                            next_tick(v) = nb;
                        end
                    end"""
src = sub_exact(src, old, new, '8.SIFS_PRE_hearers')
if src is None: sys.exit(1)

# ---- 9. AP_SIFS_POST/DATA hearers ----
old = """                        for v = hearers.'
                            node_state(v) = ST_SENSE;

                            sense_count(v) = 0;
                            sense_start(v) = winner_data_end;
                            nb = busy_observe_tick(t_now);
                            if nb < next_tick(v)
                                next_tick(v) = nb;
                            end
                        end"""
new = """                        for v = hearers.'
                            node_state(v) = ST_SENSE;
                            sense_count(v) = 0;
                            sense_start(v) = winner_data_end;
                            nb = ceil(t_now / slot_us) * slot_us;
                            if nb <= t_now
                                nb = t_now + slot_us;
                            end
                            if nb < next_tick(v)
                                next_tick(v) = nb;
                            end
                        end"""
src = sub_exact(src, old, new, '9.DATA_hearers')
if src is None: sys.exit(1)

# ---- 10. winner requeue sb_cb at next boundary ----
old = """                    if queue_count(winner_id) > 0
                        if strcmp(mode,'sb_cb')
                            node_state(winner_id) = ST_SENSE;
                            sense_start(winner_id) = t_now;
                        else
                            node_state(winner_id) = ST_READY;
                        end

                        sense_count(winner_id) = 0;
                        next_tick(winner_id) = t_now;
                        if next_tick(winner_id) <= t_now
                            next_tick(winner_id) = t_now + slot_us;
                        end"""
new = """                    if queue_count(winner_id) > 0
                        if strcmp(mode,'sb_cb')
                            node_state(winner_id) = ST_SENSE;
                            sense_start(winner_id) = t_now;
                            next_tick(winner_id) = ceil(t_now / slot_us) * slot_us;
                            if next_tick(winner_id) <= t_now
                                next_tick(winner_id) = t_now + slot_us;
                            end
                        else
                            node_state(winner_id) = ST_READY;
                            next_tick(winner_id) = t_now;
                            if next_tick(winner_id) <= t_now
                                next_tick(winner_id) = t_now + slot_us;
                            end
                        end

                        sense_count(winner_id) = 0;"""
src = sub_exact(src, old, new, '10.winner_requeue')
if src is None: sys.exit(1)

# ---- 11. Remove unused busy_observe_tick function ----
old_fn = """

    function nt = busy_observe_tick(t_observe)
        nt = ceil(t_observe / slot_us) * slot_us;
        if nt <= t_observe
            nt = t_observe + slot_us;
        end
    end"""
if old_fn in src:
    src = src.replace(old_fn, '')
    print('removed busy_observe_tick function')
else:
    print('WARN: busy_observe_tick function not found')

with io.open(path, 'w', encoding='utf-8-sig', newline='') as f:
    f.write(src)
print('STEPS 6-10 saved')
