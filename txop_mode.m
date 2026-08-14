function mode = txop_mode(cfg)
%TXOP_MODE Return the normalized TXOP admission mode.
%   ready_queue: a non-empty packet queue may contend.
%   batch_M:     only complete M-packet requests may contend.

    if ~isfield(cfg, 'txop_mode') || isempty(cfg.txop_mode)
        mode = 'ready_queue';
    else
        mode = lower(char(cfg.txop_mode));
    end
    if strcmp(mode, 'batch_m')
        mode = 'batch_M';
    end
    if ~ismember(mode, {'ready_queue', 'batch_M'})
        error('txop_mode:BadMode', ...
              'cfg.txop_mode must be ''ready_queue'' or ''batch_M''.');
    end
end
