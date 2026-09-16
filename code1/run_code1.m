function result = run_code1()
%RUN_CODE1 Sector-sweep CTS delay experiment.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    result = run_R10_cts_mode(1);
end
