function run_all_protocols()
    clc;
    fprintf('=== Batch Running All Protocols (Saturation Throughput Only) ===\n');

    script_aloha_slot();
    script_aloha_conn();
    script_csma_basic();
    script_csma_rts();
    script_sub7_clean();
    script_sub7_busy();

    fprintf('=== All simulations completed. Results saved in /results ===\n');
end
