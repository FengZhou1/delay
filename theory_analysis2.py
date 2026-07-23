import numpy as np
from scipy.special import lambertw
import scipy.io as sio

n = 40
lambda_val = 5
slot_us = 5
conn_overhead = 38
conn_slot_us = conn_overhead * slot_us  # 190
lam = lambda_val * conn_slot_us * 1e-6  # 9.5e-4 per slot per node
lam_hat = n * lam  # 0.038

mat = sio.loadmat(r"C:\Users\Administrator\Documents\delay2.0\results\res_delay_sensing_free_connection_based_lambda_5.mat", squeeze_me=True, struct_as_record=False)
sim_delay_us = mat["mean_delay"]
sim_qstar = mat["best_q"]

def theory_T_at_q(M, delta, lam, lam_hat, n, q):
    """Compute T at a given q using eq (42)"""
    lam_r = lam / M
    
    # Check unsaturated
    x = lam_hat / (M - lam_hat * (M + delta - 1))
    if x >= 1.0/np.e:
        return None
    
    W0 = lambertw(-x, k=0).real
    Wm1 = lambertw(-x, k=-1).real
    p_L = np.exp(W0)
    
    alpha_u = (1 - n*lam_r*(M+delta-1)) / (1 - lam_r*(M+delta-1))
    
    A = 1.0 / (p_L * alpha_u * q)
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
        return None
    
    Wb = (M-1)/(2*lam)
    T = Wb + M + delta + r0/(lam*(1-r0))
    T_no_Wb = M + delta + r0/(lam*(1-r0))
    return T, T_no_Wb, r0

# ===== Check unsaturated region boundaries =====
print("=== Unsaturated region boundaries ===")
print("(Using M=M_sim, delta=1, 1 slot = 190 us)")
print(f"{'M':>6} {'x':>10} {'q_lower':>10} {'q_upper':>10} {'sim_q*':>10}")
for M_sim in [1.0, 2.0, 3.0, 4.0, 5.0]:
    delta = 1
    lam_r = lam / M_sim
    x = lam_hat / (M_sim - lam_hat * (M_sim + delta - 1))
    W0 = lambertw(-x, k=0).real
    Wm1 = lambertw(-x, k=-1).real
    q_lower = -1.0 / (n * Wm1)  # W_{-1} branch
    q_upper = -1.0 / (n * W0)   # W_0 branch
    idx = [1.0, 2.0, 3.0, 4.0, 5.0].index(M_sim) + 4
    print(f"{M_sim:>6.1f} {x:>10.6f} {q_lower:>10.6f} {q_upper:>10.6f} {sim_qstar[idx]:>10.4f}")

print()
print("=== T(q) curve for M=5, delta=1 ===")
M_sim = 5.0
delta = 1
print(f"{'q':>8} {'T':>12} {'T_noWb':>12} {'r0':>12}")
for q in [0.001, 0.005, 0.01, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 0.99]:
    result = theory_T_at_q(M_sim, delta, lam, lam_hat, n, q)
    if result:
        T, T_noWb, r0 = result
        print(f"{q:>8.3f} {T:>12.3f} {T_noWb:>12.3f} {r0:>12.8f}")
    else:
        print(f"{q:>8.3f}  (no root found)")

print()
print("=== T(q) curve for M=1, delta=1 ===")
M_sim = 1.0
delta = 1
print(f"{'q':>8} {'T':>12} {'T_noWb':>12} {'r0':>12}")
for q in [0.001, 0.005, 0.01, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 0.99]:
    result = theory_T_at_q(M_sim, delta, lam, lam_hat, n, q)
    if result:
        T, T_noWb, r0 = result
        print(f"{q:>8.3f} {T:>12.3f} {T_noWb:>12.3f} {r0:>12.8f}")
    else:
        print(f"{q:>8.3f}  (no root found)")

print()
print("=== KEY INSIGHT ===")
print("For light load (lambda_hat=0.038 << lambda_max),")
print("the unsaturated region is very wide: (q_lower ~ 0.005, q_upper ~ 0.5)")
print("T is DECREASING in q, so minimum T is at q_upper ~ 0.5")
print("But sim q* = 0.7-0.8, which is OUTSIDE the unsaturated region!")
print("This means the paper model does NOT directly apply to the simulation.")
print()
print("The paper assumes: request time = 1 time slot = 1 data packet time")
print("Sim has: request time = 1 round = 190us, data time = M*190us")
print("So request time = 1/M of data packet time (NOT equal!)")
print("This fundamentally changes the contention dynamics.")
