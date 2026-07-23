import numpy as np
from scipy.special import lambertw
import scipy.io as sio

# ========== Parameters ==========
n = 40
lambda_val = 5  # pkt/sta/s
slot_us = 5     # minislot in us
conn_overhead = 38  # 4+1+8*4+1
conn_slot_us = conn_overhead * slot_us  # 190 us = 1 slot in paper's sense
lam = lambda_val * conn_slot_us * 1e-6  # per-slot per-node arrival rate
lam_hat = n * lam
print(f"n={n}, lambda(per slot)={lam:.6f}, lambda_hat={lam_hat:.6f}")
print(f"conn_slot_us={conn_slot_us}")
print()

# ========== Simulation results ==========
mat = sio.loadmat(r"C:\Users\Administrator\Documents\delay2.0\results\res_delay_sensing_free_connection_based_lambda_5.mat", squeeze_me=True, struct_as_record=False)
sim_M = mat["M_VALUES"]
sim_delay_us = mat["mean_delay"]
sim_qd_us = mat["mean_qd"]
sim_ad_us = mat["mean_ad"]
sim_qstar = mat["best_q"]
print("=== Simulation Results (SF-CB, lambda=5) ===")
print(f"{'M':>6} {'MeanD(us)':>10} {'MeanD(slots)':>12} {'MeanQ':>8} {'MeanA':>8} {'q*':>8}")
for i in range(len(sim_M)):
    s = sim_delay_us[i]
    print(f"{sim_M[i]:>6.2f} {s:>10.1f} {s/conn_slot_us:>12.3f} {sim_qd_us[i]:>8.1f} {sim_ad_us[i]:>8.1f} {sim_qstar[i]:>8.4f}")
print()

# ========== Theory ==========
def theory_delay(M, delta, lam, lam_hat, n, eps=1e-10):
    x = lam_hat / (M - lam_hat * (M + delta - 1))
    if x >= 1.0/np.e:
        return None, None, None, None, None
    
    W0 = lambertw(-x, k=0).real
    p_L = np.exp(W0)
    
    lam_r = lam / M
    alpha_u = (1 - n*lam_r*(M+delta-1)) / (1 - lam_r*(M+delta-1))
    
    Wm1 = lambertw(-x, k=-1).real
    q_star = -1.0 / (n * Wm1) - eps
    if q_star <= 0 or q_star > 1:
        q_star = min(max(q_star, 1e-6), 0.9999)
    
    A = 1.0 / (p_L * alpha_u * q_star)
    
    M_int = max(1, int(round(M)))
    
    def f(r):
        return (1-lam)*r**(M_int+1) + lam*r**M_int - (lam*(A-1)+1)*r + lam*(A-1)
    
    r_vals = np.linspace(1e-12, 1-1e-12, 500000)
    f_vals = np.array([f(r) for r in r_vals])
    sign_changes = np.where(np.diff(np.sign(f_vals)))[0]
    
    r0 = None
    for idx in sign_changes:
        r0 = r_vals[idx] - f_vals[idx] * (r_vals[idx+1]-r_vals[idx]) / (f_vals[idx+1]-f_vals[idx])
        if 0 < r0 < 1:
            break
    
    if r0 is None:
        return None, None, None, None, None
    
    Wb = (M-1)/(2*lam)
    T_star = Wb + M + delta + r0/(lam*(1-r0))
    T_no_Wb = M + delta + r0/(lam*(1-r0))
    
    return T_star, T_no_Wb, p_L, q_star, r0

print("=== Theory: Paper model (M=M_sim, delta=1) ===")
print(f"{'M':>6} {'T*(slots)':>10} {'T*_noWb':>10} {'Wb':>10} {'p_L':>8} {'q*':>8} {'r0':>10}")
for M in [1.0, 2.0, 3.0, 4.0, 5.0]:
    T, T_noWb, pL, q, r0 = theory_delay(M, 1, lam, lam_hat, n)
    if T is not None:
        Wb = (M-1)/(2*lam)
        print(f"{M:>6.1f} {T:>10.3f} {T_noWb:>10.3f} {Wb:>10.3f} {pL:>8.4f} {q:>8.5f} {r0:>10.6f}")
    else:
        print(f"{M:>6.1f}  N/A")
print()

