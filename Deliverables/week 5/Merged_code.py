import time

# Simulated pins (for state tracking)
mosfet_pin = False  # False = HIGH (P-MOSFET OFF), True = LOW (Charger ON)
backlight_pin = True  # True = HIGH (ON), False = LOW (OFF)

# SoC thresholds for 3.7V Li-ion
#soc_low = 3.65  # 40% SoC
#soc_high = 3.8  # 70% SoC
soc_low = 0.0  # 0% SoC
soc_high = 4.2  # 100% SoC
switch_state = False

# Backlight control
backlight_timeout = 30  # 30 seconds
last_interaction = time.time()
backlight_on = True

def map_value(x, in_min, in_max, out_min, out_max):
    """Map a value from one range to another."""
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min

def constrain(x, min_val, max_val):
    """Constrain a value to a range."""
    return max(min_val, min(x, max_val))

def simulate_lcd_print(line, col, text):
    """Simulate LCD printing."""
    print(f"LCD [Line {line}, Col {col}]: {text}")

def calculate_time_remaining(voltage, current_load, current_charger, time_to_reach_voltage):
    """
    Calculate the remaining time (discharge time) based on given parameters.
    
    Parameters:
    voltage (float): The current battery voltage (in volts)
    current_load (float): Current taken by the load (in amperes)
    current_charger (float): Current provided by the charger (in amperes)
    time_to_reach_voltage (float): Time taken to reach the specified voltage (in seconds)
    
    Returns:
    float: The remaining time in seconds
    """
    # Calculate current capacity (in Ah) based on time to reach voltage and charger current
    current_capacity = time_to_reach_voltage * current_charger / 3600  # Convert to Ah
    # Calculate discharge time based on load current
    if current_load > 0:
        remaining_time = current_capacity / current_load * 3600  # Convert back to seconds
    else:
        remaining_time = float('inf')  # No discharge if no load
    return remaining_time

def main():
    global switch_state, backlight_on, last_interaction
    
    print("Battery Monitor Simulation")
    time.sleep(2)  # Simulate initial delay
    
    while True:
        # Get user inputs
        try:
            battery_voltage = float(input("Enter battery voltage (V, e.g., 3.7): "))
            load_current_mA = float(input("Enter load current (mA, e.g., 500): "))
            charger_current_mA = float(input("Enter charger current (mA, e.g., 200): "))
            machine_voltage = float(input("Enter voltage used by the machine (V, e.g., 3.7): "))
            machine_current_mA = float(input("Enter current used by the machine (mA, e.g., 500): "))
            time_to_charge = float(input("Enter time to charge (seconds, e.g., 3600): "))
        except ValueError:
            print("Invalid input. Please enter numeric values.")
            continue
        
        # Convert currents to amperes
        load_current_A = load_current_mA / 1000
        charger_current_A = charger_current_mA / 1000
        machine_current_A = machine_current_mA / 1000
        
        # Estimate SoC
        soc = map_value(battery_voltage, 3.0, 4.2, 0, 100)
        soc = constrain(soc, 0, 100)
        
        # Calculate discharge time
        time_remaining = calculate_time_remaining(battery_voltage, machine_current_A, charger_current_A, time_to_charge)
        
        # Control charger
        if battery_voltage <= soc_low and not switch_state:
            mosfet_pin = True  # Charger ON
            switch_state = True
            print("Battery <= 40%, Charger ON")
            simulate_lcd_print(1, 0, "Chg:ON          ")
            backlight_pin = True
            backlight_on = True
            last_interaction = time.time()
        elif battery_voltage >= soc_high and switch_state:
            mosfet_pin = False  # Charger OFF
            switch_state = False
            print("Battery >= 70%, Charger OFF")
            simulate_lcd_print(1, 0, "Chg:OFF         ")
            backlight_pin = True
            backlight_on = True
            last_interaction = time.time()
        
        # Simulate LCD display
        simulate_lcd_print(0, 0, f"V:{battery_voltage:.1f} I:{load_current_mA/1000:.1f}A")
        simulate_lcd_print(1, 0, f"C:{charger_current_mA/1000:.1f}A")
        simulate_lcd_print(1, 10, f"{soc:.0f}%")
        
        # Backlight control
        if (time.time() - last_interaction) > backlight_timeout and backlight_on:
            backlight_pin = False
            backlight_on = False
            print("Backlight OFF")
        
        # Serial output
        print(f"Battery Voltage: {battery_voltage:.2f} V, "
              f"Load Current: {load_current_mA/1000:.2f} A, "
              f"Charger Current: {charger_current_mA/1000:.2f} A, "
              f"SoC: {soc:.0f}%, "
              f"Machine Voltage: {machine_voltage:.2f} V, "
              f"Machine Current: {machine_current_mA/1000:.2f} A, "
              f"Time to Discharge: {time_remaining:.2f} seconds")
        
        time.sleep(1)  # Simulate loop delay

if __name__ == "__main__":
    main()