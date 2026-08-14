function enabled = is_batch_txop_mode(cfg)
%IS_BATCH_TXOP_MODE True when complete M-packet request admission is enabled.
    enabled = strcmp(txop_mode(cfg), 'batch_M');
end
