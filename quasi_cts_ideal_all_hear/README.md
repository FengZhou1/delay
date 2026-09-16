# Quasi-omni CTS ideal all-hear study

This folder is self-contained relative to the main `delay` code:

- `run_quasi_cts_ideal_all_hear.m` runs all CTS-affected protocols
  (`sf_cb`, `sb_cb`, `unslotted`) for packet lengths 162.5 us and 650 us.
- `simulate_sb_cb_v2.m` is a local copy with a `quasi_omni_ideal` CTS mode.
- `simulate_unslotted_engine.m` is a local copy with the same CTS mode.
  The original delay-folder simulators are not modified.

The quasi-omni model assumes:

- one CTS transmission of 14.5 us;
- reservation conn-slot = 61 us;
- every non-transmitting STA decodes CTS and sets NAV.

Results and all-protocol figures are written to:

```text
R10_results/quasi_cts_ideal_all_hear/
    combined_summary_pkt162.5.csv
    combined_summary_pkt650.csv
    figures/
        all_protocols_delay_pkt162.5.png
        all_protocols_delay_pkt650.png
```
