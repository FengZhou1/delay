# Saturation throughput CTS experiments

Run all four CTS modes sequentially:

```matlab
cd('C:\Users\Administrator\Documents\delay\saturation_throughput');
run_saturation_cts_modes;
```

Each run creates a timestamped directory such as
`results_R10_cts/20260914_203000/`.

Run all modes with selective packet failure:

```matlab
run_saturation_cts_modes('packet');
```

After the CTS/airtime accounting fix, rerun only the affected protocols and
merge them with the unchanged protocol rows:

```matlab
run_saturation_cts_modes('txop',{'sf_cb','sb_cb','unslotted'},[2 3 4]);
```

`result1` is rewritten from the merged summary after the affected-protocol
rerun. Modes 2-4 are generated separately with the same merge logic.

Quasi-omni mode 5 (same gain in every direction), with a selectable peak gain:

```matlab
root = 'C:\Users\Administrator\Documents\delay\saturation_throughput\results_R10_cts\20260914_201134';
% default: -9 dB only; pass gains explicitly to run several
run_saturation_cts_mode(5,'txop',{},root);
run_saturation_cts_mode(5,'txop',{},root,[0 -9]);
```

Only the CTS-dependent protocols need to be re-run: pass the two CB protocols and the
remaining ones are copied from `result1` and drawn as `reference` curves, so the figure
still shows SF-CF / SB-CF / S7-AN without simulating them again:

```matlab
run_saturation_cts_mode(5,'txop',{'sf_cb','sb_cb'},root,[0 -9]);   % 2 protocols x 14 TXOP x 2 gains
```

Results land in `result5/qo_iso_0dB` and `result5/qo_iso_-9dB`, each with its own
figure `throughput_vs_Tp_result5_<variant>.png`.
Mode 3 (tapered physical quasi-omni) is kept for reference but is no longer in the
default mode list, which is now `[1 2 4 5]`.

Run one mode:

```matlab
run_saturation_cts_mode(1);
run_saturation_cts_mode(2);
run_saturation_cts_mode(3);
run_saturation_cts_mode(4);
```

Results are written to
`results_R10_cts/<timestamp>/result1` through `result4`.
Mode 3 uses the `0 dB` quasi-omni variant. Each result directory contains
`saturation_summary.csv` and one figure named
`throughput_vs_Tp_resultN.png`.

The TXOP scan is unchanged. The DATA payload unit remains 162.5 us while
the CTS reservation slot changes according to the selected mode.
