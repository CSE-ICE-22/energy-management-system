import numpy as np
from numpy.linalg import inv

class BatterySOCEstimator:
    def __init__(self, Q_nominal, initial_soc=0.5, initial_voltage=3.7):
        """
        Initialize the SOC estimator
        
        Parameters:
        - Q_nominal: Nominal battery capacity in Ah
        - initial_soc: Initial state of charge (0-1)
        - initial_voltage: Initial battery voltage
        """
        # Battery parameters
        self.Q_nominal = Q_nominal  # in Ah
        self.current_soc_cc = initial_soc  # Coulomb Counting SOC
        self.current_soc_ekf = initial_soc  # EKF SOC
        self.voltage = initial_voltage
        
        # Coulomb Counting parameters
        self.cumulative_current = 0.0  # in Ah
        self.last_time = None
        
        # EKF parameters
        self.dt = 1.0  # time step (will be updated in real measurements)
        
        # State transition matrix (simple model: SOC[k+1] = SOC[k] - (i*dt)/Q)
        self.F = np.eye(1)
        
        # Process noise covariance
        self.Q = np.array([[0.001]])
        
        # Measurement noise covariance
        self.R = np.array([[0.01]])
        
        # State covariance
        self.P = np.array([[0.1]])
        
        # Battery model parameters (simplified)
        self.ocv_params = {
            'full_charge_voltage': 4.2,
            'empty_voltage': 3.0,
            'flat_region_low': 0.2,
            'flat_region_high': 0.8
        }
        
    def update_coulomb_counting(self, current, dt):
        """
        Update SOC using Coulomb Counting method
        
        Parameters:
        - current: Current in A (positive for discharge, negative for charge)
        - dt: Time elapsed since last update in hours
        """
        delta_q = current * dt  # Ah
        self.cumulative_current += delta_q
        delta_soc = delta_q / self.Q_nominal
        self.current_soc_cc -= delta_soc
        self.current_soc_cc = np.clip(self.current_soc_cc, 0, 1)
        
    def voltage_to_soc(self, voltage):
        """
        Simple voltage to SOC mapping (linear outside flat region)
        """
        full_v = self.ocv_params['full_charge_voltage']
        empty_v = self.ocv_params['empty_voltage']
        flat_low = self.ocv_params['flat_region_low']
        flat_high = self.ocv_params['flat_region_high']
        
        if voltage >= full_v:
            return 1.0
        elif voltage <= empty_v:
            return 0.0
        elif voltage > 4.0:  # Upper nonlinear region
            soc = 0.8 + 0.2 * (voltage - 4.0) / (full_v - 4.0)
        elif voltage < 3.4:  # Lower nonlinear region
            soc = 0.2 * (voltage - empty_v) / (3.4 - empty_v)
        else:  # Flat region - voltage is not reliable
            return None  # Indicate voltage is not reliable for SOC
            
        return np.clip(soc, 0, 1)
    
    def update_ekf(self, current, voltage, dt):
        """
        Update SOC using Extended Kalman Filter
        
        Parameters:
        - current: Current in A
        - voltage: Battery voltage in V
        - dt: Time elapsed since last update in hours
        """
        self.dt = dt
        
        # State prediction
        soc_pred = self.current_soc_ekf - (current * dt) / self.Q_nominal
        soc_pred = np.clip(soc_pred, 0, 1)
        
        # Update state transition matrix
        self.F = np.eye(1)  # Simple model for this example
        
        # Predict state covariance
        self.P = self.F @ self.P @ self.F.T + self.Q
        
        # Measurement update (only if voltage is meaningful for SOC)
        voltage_soc = self.voltage_to_soc(voltage)
        
        if voltage_soc is not None:
            # Jacobian of measurement function (linearized around current state)
            H = np.array([[1.0]])  # Simple 1:1 relationship for this example
            
            # Kalman gain
            S = H @ self.P @ H.T + self.R
            K = self.P @ H.T @ inv(S)
            
            # State update
            residual = voltage_soc - soc_pred
            soc_pred = soc_pred + K * residual
            
            # Covariance update
            self.P = (np.eye(1) - K @ H) @ self.P
        
        self.current_soc_ekf = np.clip(float(soc_pred), 0, 1)
        
    def update_combined_soc(self, current, voltage, time):
        """
        Update SOC using combined approach
        
        Parameters:
        - current: Current in A
        - voltage: Battery voltage in V
        - time: Current timestamp (datetime or similar)
        """
        # Calculate time delta
        if self.last_time is not None:
            dt = (time - self.last_time).total_seconds() / 3600  # convert to hours
        else:
            dt = 0
        self.last_time = time
        
        # Update voltage
        self.voltage = voltage
        
        # Update both estimators
        self.update_coulomb_counting(current, dt)
        self.update_ekf(current, voltage, dt)
        
        # Determine which SOC to use based on voltage
        voltage_soc = self.voltage_to_soc(voltage)
        
        if voltage_soc is None:
            # In flat region - rely more on Coulomb Counting but blend with EKF
            # Weighted average favoring Coulomb Counting
            combined_soc = 0.7 * self.current_soc_cc + 0.3 * self.current_soc_ekf
        else:
            # Outside flat region - rely more on voltage-corrected EKF
            combined_soc = 0.2 * self.current_soc_cc + 0.8 * self.current_soc_ekf
            
        return combined_soc

