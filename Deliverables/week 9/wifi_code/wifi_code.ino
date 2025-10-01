#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

// Wi-Fi AP credentials
const char* ssid = "ESP32C3_EnergyMonitor";
const char* password = "password123";

// Web server on port 80
WebServer server(80);

// OLED configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// INA219 instances
Adafruit_INA219 ina219_load(0x40);   // Discharging sensor
Adafruit_INA219 ina219_charge(0x41); // Charging sensor

// Battery and timing variables
float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;
float battery_V = 0.0, load_current_mA = 0.0, charge_current_mA = 0.0;

void handleRoot() {
  // Create JSON response
  StaticJsonDocument<200> doc;
  doc["battery_V"] = battery_V;
  doc["load_I_mA"] = load_current_mA;
  doc["load_shunt_mV"] = ina219_load.getShuntVoltage_mV();
  doc["load_power_mW"] = ina219_load.getPower_mW();
  doc["charge_I_mA"] = charge_current_mA;
  doc["charge_shunt_mV"] = ina219_charge.getShuntVoltage_mV();
  doc["charge_power_mW"] = ina219_charge.getPower_mW();
  doc["capacity_mAh"] = capacity_mAh;
  doc["remaining_time_h"] = (load_current_mA > 0) ? capacity_mAh / load_current_mA : 0.0;
  doc["mode"] = (charge_current_mA > 0.2 && load_current_mA <= 5.0) ? "Charging" : (load_current_mA > 5.0) ? "Discharging" : "Idle";
  
  String json;
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(1); }

  // Initialize I2C on GPIO6 (SDA), GPIO7 (SCL)
  Wire.begin(6, 7);

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

  // Initialize OLED (address 0x3C)
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("SSD1306 allocation failed"));
    while (1) { delay(10); }
  }

  // Display startup message
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("ESP32-C3 WiFi Test");
  display.println("SSID: ESP32C3_EnergyMonitor");
  display.println("IP: 192.168.4.1");
  display.display();

  // Set up Wi-Fi AP
  WiFi.softAP(ssid, password);
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);

  // Start web server
  server.on("/", handleRoot);
  server.begin();
  Serial.println("Web server started at http://192.168.4.1");

  Serial.println("Pin Configuration (ESP32-C3):");
  Serial.println("Charging:");
  Serial.println("  ESP32-C3 VIN: TP4056 OUT+ (via Switch)");
  Serial.println("  TP4056 IN+: Laptop USB 5V");
  Serial.println("  TP4056 OUT+: Switch Input");
  Serial.println("  INA219(0x41) VIN+: Switch Output");
  Serial.println("  INA219(0x41) VIN-: Battery+, TP4056 B+");
  Serial.println("  INA219(0x41) A0: 3V3, A1: GND");
  Serial.println("  I2C: GPIO6 (SDA), GPIO7 (SCL)");
  Serial.println("Discharging:");
  Serial.println("  ESP32-C3 VIN: Battery+ (or USB for testing)");
  Serial.println("  INA219(0x40) VIN+: Battery+");
  Serial.println("  INA219(0x40) VIN-: Load+");
  Serial.println("  Load-: GND");
  Serial.println("  I2C: GPIO6 (SDA), GPIO7 (SCL)");
  Serial.println("Common:");
  Serial.println("  ESP32-C3 3V3: INA219 VCC, OLED VCC");
  Serial.println("  OLED SDA: GPIO6, SCL: GPIO7");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Time | Mode");
}

void loop() {
  server.handleClient();

  unsigned long currentMillis = millis();
  if (currentMillis - lastMillis >= 2000) {
    lastMillis = currentMillis;
    float delta_t = 2.0;

    // Read discharging data
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

    // Display on OLED
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    if (isCharging) {
      display.println("Charging Mode");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.print("I: ");
      display.print(charge_current_mA, 1);
      display.println(" mA");
      display.print("Cap: ");
      display.print((int)capacity_mAh);
      display.println(" mAh");
      display.println("Pin Config:");
      display.println("ESP32-C3 VIN: TP4056 OUT+");
      display.println("INA219 VIN+: Switch");
      display.println("VIN-: Batt+");
    } else if (isDischarging) {
      display.println("Discharging Mode");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.print("I: ");
      display.print(load_current_mA, 1);
      display.println(" mA");
      display.print("Time: ");
      display.print(remaining_time_h, 1);
      display.println(" h");
      display.println("Pin Config:");
      display.println("ESP32-C3 VIN: Batt+");
      display.println("INA219 VIN+: Batt+");
      display.println("VIN-: Load+");
    } else {
      display.println("Idle Mode");
      display.print("Charge I: ");
      display.print(charge_current_mA, 2);
      display.println(" mA");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.println("Pin Config:");
      display.println("ESP32-C3 VIN: Check");
      display.println("Check TP4056/Switch");
      display.println("Check Load");
    }
    display.display();

    // Serial output
    Serial.print("Data: ");
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
}