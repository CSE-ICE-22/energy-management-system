import math

# Define practical constant values for a Li-ion battery
E0 = 3.7   # Nominal open-circuit voltage (V), typical for Li-ion (3.0–4.2 V)
K = 0.1    # Proportionality constant, adjusted for gradual discharge
Q = 4320.0 # Charge capacity (C), equivalent to ~1.2 Ah (4320 C / 3600 s/Ah)
R = 0.1    # Internal resistance (Ω), typical for Li-ion (0.05–0.2 Ω)
A = 0.5    # Amplitude of exponential term (V), small transient drop
B = 0.01   # Decay constant (A⁻¹ s⁻¹), slower decay for battery discharge

# Function to calculate V(t)
def calculate_vt(i, t):
    # First term: K * (Q / (Q - i * t)) * i
    term1 = K * (Q / (Q - i * t)) * i
    
    # Second term: R * i
    term2 = R * i
    
    # Third term: A * e^(-B * i * t)
    term3 = A * math.exp(-B * i * t)
    
    # Total V(t)
    vt = E0 - term1 - term2 + term3
    return vt

# Get user input
try:
    i = float(input("Enter the value of i (discharge current in A): "))
    t = float(input("Enter the value of t (time in seconds): "))
    
    # Check for division by zero or invalid denominator
    if (Q - i * t) == 0:
        print("Error: Denominator (Q - i*t) cannot be zero. Please try different values.")
    else:
        # Calculate and display result
        result = calculate_vt(i, t)
        print(f"V(t) = {result:.4f} V for i = {i} A and t = {t} s")
        
except ValueError:
    print("Error: Please enter valid numerical values for i and t.")
except Exception as e:
    print(f"An error occurred: {e}")