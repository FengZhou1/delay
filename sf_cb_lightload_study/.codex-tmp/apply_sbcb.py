import io, re, sys

path = r'C:\Users\Administrator\Documents\delay\sf_cb_lightload_study\simulate_lightload_continuous.m'
with io.open(path,'r',encoding='utf-8-sig',newline='') as f:
    src = f.read()

def sub(src, old, new, label):
    # Normalize whitespace: allow flexible blank-line whitespace via regex
    old_norm = re.sub(r'[ \t]*\n[ \t]*', '\n', old)
    # Escape special chars except allow \n as whitespace-flexible
    # Build a regex that treats each line's leading spaces as flexible
    lines = old.split('\n')
    pat_parts = []
    for ln in lines:
        stripped = ln.strip()
        if stripped == '':
            pat_parts.append(r'\s*')
        else:
            pat_parts.append(re.escape(stripped))
    pat = r'\s*' + r'\s*\n\s*'.join(pat_parts) + r'\s*'
    m = re.search(pat, src)
    if m is None:
        print('FAIL:', label)
        return None
    return src[:m.start()] + new + src[m.end():]

# ============================================================
# 1. enter_hol sb_cb
# ============================================================
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
src = sub(src, old, new, '1.enter_hol_sb_cb')
if src is None: sys.exit(1)

# ============================================================
# 2. process_tick ST_SENSE
# ============================================================
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
                    % No backoff: draw Bernoulli(q) at this boundary.
                else
                    next_tick(u) = difs_ok + 2 * slot_us;
                    return;
                end
            else
                next_tick(u) = t_now + slot_us;
                return;
            end
        end"""
src = sub(src, old, new, '2.ST_SENSE')
if src is None: sys.exit(1)

# ============================================================
# 3. process_tick ST_READY sb_cb
# ============================================================
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
src = sub(src, old, new, '3.ST_READY_sb_cb')
if src is None: sys.exit(1)

# ============================================================
# 4. process_timeout sb_cb
# ============================================================
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
src = sub(src, old, new, '4.process_timeout')
if src is None: sys.exit(1)

# ============================================================
# 5. ST_NAV -> sb_cb
# ============================================================
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
src = sub(src, old, new, '5.ST_NAV_sb_cb')
if src is None: sys.exit(1)

# ============================================================
# 6. start_rts hearers
# ============================================================
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
src = sub(src, old, new, '6.start_rts_hearers')
if src is None: sys.exit(1)

# ============================================================
# 7. process_cts_sector_end hearers
# ============================================================
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
src = sub(src, old, new, '7.CTS_hearers')
if src is None: sys.exit(1)

# ============================================================
# 8. AP_SIFS_PRE hearers
# ============================================================
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
src = sub(src, old, new, '8.SIFS_PRE_hearers')
if src is None: sys.exit(1)

# ============================================================
# 9. AP_SIFS_POST/DATA hearers
# ============================================================
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
src = sub(src, old, new, '9.DATA_hearers')
if src is None: sys.exit(1)

# ============================================================
# 10. winner requeue (sb_cb at next boundary)
# ============================================================
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
src = sub(src, old, new, '10.winner_requeue')
if src is None: sys.exit(1)

# ============================================================
# 11. Remove unused busy_observe_tick function (no callers remain)
# ============================================================
if 'busy_observe_tick' in src:
    m = re.search(r'\n    function nt = busy_observe_tick.*?\n    end\n', src, re.S)
    if m:
        src = src[:m.start()] + '\n' + src[m.end():]
        print('removed busy_observe_tick function')
    else:
        print('WARN: busy_observe_tick refs remain but function not found')

with io.open(path,'w',encoding='utf-8-sig',newline='') as f:
    f.write(src)
print('ALL 10 STEPS DONE')
