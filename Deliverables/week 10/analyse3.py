import math

# Constants
K = 0.1          # Proportionality constant
Q_nominal = 3600.0 # Nominal charge capacity (C) ~1 Ah
R = 0.1          # Internal resistance (Ω)
A = 0.5          # Amplitude of exponential term (V)
B = 0.01         # Decay constant (A⁻¹ s⁻¹)
V_max = 4.0      # Fully charged voltage (V)
V_min = 0.0      # Fully discharged voltage (V)
i = 0.5          # Current in A

# Non-linear SoC model (sigmoid-like)
def calculate_soc(E0):
    V_mid = 3.45  # Midpoint of plateau
    k = 10        # Steepness of transition
    soc = 1 / (1 + math.exp(-k * (E0 - V_mid)))
    # Normalize to SoC = 1 at E0 = 4.0 V
    soc_max = 1 / (1 + math.exp(-k * (4.0 - V_mid)))
    soc_normalized = soc / soc_max
    # Scale to match realistic Li-ion profile (e.g., SoC ≈ 0.2 at 3.3 V)
    if E0 <= 3.3:
        soc_normalized *= 0.25  # Reduce capacity below plateau
    return max(0, min(soc_normalized, 1))

# Equation for V(t)
def calculate_vt(i, t, E0, Q):
    if Q - i * t <= 0:  # Avoid division by zero or negative capacity
        return 0
    term1 = K * (Q / (Q - i * t)) * i
    term2 = R * i
    term3 = A * math.exp(-B * i * t)
    vt = E0 - term1 - term2 + term3
    return max(vt, 0)  # Voltage cannot go below 0

# Calculate remaining time and simulate discharge
def simulate_discharge(E0, i):
    # Calculate SoC and capacity
    SoC = calculate_soc(E0)
    Q = SoC * Q_nominal  # Available capacity
    if Q <= 0:
        return 0, [0], [0]
    t_max = Q / i  # Remaining discharge time
    t_values = [t_max * x / 100 for x in range(101)]  # 101 points
    v_values = [calculate_vt(i, t, E0, Q) for t in t_values]
    return t_max, t_values, v_values

# Cases to simulate
initial_voltages = [4.0, 3.9, 3.8, 3.7, 3.6, 3.5, 3.4, 3.3, 3.2, 3.1, 3.0]

# Store results
results = []
for E0 in initial_voltages:
    t_max, t_vals, v_vals = simulate_discharge(E0, i)
    print(f"Initial Voltage: {E0} V, Remaining Time: {t_max:.1f} seconds")
    results.append((E0, t_vals, v_vals))