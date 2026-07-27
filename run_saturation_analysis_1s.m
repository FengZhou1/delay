%RUN_SATURATION_ANALYSIS_1S Run the six-protocol saturation study.
%
% Default analysis profile:
%   40 saturated MLO stations, 8 sectors, fixed topology seed 20260325
%   M = [0.1 0.2 0.4 0.6 1:6 8 10 15 20]
%   fractional payloads are rounded to the nearest 9-us mmWave slot
%   0.2 s warm-up + 1 s measurement, no drain
%   protocol-specific coarse q scan + local logarithmic fine scan
%   3 independent evaluation seeds at the selected q
%
% Results and the legacy-style crossing plot are written below
% results_v2/saturation/<timestamp_config-hash>/.

saturation_cfg = default_saturation_config('analysis');
saturation_experiment = run_saturation_experiment(saturation_cfg);

fprintf('\nSaturation analysis complete.\n');
fprintf('Result directory: %s\n',saturation_experiment.output_dir);
fprintf('Throughput figure: %s\n',saturation_experiment.plot.png_path);
