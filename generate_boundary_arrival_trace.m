function trace=generate_boundary_arrival_trace(lambda_per_node,cfg,seed,boundary_us)
%GENERATE_BOUNDARY_ARRIVAL_TRACE Theory-only Bernoulli boundary arrivals.
% This removes the sub-boundary phase wait and must not be used as the
% fairness trace for cross-protocol comparisons.
    if nargin<4 || isempty(boundary_us), boundary_us=190; end
    if mod(boundary_us,cfg.arrival_tick_us)~=0
        error('generate_boundary_arrival_trace:BadBoundary', ...
              'boundary_us must align with the common physical grid.');
    end
    p=lambda_per_node*boundary_us*1e-6;
    if p>1
        error('generate_boundary_arrival_trace:ProbabilityAboveOne', ...
              'lambda*boundary_us exceeds one Bernoulli arrival per boundary.');
    end
    times=(0:boundary_us:cfg.arrival_end_us-boundary_us).';
    stream=RandStream('mt19937ar','Seed',double(seed));
    mask=rand(stream,numel(times),cfg.n_nodes)<p;
    [rows,nodes]=find(mask);
    event_times=times(rows);
    ordered=sortrows([event_times,double(nodes)],[1,2]);
    if isempty(ordered)
        event_times=zeros(0,1);
        node_id=zeros(0,1);
    else
        event_times=ordered(:,1);
        node_id=ordered(:,2);
    end
    ids=cell(cfg.n_nodes,1);
    for u=1:cfg.n_nodes, ids{u}=find(node_id==u).'; end
    trace=struct('times_us',event_times,'node_id',node_id, ...
        'packet_ids_by_node',{ids},'n_packets',numel(event_times), ...
        'lambda_per_node',lambda_per_node,'bernoulli_p',p, ...
        'tick_us',boundary_us,'warmup_us',cfg.warmup_us, ...
        'measure_us',cfg.measure_us,'arrival_end_us',cfg.arrival_end_us, ...
        'hard_end_us',cfg.sim_hard_end_us,'seed',seed, ...
        'theory_boundary_only',true);
end
