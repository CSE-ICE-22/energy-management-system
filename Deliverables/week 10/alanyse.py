import math
import matplotlib.pyplot as plt

# Constants (example values for a Li-ion battery model)
K = 0.1    # Proportionality constant
Q = 4320.0 # Charge capacity (C) ~1.2 Ah
R = 0.1    # Internal resistance (Ω)
A = 0.5    # Amplitude of exponential term (V)
B = 0.01   # Decay constant (A⁻¹ s⁻¹)

# Equation for V(t)
def calculate_vt(i, t, E0):
    if Q - i * t <= 0:  # avoid division by zero or negative capacity
        return 0
    term1 = K * (Q / (Q - i * t)) * i
    term2 = R * i
    term3 = A * math.exp(-B * i * t)
    vt = E0 - term1 - term2 + term3
    return max(vt, 0)  # voltage cannot go below 0

# Example: simulate discharge
def simulate_discharge(E0, i):
    t_max = Q / i  # theoretical max time
    t_values = [t_max * x / 1000 for x in range(1001)]
    v_values = [calculate_vt(i, t, E0) for t in t_values]
    return t_values, v_values

# Simulate different cases
examples = [
    (3.7, 0.6, "Li-ion typical (3.7V, 0.6A)"),
    (3.7, 1.0, "Higher current (3.7V, 1A)"),
    (4.2, 0.6, "Fully charged (4.2V, 0.6A)")
]

plt.figure(figsize=(10,6))
for E0, i, label in examples:
    t_vals, v_vals = simulate_discharge(E0, i)
    plt.plot(t_vals, v_vals, label=label)

plt.xlabel("Time (s)")
plt.ylabel("Voltage V(t) [V]")
plt.title("Battery Discharge Curves from Model Equation")
plt.legend()
plt.grid(True)
plt.show()
