import math
import matplotlib.pyplot as plt

# Constants (example values for a Li-ion battery model)
K = 0.1    # Proportionality constant
Q_nominal = 4320.0 # Nominal charge capacity (C) ~1.2 Ah at full charge
R = 0.1    # Internal resistance (Ω)
A = 0.5    # Amplitude of exponential term (V)
B = 0.01   # Decay constant (A⁻¹ s⁻¹)
V_max = 4.2  # Fully charged voltage (V)
V_min = 3.0  # Fully discharged voltage (V)

# Equation for V(t)
def calculate_vt(i, t, E0, Q):
    if Q - i * t <= 0:  # avoid division by zero or negative capacity
        return 0
    term1 = K * (Q / (Q - i * t)) * i
    term2 = R * i
    term3 = A * math.exp(-B * i * t)
    vt = E0 - term1 - term2 + term3
    return max(vt, 0)  # voltage cannot go below 0

# Simulate discharge
def simulate_discharge(E0, i):
    # Calculate state of charge (SoC) based on E0
    soc = (E0 - V_min) / (V_max - V_min)
    soc = max(0, min(soc, 1))  # Ensure SoC is between 0 and 1
    Q = soc * Q_nominal  # Available charge capacity
    if Q <= 0:  # If no charge available
        return [0], [0]
    t_max = Q / i  # theoretical max time
    t_values = [t_max * x / 1000 for x in range(1001)]
    v_values = [calculate_vt(i, t, E0, Q) for t in t_values]
    return t_values, v_values

# Simulate different cases
examples = [
    (4.0, 0.5, "Li-ion typical (4.0V, 0.5A)"),
    (3.9, 0.5, "Li-ion typical (3.9V, 0.5A)"),
    (3.8, 0.5, "Li-ion typical (3.8V, 0.5A)"),
    (3.7, 0.5, "Li-ion typical (3.7V, 0.5A)"),
    (3.6, 0.5, "Li-ion typical (3.6V, 0.5A)"),
    (3.5, 0.5, "Li-ion typical (3.5V, 0.5A)"),
    (3.4, 0.5, "Li-ion typical (3.4V, 0.5A)"),
    (3.3, 0.5, "Li-ion typical (3.3V, 0.5A)"),
    (3.2, 0.5, "Li-ion typical (3.2V, 0.5A)"),
    (3.1, 0.5, "Li-ion typical (3.1V, 0.5A)"),
    (3.0, 0.5, "Li-ion typical (3.0V, 0.5A)")
]

# Plotting
plt.figure(figsize=(10,6))
for E0, i, label in examples:
    t_vals, v_vals = simulate_discharge(E0, i)
    plt.plot(t_vals, v_vals, label=label)
    print(f"Final time for {label}: {t_vals[-1]:.1f} seconds")

plt.xlabel("Time (s)")
plt.ylabel("Voltage V(t) [V]")
plt.title("Battery Discharge Curves from Model Equation")
plt.legend()
plt.grid(True)
plt.show()