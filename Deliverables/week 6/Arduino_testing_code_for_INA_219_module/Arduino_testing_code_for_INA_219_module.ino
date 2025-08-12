#include <Wire.h>
#include <Adafruit_INA219.h>

// Initialize INA219 at default I2C address 0x40
Adafruit_INA219 ina219;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(1); // Wait for Serial Monitor to connect
  }
  
  // Initialize I2C with D21 (SDA) and D22 (SCL)
  Wire.begin(21, 22); // ESP32 I2C pins: D21=SDA (GPIO21), D22=SCL (GPIO22)
  
  // Initialize INA219
  if (!ina219.begin()) {
    Serial.println("Failed to find INA219 chip at address 0x40");
    Serial.println("Check wiring: SDA->D21, SCL->D22, VCC->3V3, GND->GND");
    while (1) { delay(10); }
  }
  
  Serial.println("INA219 initialized successfully");
  Serial.println("Monitoring battery and DC motor...");
  Serial.println("Format: Battery Voltage | Battery Current | Motor Voltage | Motor Current");
}

void loop() {
  // Read measurements from INA219
  float shuntVoltage_mV = ina219.getShuntVoltage_mV();
  float busVoltage_V = ina219.getBusVoltage_V();
  float current_mA = ina219.getCurrent_mA();
  
  // Calculate battery voltage (bus voltage + shunt drop)
  float batteryVoltage_V = busVoltage_V + (shuntVoltage_mV / 1000.0);
  
  // Motor voltage is approximately the bus voltage (voltage at load side)
  float motorVoltage_V = busVoltage_V;
  
  // Motor current is the same as battery current (current through INA219)
  float motorCurrent_mA = current_mA;
  
  // Display in Serial Monitor
  Serial.print("Battery Voltage: ");
  Serial.print(batteryVoltage_V, 2);
  Serial.print(" V | Battery Current: ");
  Serial.print(current_mA, 2);
  Serial.print(" mA | Motor Voltage: ");
  Serial.print(motorVoltage_V, 2);
  Serial.print(" V | Motor Current: ");
  Serial.print(motorCurrent_mA, 2);
  Serial.println(" mA");
  
  delay(2000); // Update every 2 seconds
}