# Example usage
if __name__ == "__main__":
    import datetime
    
    # Initialize with a 3.7V nominal battery with 2Ah capacity
    estimator = BatterySOCEstimator(Q_nominal=2.0, initial_soc=0.8, initial_voltage=4.1)
    
    # Extended discharge curve simulation from 4.20V to 3.0V
measurements = [
    # (current_A, voltage_V, time_delta_seconds)
    # High voltage region (100%-80% SOC)
    (0.5, 4.20, 10),  # 100%
    (0.5, 4.15, 10),
    (0.5, 4.10, 10),
    (0.5, 4.05, 10),
    (0.5, 4.00, 10),  # ~80%
    
    # Flat voltage plateau (80%-20% SOC)
    (0.5, 3.95, 30),
    (0.5, 3.90, 30),
    (0.5, 3.85, 30),
    (0.5, 3.80, 30),
    (0.5, 3.78, 30),
    (0.5, 3.76, 30),
    (0.5, 3.75, 30),
    (0.5, 3.74, 30),
    (0.5, 3.73, 30),
    (0.5, 3.72, 30),
    (0.5, 3.71, 30),
    (0.5, 3.70, 30),  # ~50%
    (0.5, 3.69, 30),
    (0.5, 3.68, 30),
    (0.5, 3.67, 30),
    (0.5, 3.66, 30),
    (0.5, 3.65, 30),
    (0.5, 3.64, 30),
    (0.5, 3.63, 30),
    (0.5, 3.62, 30),
    (0.5, 3.61, 30),
    (0.5, 3.60, 30),  # ~20%
    
    # Lower voltage region (20%-0% SOC)
    (0.5, 3.55, 10),
    (0.5, 3.50, 10),
    (0.5, 3.45, 10),
    (0.5, 3.40, 10),
    (0.5, 3.35, 10),
    (0.5, 3.30, 10),
    (0.5, 3.25, 10),
    (0.5, 3.20, 10),
    (0.5, 3.15, 10),
    (0.5, 3.10, 10),
    (0.5, 3.05, 10),
    (0.5, 3.00, 10),  # 0%
]

# Initialize with a 3.7V nominal battery with 2Ah capacity
estimator = BatterySOCEstimator(Q_nominal=2.0, initial_soc=1.0, initial_voltage=4.2)

current_time = datetime.datetime.now()

print("Time\tCurrent(A)\tVoltage(V)\tSOC CC\tSOC EKF\tCombined SOC")
for i, (current, voltage, dt) in enumerate(measurements):
    current_time += datetime.timedelta(seconds=dt)
    combined_soc = estimator.update_combined_soc(current, voltage, current_time)
    
    print(f"{i*10 if i < 4 else i*30 if i < 28 else 28*30 + (i-28)*10}s\t{current:.2f}\t\t{voltage:.2f}\t\t"
          f"{estimator.current_soc_cc:.2%}\t{estimator.current_soc_ekf:.2%}\t"
          f"{combined_soc:.2%}")