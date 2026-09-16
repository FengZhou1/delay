# R10 CTS delay experiments

Run all four CTS modes sequentially:

```matlab
cd('C:\Users\Administrator\Documents\delay');
run_R10_cts_modes;
```

The run creates one timestamped directory such as
`R10_results/20260914_203000/`. `result2` through `result4` merge with the
`result1` generated in that same run, so stale result directories are not
reused.

Protocols simulated per mode:

| mode | simulated | reused from the references |
| --- | --- | --- |
| 1 | `sf_cb`, `sb_cf`, `sb_cb` | `sf_cf`, `s7_clean`, `s7_busy` |
| 2, 4, 5 | `sf_cb`, `sb_cb` | `sf_cf`, `sb_cf`, `s7_clean`, `s7_busy` |
| 3 (legacy) | `sf_cb`, `sb_cb` | `sf_cf`, `sb_cf`, `s7_clean`, `s7_busy` |
Mode 3 (physical quasi-omni with the tapered AWV) is kept for reference but is no
longer part of the default mode list; the default list is `[1 2 4 5]`.
Mode 5 uses a quasi-omni pattern whose gain is the same in every direction (no
steering, no nulls), so the CTS coverage is set by the link budget only.

`unslotted` is no longer run or plotted by default.  Its simulator is kept,
and it can still be requested explicitly (for example
`run_R10_cts_mode(2,'txop',{'sf_cb','sb_cb','unslotted'},output_root)`), but
it is filtered out of the merged summaries and figures otherwise.

`sf_cf`, `sb_cf`, `s7_clean` and `s7_busy` never read a CTS parameter,
so their results are identical in all four modes. `sb_cf` is simulated only
in mode 1, where it also produces the `M=20` rows that modes 2-4 reuse; pass
`{'sf_cb','sb_cf','sb_cb'}` explicitly to restore the old behaviour. Mode 1
reads `sf_cf`, `s7_clean` and `s7_busy` from
`R10_results/lambda_sweep/summary.csv` (`lambda_sweep_pkt650` for 650 us);
modes 2-4 read them from `result1/summary_pkt*.csv` of the same run.

Offered loads are `[0.1, 0.2, 0.3, 0.5, 0.6]`.  Reference rows may come from
an older run with a wider grid; `restrict_summary` trims every merged summary
to the scanned loads, so the merged CSV and the figure always share one grid.

Resume an interrupted run in its existing timestamped directory:

```matlab
output_root = 'R10_results\20260914_201159';
run_R10_cts_modes('txop',{},1:4,output_root);
```

Raw summaries are reused automatically. The run directory that carries the
current config hash is preferred; a summary from an earlier run is reused only
when its condition matrix (protocols, M values, loads, load modes) is exactly
the one requested here, and a warning is printed when that older summary came
from a different config or code fingerprint. Summaries with a different
condition set are ignored instead of being merged by accident. This is useful
when an interruption occurs after `run_experiment` finishes but before the
merged `resultN/summary_pkt*.csv` files are written.

Run only selected packet durations (default is both):

```matlab
output_root = 'R10_results\20260914_201159';
run_R10_cts_modes('txop',{},[3 4],output_root,[650]);   % 650 us only
```

When a packet duration is not re-run, any older summary of that duration stays
untouched in the result directory, so remove it if it was produced by an older
code version.

Quasi-omni mode 5, with a selectable peak gain:

```matlab
output_root = 'R10_results\20260914_201159';
run_R10_cts_modes('txop',{},5,output_root);                        % default: -9 dB only
run_R10_cts_modes('txop',{},[4 5],output_root,[162.5 650],[0 -9]); % 0 dB and -9 dB
```

The 6th argument (`qo_iso_gains_db`) only affects mode 5; when it is omitted, mode 5
runs at -9 dB.  Results land in `result5/qo_iso_<gain>dB`.

Run all modes with selective packet failure:

```matlab
run_R10_cts_modes('packet');
```

Rerun only selected protocols in modes 2-4 within the same timestamped root:

```matlab
output_root = 'R10_results\20260914_203000';
run_R10_cts_mode(2,'txop',{'sf_cb','sb_cb','unslotted'},output_root);
run_R10_cts_mode(3,'txop',{'sf_cb','sb_cb','unslotted'},output_root);
run_R10_cts_mode(4,'txop',{'sf_cb','sb_cb','unslotted'},output_root);
```

This keeps `result1` unchanged and merges the corrected rows with the
`result1` reference rows. The raw summary of that mode is not reused any
more, because its condition set differs; delete `resultN/raw` first if the
stale directory should be removed as well.

Run one mode:

```matlab
run('code1/run_code1.m');   % sector sweep
run('code2/run_code2.m');   % ideal quasi-omni
run('code3/run_code3.m');   % physical quasi-omni, 0 dB
run('code4/run_code4.m');   % winner-directed CTS
```

Results are written to:

```text
R10_results/<timestamp>/result1/
R10_results/<timestamp>/result2/
R10_results/<timestamp>/result3/qo_0dB/
R10_results/<timestamp>/result4/
```

Each directory contains `summary_pkt162.5.csv`, `summary_pkt650.csv`,
and one combined mean-delay figure per packet duration.

CTS beam steering: `calculate_ula_awv_gain` used to evaluate the array
response with an extra conjugation (`w(:)' * a`) while `build_ula_awv`
already builds `w = conj(a(theta_0))`.  The physical CTS beam therefore
pointed at the mirrored angle instead of the winner, and 9 of 40 winners could
not decode their own CTS.  It is fixed (`w(:).' * a`), so modes 3 and 4 must
be re-run; modes 1 and 2 do not use this function and stay valid.

The default DATA failure mode is `txop`, which retries the whole TXOP.
Control-frame and DATA-frame SINR thresholds are 6 dB and 20 dB,
respectively.

`result3` uses a 0 dB quasi-omni CTS peak gain. In the completed
`pkt162.5` summary no CB protocol finds a stable `q` at any load, so those
curves stay empty there; the reference rows are still merged into the figure.
