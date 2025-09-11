import numpy as np
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import RBF, ConstantKernel as C
import matplotlib.pyplot as plt

# Dataset
voltages = np.array([3.8, 3.75, 3.73, 3.72, 3.72, 3.72, 3.72, 3.71, 3.71, 3.69, 3.64, 3.54, 3.30, 3.00, 2.00, 0.07])
times = np.array([15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240])

# Reshape voltages for sklearn (2D array)
X = voltages.reshape(-1, 1)
y = times

# Define GPR model with RBF kernel
kernel = C(1.0, (1e-3, 1e3)) * RBF(length_scale=1.0, length_scale_bounds=(1e-2, 1e2))
gpr = GaussianProcessRegressor(kernel=kernel, n_restarts_optimizer=10, random_state=42)

# Fit the model
gpr.fit(X, y)

# Function to predict remaining time for a given voltage
def predict_remaining_time(voltage):
    voltage = np.array([[voltage]])
    mean, std = gpr.predict(voltage, return_std=True)
    return mean[0], std[0]

# Plot the fitted model with uncertainty
def plot_gpr_model():
    X_plot = np.linspace(0.0, 4.0, 100).reshape(-1, 1)
    y_mean, y_std = gpr.predict(X_plot, return_std=True)
    
    plt.figure(figsize=(10, 6))
    plt.scatter(voltages, times, color='red', label='Data points')
    plt.plot(X_plot, y_mean, color='blue', label='GPR fit')
    plt.fill_between(X_plot.ravel(), y_mean - 1.96 * y_std, y_mean + 1.96 * y_std, 
                     alpha=0.2, color='blue', label='95% confidence interval')
    plt.xlabel('Voltage (V)')
    plt.ylabel('Time (minutes)')
    plt.title('Battery Voltage vs. Remaining Time (GPR)')
    plt.legend()
    plt.grid(True)
    plt.show()

# Interactive prediction
def main():
    print("Battery Voltage vs. Time Prediction (GPR Model)")
    plot_gpr_model()
    
    while True:
        try:
            voltage = float(input("Enter voltage (V) to predict remaining time (or type 'exit' to quit): "))
            if 0.0 <= voltage <= 4.2:  # Reasonable range for Li-ion battery
                mean, std = predict_remaining_time(voltage)
                print(f"Predicted remaining time: {mean:.2f} minutes (±{1.96*std:.2f} minutes, 95% CI)")
            else:
                print("Please enter a voltage between 0.0 and 4.2 V.")
        except ValueError as e:
            if str(e) == "could not convert string to float: 'exit'":
                print("Exiting...")
                break
            print("Invalid input. Please enter a valid number or 'exit'.")

if __name__ == "__main__":
    main()