print("=== Theory: Sim-equivalent model (M=1, delta=M_sim) ===")
print(f"{'M_sim':>6} {'delta':>6} {'T*(slots)':>10} {'T_noWb':>10} {'p_L':>8} {'q*':>8} {'r0':>10}")
for M_sim in [1.0, 2.0, 3.0, 4.0, 5.0]:
    T, T_noWb, pL, q, r0 = theory_delay(1, M_sim, lam, lam_hat, n)
    if T is not None:
        print(f"{M_sim:>6.1f} {M_sim:>6.1f} {T:>10.3f} {T_noWb:>10.3f} {pL:>8.4f} {q:>8.5f} {r0:>10.6f}")
    else:
        print(f"{M_sim:>6.1f}  N/A")
print()

# ========== Comparison ==========
print("=== Comparison (all in slots, 1 slot = 190 us) ===")
print(f"{'M':>6} {'Sim':>10} {'Pap_noWb':>10} {'SimEq':>10} {'gap_Pap':>10} {'gap_SimEq':>10}")
for i, M_sim in enumerate([1.0, 2.0, 3.0, 4.0, 5.0]):
    sim_s = sim_delay_us[4+i] / conn_slot_us
    T_pap, T_pap_noWb, _, _, _ = theory_delay(M_sim, 1, lam, lam_hat, n)
    T_simeq, _, _, _, _ = theory_delay(1, M_sim, lam, lam_hat, n)
    gap_pap = sim_s - T_pap_noWb if T_pap_noWb else float("nan")
    gap_simeq = sim_s - T_simeq if T_simeq else float("nan")
    print(f"{M_sim:>6.1f} {sim_s:>10.3f} {T_pap_noWb:>10.3f} {T_simeq:>10.3f} {gap_pap:>10.3f} {gap_simeq:>10.3f}")
print()

# ========== Light-load analysis ==========
print("=== Light-load analysis (lambda->0, q->1) ===")
print("Paper model (M=M_sim, delta=1): T -> M + 1")
print("Sim-equivalent (M=1, delta=M_sim): T -> 1 + M_sim")
print("Both give the same result for light load!")
print()
print("The difference comes from NON-light-load effects:")
print("  1. Non-zero lambda causes contention (p_L < 1)")
print("  2. q* is not 1 but determined by Lambert W")
print("  3. The waiting time W_r = r0/(lambda*(1-r0)) differs")
print()

# ========== Detailed breakdown ==========
print("=== Detailed breakdown for M=5 ===")
M_sim = 5.0
print(f"\n--- Paper model (M=5, delta=1) ---")
T, T_noWb, pL, q, r0 = theory_delay(M_sim, 1, lam, lam_hat, n)
if T:
    Wb = (M_sim-1)/(2*lam)
    Wr_approx = r0/(lam*(1-r0))
    Dr = 1/(pL*1.0*1.0) + M_sim + 1 - 1  # using q=1, alpha=1 for light load
    Dr_actual = 1/(pL * (1-n*lam/M_sim*(M_sim+1-1))/(1-lam/M_sim*(M_sim+1-1)) * q) + M_sim + 1 - 1
    print(f"  Wb = {Wb:.3f} slots")
    print(f"  Wr = {Wr_approx:.3f} slots")
    print(f"  M+delta = {M_sim+1:.3f} slots")
    print(f"  T_noWb = {T_noWb:.3f} slots")
    print(f"  p_L = {pL:.6f}, q* = {q:.6f}, r0 = {r0:.8f}")
    print(f"  alpha_u = {(1-n*lam/M_sim*(M_sim+1-1))/(1-lam/M_sim*(M_sim+1-1)):.6f}")

print(f"\n--- Sim-equivalent model (M=1, delta=5) ---")
T2, T2_noWb, pL2, q2, r02 = theory_delay(1, M_sim, lam, lam_hat, n)
if T2:
    Wr2 = r02/(lam*(1-r02))
    print(f"  Wb = 0 (M=1)")
    print(f"  Wr = {Wr2:.3f} slots")
    print(f"  M+delta = {1+M_sim:.3f} slots")
    print(f"  T = {T2:.3f} slots")
    print(f"  p_L = {pL2:.6f}, q* = {q2:.6f}, r0 = {r02:.8f}")
    print(f"  alpha_u = {(1-n*lam*(1+M_sim-1))/(1-lam*(1+M_sim-1)):.6f}")

print(f"\n--- Simulation result for M=5 ---")
sim_s5 = sim_delay_us[8] / conn_slot_us
print(f"  Sim delay = {sim_s5:.3f} slots = {sim_delay_us[8]:.1f} us")
print(f"  q* = {sim_qstar[8]:.4f}")
print(f"  Gap from Paper_noWb = {sim_s5 - T_noWb:.3f} slots")
print(f"  Gap from SimEq = {sim_s5 - T2:.3f} slots")
