import numpy as np
from scipy.special import lambertw
import scipy.io as sio

n = 40
lambda_val = 5
slot_us = 5
conn_overhead = 38
conn_slot_us = conn_overhead * slot_us
lam = lambda_val * conn_slot_us * 1e-6
lam_hat = n * lam

print("=" * 80)
print("PARAMETERS")
print(f"  n={n}, lam={lam:.6f}, lam_hat={lam_hat:.6f}, slot={conn_slot_us}us")
print()

mat = sio.loadmat(r"C:\Users\Administrator\Documents\delay2.0\results\res_delay_sensing_free_connection_based_lambda_5.mat", squeeze_me=True, struct_as_record=False)
sim_M = mat["M_VALUES"]
sim_delay_us = mat["mean_delay"]
sim_qd_us = mat["mean_qd"]
sim_ad_us = mat["mean_ad"]
sim_qstar = mat["best_q"]

print("SIMULATION RESULTS (SF-CB, lam=5)")
print(f"  {'M':>6} {'MeanD(us)':>10} {'Slots':>10} {'q*':>8}")
for i in range(len(sim_M)):
    s = sim_delay_us[i]
    print(f"  {sim_M[i]:>6.2f} {s:>10.1f} {s/conn_slot_us:>10.3f} {sim_qstar[i]:>8.4f}")
print()

def compute_theory(M, delta, lam, lam_hat, n, q):
    lam_r = lam / M
    x = lam_hat / (M - lam_hat * (M + delta - 1))
    if x >= 1.0 / np.e:
        return None
    W0_val = lambertw(-x, k=0).real
    p_L = np.exp(W0_val)
    alpha_u = (1 - n * lam_r * (M + delta - 1)) / (1 - lam_r * (M + delta - 1))
    A = 1.0 / (p_L * alpha_u * q)
    M_int = max(1, int(round(M)))
    def f(r):
        return (1 - lam) * r**(M_int + 1) + lam * r**M_int - (lam * (A - 1) + 1) * r + lam * (A - 1)
    r_vals = np.linspace(1e-14, 1 - 1e-14, 2000000)
    f_vals = np.array([f(r) for r in r_vals])
    sign_changes = np.where(np.diff(np.sign(f_vals)))[0]
    r0 = None
    for idx in sign_changes:
        r0 = r_vals[idx] - f_vals[idx] * (r_vals[idx+1] - r_vals[idx]) / (f_vals[idx+1] - f_vals[idx])
        if 0 < r0 < 1:
            break
    if r0 is None:
        return None
    Wr = r0 / (lam * (1 - r0))
    T_no_Wb = M + delta + Wr
    T = (M - 1) / (2 * lam) + M + delta + Wr
    return T, T_no_Wb, p_L, alpha_u, r0, Wr

print("=" * 80)
print("MODEL A: Paper (M=M_sim, delta=1)")
theory_A = {}
for M_sim in [1.0, 2.0, 3.0, 4.0, 5.0]:
    idx = list(sim_M).index(M_sim)
    q_sim = sim_qstar[idx]
    result = compute_theory(M_sim, 1, lam, lam_hat, n, q_sim)
    if result:
        T, T_noWb, pL, au, r0, Wr = result
        theory_A[M_sim] = T_noWb
        print(f"  M={M_sim:.0f} q={q_sim:.4f} pL={pL:.4f} Wr={Wr:.3f} T_noWb={T_noWb:.3f}")
print()

print("=" * 80)
print("MODEL B: Sim-equivalent (M=1, delta=M_sim)")
theory_B = {}
for M_sim in [1.0, 2.0, 3.0, 4.0, 5.0]:
    idx = list(sim_M).index(M_sim)
    q_sim = sim_qstar[idx]
    result = compute_theory(1, M_sim, lam, lam_hat, n, q_sim)
    if result:
        T, T_noWb, pL, au, r0, Wr = result
        theory_B[M_sim] = T
        print(f"  M={M_sim:.0f} q={q_sim:.4f} pL={pL:.4f} Wr={Wr:.3f} T={T:.3f}")
print()

print("=" * 80)
print("COMPARISON (slots, 1 slot = 190 us)")
print(f"  {'M':>4} {'Sim':>8} {'A_noWb':>8} {'B_simeq':>8} {'A-B':>8} {'Sim-B':>8} {'Sim-A':>8}")
for M_sim in [1.0, 2.0, 3.0, 4.0, 5.0]:
    idx = list(sim_M).index(M_sim)
    sim_s = sim_delay_us[idx] / conn_slot_us
    A = theory_A.get(M_sim, float("nan"))
    B = theory_B.get(M_sim, float("nan"))
    print(f"  {M_sim:>4.0f} {sim_s:>8.3f} {A:>8.3f} {B:>8.3f} {A-B:>8.3f} {sim_s-B:>8.3f} {sim_s-A:>8.3f}")
print()
print("  A-B:   batch-vs-single contention effect")
print("  Sim-B: residual gap (enqueue ordering, etc.)")
print("  Sim-A: total gap (user observes)")

print()
print("=" * 80)
M5 = 5.0
idx5 = list(sim_M).index(M5)
q5 = sim_qstar[idx5]
ra = compute_theory(M5, 1, lam, lam_hat, n, q5)
rb = compute_theory(1, M5, lam, lam_hat, n, q5)
print(f"M=5 DETAIL q={q5}")
if ra:
    T, T_noWb, pL, au, r0, Wr = ra
    ci_a = n*(lam/M5)/(pL*au)
    print(f"  A(M=5,d=1): T_noWb={T_noWb:.3f} Wr={Wr:.3f} pL={pL:.6f} lam_r={lam/M5:.6f} contention={ci_a:.6f}")
if rb:
    T, T_noWb, pL, au, r0, Wr = rb
    ci_b = n*lam/(pL*au)
    print(f"  B(M=1,d=5): T={T:.3f} Wr={Wr:.3f} pL={pL:.6f} lam_r={lam:.6f} contention={ci_b:.6f}")
    print(f"  Contention B/A = {ci_b/ci_a:.1f}x")
sim5 = sim_delay_us[idx5] / conn_slot_us
print(f"  Sim: {sim5:.3f} slots = {sim_delay_us[idx5]:.1f} us")
