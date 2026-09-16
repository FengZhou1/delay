function result = run_code4()
%RUN_CODE4 Winner-directed CTS delay experiment.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    result = run_R10_cts_mode(4);
end
