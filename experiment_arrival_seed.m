function seed = experiment_arrival_seed(cfg,lambda_eff,run_index, ...
        seed_offset,load_index,lambda_index)
%EXPERIMENT_ARRIVAL_SEED Deterministic seed for a physical arrival trace.
%   With common_arrivals_by_effective_rate enabled, conditions with the same
%   effective per-node arrival rate and run index use the same physical
%   arrival trace, regardless of load label, protocol, or M.

    if nargin < 4 || isempty(seed_offset)
        seed_offset = 0;
    end
    if nargin < 5 || isempty(load_index)
        load_index = 0;
    end
    if nargin < 6 || isempty(lambda_index)
        lambda_index = 0;
    end
    if ~isscalar(lambda_eff) || ~isfinite(lambda_eff) || lambda_eff < 0
        error('experiment_arrival_seed:BadRate', ...
            'lambda_eff must be a finite non-negative scalar.');
    end

    use_common = isfield(cfg,'common_arrivals_by_effective_rate') && ...
                 logical(cfg.common_arrivals_by_effective_rate);
    if use_common
        rate_key = round(double(lambda_eff)*1e6);
        raw = double(cfg.traffic_seed_base) + double(seed_offset) + ...
              rate_key + double(run_index);
    else
        raw = double(cfg.traffic_seed_base) + double(seed_offset) + ...
              double(load_index)*1000000 + ...
              double(lambda_index)*10000 + double(run_index);
    end
    seed = mod(raw,2^31-2)+1;
end
