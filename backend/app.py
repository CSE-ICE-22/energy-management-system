from flask import Flask, request, jsonify
import torch
import torch.nn as nn
import numpy as np
import pickle

app = Flask(__name__)

# Define the same model architecture
class BatteryMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(2, 128)
        self.fc2 = nn.Linear(128, 64)
        self.fc3 = nn.Linear(64, 32)
        self.fc4 = nn.Linear(32, 1)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.2)
    
    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.relu(self.fc2(x))
        x = self.dropout(x)
        x = self.relu(self.fc3(x))
        return self.fc4(x)

# Load the model and scalers
model = BatteryMLP()
model.load_state_dict(torch.load('battery_model.pth'))
model.eval()
with open('scalers.pkl', 'rb') as f:
    scalers = pickle.load(f)
X_mean, X_std = scalers['X_mean'], scalers['X_std']
y_log_mean, y_log_std = scalers['y_log_mean'], scalers['y_log_std']

# Inference function
def predict_remaining_time(voltage, current):
    input_arr = np.array([[voltage, current]], dtype=np.float32)
    input_norm = (input_arr - X_mean) / X_std
    with torch.no_grad():
        pred_norm = model(torch.from_numpy(input_norm)).numpy()
    pred = np.expm1((pred_norm * y_log_std) + y_log_mean) - 1
    return max(pred[0][0], 0)

@app.route('/predict', methods=['POST'])
def predict():
    data = request.get_json()
    voltage = float(data.get('voltage', 0))
    current = float(data.get('current', 0))
    if not (0 <= voltage <= 4.2) or not (0.001 <= current <= 10):
        return jsonify({'error': 'Invalid input. Voltage: 0-4.2V, Current: 0.001-10A'}), 400
    remaining_time = predict_remaining_time(voltage, current)
    return jsonify({'remaining_time': remaining_time / 3600})  # Return in hours

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)