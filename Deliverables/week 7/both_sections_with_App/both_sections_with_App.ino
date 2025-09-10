#include <Wire.h>
#include <Adafruit_INA219.h>
#include <ArduinoBLE.h>
#include <ArduinoJson.h>

// INA219 instances
Adafruit_INA219 ina219_load(0x40);   // Discharging (load) sensor
Adafruit_INA219 ina219_charge(0x41); // Charging sensor

// BLE Service and Characteristic
BLEService batteryService("180F"); // Standard Battery Service UUID
BLECharacteristic batteryDataChar("2A19", BLERead | BLENotify, 512); // Custom characteristic for JSON data

// Battery and timing variables
float capacity_mAh = 3000.0; // Initial capacity
unsigned long lastMillis = 0;
float battery_V = 0.0, load_current_mA = 0.0, charge_current_mA = 0.0;

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(1); }

  // Initialize I2C (SDA=GPIO21, SCL=GPIO22)
  Wire.begin(21, 22);

  // Initialize INA219 for discharging
  if (!ina219_load.begin()) {
    Serial.println("Failed to find INA219 at 0x40");
    while (1) { delay(10); }
  }

  // Initialize INA219 for charging
  if (!ina219_charge.begin()) {
    Serial.println("Failed to find INA219 at 0x41");
    while (1) { delay(10); }
  }

  // Initialize BLE
  if (!BLE.begin()) {
    Serial.println("Failed to initialize BLE");
    while (1) { delay(10); }
  }

  // Set up BLE service
  BLE.setLocalName("EnergyMonitor");
  BLE.setAdvertisedService(batteryService);
  batteryService.addCharacteristic(batteryDataChar);
  BLE.addService(batteryService);
  BLE.advertise();
  Serial.println("BLE Peripheral started");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Time | Mode");
}

void loop() {
  // Wait for BLE central connection
  BLEDevice central = BLE.central();
  if (central) {
    Serial.println("Connected to central: " + central.address());
    while (central.connected()) {
      unsigned long currentMillis = millis();
      if (currentMillis - lastMillis >= 2000) { // Update every 2 seconds
        lastMillis = currentMillis;
        float delta_t = 2.0; // Seconds

        // Read discharging (load) data
        float shunt_load_mV = ina219_load.getShuntVoltage_mV();
        float bus_load_V = ina219_load.getBusVoltage_V();
        load_current_mA = ina219_load.getCurrent_mA();
        float power_load_mW = ina219_load.getPower_mW();
        battery_V = bus_load_V + (shunt_load_mV / 1000.0);

        // Read charging data
        float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
        float bus_charge_V = ina219_charge.getBusVoltage_V();
        charge_current_mA = ina219_charge.getCurrent_mA();
        float power_charge_mW = ina219_charge.getPower_mW();

        // Mode detection
        bool isDischarging = (load_current_mA > 5.0);
        bool isCharging = (!isDischarging && charge_current_mA > 0.2);
        String mode = isCharging ? "Charging" : isDischarging ? "Discharging" : "Idle";

        // Update capacity
        if (isCharging) {
          capacity_mAh += (charge_current_mA * delta_t / 3600.0);
          if (capacity_mAh > 5000) capacity_mAh = 5000;
        } else if (isDischarging) {
          capacity_mAh -= (load_current_mA * delta_t / 3600.0);
          if (capacity_mAh < 0) capacity_mAh = 0;
        }

        // Calculate remaining time
        float remaining_time_h = (load_current_mA > 0 && isDischarging) ? capacity_mAh / load_current_mA : 0.0;

        // Create JSON data
        StaticJsonDocument<200> doc;
        doc["battery_V"] = round(battery_V * 100) / 100.0;
        doc["load_I_mA"] = round(load_current_mA * 100) / 100.0;
        doc["load_shunt_mV"] = round(shunt_load_mV * 100) / 100.0;
        doc["load_power_mW"] = round(power_load_mW * 100) / 100.0;
        doc["charge_I_mA"] = round(charge_current_mA * 100) / 100.0;
        doc["charge_shunt_mV"] = round(shunt_charge_mV * 100) / 100.0;
        doc["charge_power_mW"] = round(power_charge_mW * 100) / 100.0;
        doc["capacity_mAh"] = round(capacity_mAh * 100) / 100.0;
        doc["remaining_time_h"] = round(remaining_time_h * 100) / 100.0;
        doc["mode"] = mode;

        // Serialize JSON to string
        char jsonBuffer[512];
        serializeJson(doc, jsonBuffer);

        // Send over BLE
        if (batteryDataChar.subscribed()) {
          batteryDataChar.writeValue((uint8_t*)jsonBuffer, strlen(jsonBuffer));
        }

        // Serial output for debugging
        Serial.print(battery_V, 2);
        Serial.print(" V | ");
        Serial.print(load_current_mA, 2);
        Serial.print(" mA | ");
        Serial.print(charge_current_mA, 2);
        Serial.print(" mA | ");
        Serial.print(capacity_mAh, 2);
        Serial.print(" mAh | ");
        Serial.print(remaining_time_h, 2);
        Serial.print(" h | ");
        Serial.println(mode);
      }
      delay(100); // Prevent tight loop
    }
    Serial.println("Disconnected from central");
  }
}