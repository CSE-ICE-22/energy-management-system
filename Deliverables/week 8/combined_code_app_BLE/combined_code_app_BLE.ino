#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// OLED configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// INA219 for load/discharge (battery to load) at address 0x40
Adafruit_INA219 ina219_load(0x40);

// INA219 for charging (TP4056 to battery) at address 0x41
Adafruit_INA219 ina219_charge(0x41);

// Preferences for storing capacity
Preferences preferences;

// Battery capacity (mAh)
float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;

// BLE Configuration
#define SERVICE_UUID "0000180f-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "00002a19-0000-1000-8000-00805f9b34fb"
BLEServer *pServer = nullptr;
BLECharacteristic *pCharacteristic = nullptr;
bool deviceConnected = false;

// BLE Server Callbacks
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Client Connected");
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("BLE Client Disconnected");
    pServer->startAdvertising(); // Restart advertising
  }
};

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(1);
  }
  
  Wire.begin(21, 22);
  
  if (!ina219_load.begin()) {
    Serial.println("Failed to find load INA219 at address 0x40");
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->GND, A1->GND");
    while (1) { delay(10); }
  }
  
  if (!ina219_charge.begin()) {
    Serial.println("Failed to find charge INA219 at address 0x41");
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND");
    while (1) { delay(10); }
  }
  
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("SSD1306 allocation failed at address 0x3C"));
    Serial.println("Check OLED wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND");
    while (1) { delay(10); }
  }
  
  preferences.begin("battery", false);
  capacity_mAh = preferences.getFloat("capacity", 3000.0);
  if (capacity_mAh < 0 || capacity_mAh > 5000) capacity_mAh = 3000.0;
  
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("System Ready");
  display.println("Monitoring...");
  display.display();
  
  // Initialize BLE
  BLEDevice::init("EnergyMonitor");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->startAdvertising();
  Serial.println("Waiting for BLE connection...");
  
  Serial.println("INA219s and OLED initialized successfully");
  Serial.println("Charging mode: ESP32 powered by external 5V supply (VIN to power supply positive)");
  Serial.println("Discharging mode: ESP32 powered by battery (VIN to battery positive)");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Remaining Time | Mode");
  delay(2000);
}

void loop() {
  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0;
  lastMillis = currentMillis;
  
  float shunt_load_mV = ina219_load.getShuntVoltage_mV();
  float bus_load_V = ina219_load.getBusVoltage_V();
  float current_load_mA = ina219_load.getCurrent_mA();
  
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  float current_charge_mA = ina219_charge.getCurrent_mA();
  
  float battery_V;
  float load_V = bus_load_V;
  float charge_V = bus_charge_V;
  bool isDischarging = (current_load_mA > 5.0);
  bool isCharging = (!isDischarging && current_charge_mA > 1.0 && bus_charge_V > 4.0);
  String mode = isCharging ? "Charging" : isDischarging ? "Discharging" : "Idle";
  
  if (isCharging) {
    battery_V = bus_charge_V + (shunt_charge_mV / 1000.0);
  } else {
    battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  }
  float load_current_mA = current_load_mA;
  
  float load_power_mW = load_V * load_current_mA;
  float charge_power_mW = charge_V * current_charge_mA;
  
  float remaining_time_h = 0.0;
  if (isCharging) {
    capacity_mAh += (current_charge_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (capacity_mAh > 5000) capacity_mAh = 5000;
    preferences.putFloat("capacity", capacity_mAh);
  } else if (isDischarging) {
    capacity_mAh -= (current_load_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    preferences.putFloat("capacity", capacity_mAh);
    if (load_current_mA > 0) {
      remaining_time_h = capacity_mAh / load_current_mA;
    }
  }
  
  if (deviceConnected) {
    DynamicJsonDocument doc(1024);
    doc["battery_V"] = battery_V;
    doc["load_shunt_mV"] = shunt_load_mV;
    doc["load_I_mA"] = load_current_mA;
    doc["load_power_mW"] = load_power_mW;
    doc["charge_shunt_mV"] = shunt_charge_mV;
    doc["charge_I_mA"] = current_charge_mA;
    doc["charge_power_mW"] = charge_power_mW;
    doc["capacity_mAh"] = capacity_mAh;
    doc["remaining_time_h"] = remaining_time_h;
    doc["mode"] = mode;
    String output;
    serializeJson(doc, output);
    pCharacteristic->setValue(output.c_str());
    pCharacteristic->notify();
    Serial.println("BLE Sent: " + output);
  }
  
  Serial.print("Load INA219 Raw: Shunt=");
  Serial.print(shunt_load_mV, 2);
  Serial.print(" mV, Bus=");
  Serial.print(bus_load_V, 2);
  Serial.print(" V, Current=");
  Serial.print(current_load_mA, 2);
  Serial.println(" mA");
  Serial.print("Charge INA219 Raw: Shunt=");
  Serial.print(shunt_charge_mV, 2);
  Serial.print(" mV, Bus=");
  Serial.print(bus_charge_V, 2);
  Serial.print(" V, Current=");
  Serial.print(current_charge_mA, 2);
  Serial.println(" mA");
  
  Serial.print("Battery V: ");
  Serial.print(battery_V, 2);
  Serial.print(" V | Load I: ");
  Serial.print(load_current_mA, 2);
  Serial.print(" mA | Charge I: ");
  Serial.print(current_charge_mA, 2);
  Serial.print(" mA | Capacity: ");
  Serial.print(capacity_mAh, 2);
  Serial.print(" mAh | Time: ");
  Serial.print(remaining_time_h, 2);
  Serial.print(" h | Mode: ");
  Serial.println(mode);
  
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  if (isCharging) {
    display.println("Charging Mode");
    display.print("Charge V: ");
    display.print(charge_V, 2);
    display.println(" V");
    display.setCursor(0, 16);
    display.print("Charge I: ");
    display.print(current_charge_mA, 1);
    display.println(" mA");
    display.setCursor(0, 32);
    display.print("Cap: ");
    display.print((int)capacity_mAh);
    display.println(" mAh");
  } else if (isDischarging) {
    display.println("Discharging Mode");
    display.print("Load V: ");
    display.print(load_V, 2);
    display.println(" V");
    display.setCursor(0, 16);
    display.print("Load I: ");
    display.print(load_current_mA, 1);
    display.println(" mA");
    display.setCursor(0, 32);
    display.print("Time: ");
    display.print(remaining_time_h, 1);
    display.println(" h");
  } else {
    display.println("Idle Mode");
    display.println("No activity");
    display.setCursor(0, 32);
    display.print("Charge I: ");
    display.print(current_charge_mA, 1);
    display.println(" mA");
  }
  display.display();
  
  delay(2000);
}

void loopEnd() {
  preferences.end();
}