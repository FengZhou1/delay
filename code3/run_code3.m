function result = run_code3()
%RUN_CODE3 Physical quasi-omni CTS delay experiment (0 dB peak gain).
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    result = run_R10_cts_mode(3);
end
