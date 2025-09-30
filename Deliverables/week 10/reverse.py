import math

K = 0.1    # Proportionality constant
Q = 4320.0 # Charge capacity (C), ~1.2 Ah
R = 0.1    # Internal resistance (Ω)
A = 0.5    # Amplitude of exponential term (V)
B = 0.01   # Decay constant (A⁻¹ s⁻¹)

# Function to calculate V(t)
def calculate_vt(i, t, E0):
    term1 = K * (Q / (Q - i * t)) * i
    term2 = R * i
    term3 = A * math.exp(-B * i * t)
    vt = E0 - term1 - term2 + term3
    return vt

# Function to find t where V(t) = 0 using binary search
def find_zero_vt(i, E0):
    t_max = Q / i
    t_min = 0.0
    tolerance = 1e-6
    max_iterations = 10000
    
    for _ in range(max_iterations):
        t_mid = (t_min + t_max) / 2
        vt_mid = calculate_vt(i, t_mid, E0)
        
        if abs(vt_mid) < tolerance:
            return t_mid
        
        if vt_mid > 0:
            t_min = t_mid
        else:
            t_max = t_mid
            
        if (t_max - t_min) < tolerance:
            break
    
    return None

# Function to compute numerical derivative dV/dt
def calculate_dvdt(i, t, E0, dt=1e-3):
    vt1 = calculate_vt(i, t, E0)
    vt2 = calculate_vt(i, t + dt, E0)
    return (vt2 - vt1) / dt

# Function to identify discharge regions
def identify_regions(i, E0):
    t_max = Q / i
    t_values = [t * t_max / 1000 for t in range(1001)]
    slope_threshold = 0.001
    
    regions = {'initial_decrease': [], 'plateau': [], 'final_decrease': []}
    
    for j in range(len(t_values) - 1):
        t = t_values[j]
        dvdt = calculate_dvdt(i, t, E0)
        
        if j < 10 and dvdt < -slope_threshold:  
            regions['initial_decrease'].append((t, calculate_vt(i, t, E0)))
        elif abs(dvdt) < slope_threshold:
            regions['plateau'].append((t, calculate_vt(i, t, E0)))
        elif dvdt < -slope_threshold:
            regions['final_decrease'].append((t, calculate_vt(i, t, E0)))
    
    return regions

# Main loop
while True:
    E0_input = input("Enter E0 (V, or 'q' to quit): ")
    if E0_input.lower() == 'q':
        print("Exiting program.")
        break
    
    i_input = input("Enter i (A, or 'q' to quit): ")
    if i_input.lower() == 'q':
        print("Exiting program.")
        break
    
    try:
        E0 = float(E0_input)
        i = float(i_input)
        
        if i <= 0:
            print("Error: Discharge current (i) must be positive.")
        else:
            print(f"\nProcessing inputs: E0 = {E0} V, i = {i} A")
            t_zero = find_zero_vt(i, E0)
            if t_zero is not None:
                print(f"V(t) becomes 0 at t ≈ {t_zero:.2f} s")
            else:
                print("No time t found where V(t) = 0.")
            
            regions = identify_regions(i, E0)
            print("\nDischarge Regions:")
            if regions['initial_decrease']:
                t_start, t_end = regions['initial_decrease'][0][0], regions['initial_decrease'][-1][0]
                print(f"Initial Decrease: t from {t_start:.2f} s to {t_end:.2f} s")
            if regions['plateau']:
                t_start, t_end = regions['plateau'][0][0], regions['plateau'][-1][0]
                print(f"Plateau Area: t from {t_start:.2f} s to {t_end:.2f} s")
            if regions['final_decrease']:
                t_start, t_end = regions['final_decrease'][0][0], regions['final_decrease'][-1][0]
                print(f"Final Decrease: t from {t_start:.2f} s to {t_end:.2f} s")
        
    except ValueError:
        print("Error: Please enter valid numerical values for E0 and i.")
    except Exception as e:
        print(f"An error occurred: {e}")
    
    print()  
