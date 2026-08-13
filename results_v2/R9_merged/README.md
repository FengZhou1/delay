# R9_merged

Merged delay results: R9 (`C:\Users\Administrator\Documents\delay\results_v2\20260813_181654_0bc5dfd4992b`) plus boundary-q supplement re-runs.

- Supplement target conditions: 24
- Rows replaced by supplement evals: 36
- Supplement scan: 3 seeds x 3 tune runs, a q counts as stable only
  when all 3 seeds are stable; eval accepts completion>=0.95 and
  stable; otherwise falls back to the next stable q to the left.

## Files

- `summary.csv`: merged condition table (supplement rows updated)
- `boundary_supplement_report.csv`: old vs new q/delay per re-tuned point
- `figures/`: delay-by-M curves for both lambda values
- `supplement_work/supplement_results.mat`: boundary supplement data
- `supplement_work_pointfix/supplement_results.mat`: point-fix data
- `supplement_work_unsl30/supplement_results.mat`: unslotted lam30 point-fix
- `supplement_work_unsl_orig/supplement_results.mat`: unslotted original-flow re-run
