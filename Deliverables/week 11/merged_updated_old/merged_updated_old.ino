#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

// Wi-Fi AP credentials
const char* ssid = "ESP32_EnergyMonitor";
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

// LED pins for alerts
#define BLUE_LED_PIN 2  // Built-in blue LED

// Battery and timing variables
float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;
float battery_V = 0.0, load_current_mA = 0.0, charge_current_mA = 0.0;
bool lowBatteryAlert = false;
bool highBatteryAlert = false;
unsigned long lastBlinkMillis = 0;
bool ledState = false;

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
  if (lowBatteryAlert) {
    doc["alert"] = "Low battery voltage: " + String(battery_V, 2) + " V";
  } else if (highBatteryAlert) {
    doc["alert"] = "High battery voltage: " + String(battery_V, 2) + " V";
  } else {
    doc["alert"] = "";
  }
  
  String json;
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) { delay(1); }

  // Initialize LED pins
  pinMode(BLUE_LED_PIN, OUTPUT);
  pinMode(BLUE_LED_PIN, OUTPUT);
  digitalWrite(BLUE_LED_PIN, LOW);
  digitalWrite(BLUE_LED_PIN, LOW);

  // Test LEDs for 5 seconds
  Serial.println("Testing LEDs...");
  for (int i = 0; i < 5; i++) {
    digitalWrite(BLUE_LED_PIN, HIGH);
    digitalWrite(BLUE_LED_PIN, HIGH);
    delay(500);
    digitalWrite(BLUE_LED_PIN, LOW);
    digitalWrite(BLUE_LED_PIN, LOW);
    delay(500);
  }
  Serial.println("LED test complete");

  // Initialize I2C on GPIO21 (SDA), GPIO22 (SCL)
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
  display.println("ESP32 Integrated Test");
  display.println("SSID: ESP32_EnergyMonitor");
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

  Serial.println("Pin Configuration (ESP32):");
  Serial.println("Charging:");
  Serial.println("  ESP32 VIN: TP4056 OUT+ (via Switch)");
  Serial.println("  TP4056 IN+: 5V DC Converter");
  Serial.println("  TP4056 OUT+: Switch Input");
  Serial.println("  INA219(0x41) VIN+: Switch Output");
  Serial.println("  INA219(0x41) VIN-: Battery+, TP4056 B+");
  Serial.println("  INA219(0x41) A0: 3V3, A1: GND");
  Serial.println("Discharging:");
  Serial.println("  ESP32 VIN: DC Booster VOUT+ (5V)");
  Serial.println("  DC Booster VIN+: Battery+");
  Serial.println("  INA219(0x40) VIN+: Battery+");
  Serial.println("  INA219(0x40) VIN-: Load+");
  Serial.println("  Load-: GND");
  Serial.println("  BLUE_LED_PIN: GPIO5 (via 220R)");
  Serial.println("  Blue LED: GPIO2 (Built-in)");
  Serial.println("Common:");
  Serial.println("  ESP32 3V3: INA219 VCC, OLED VCC");
  Serial.println("  I2C: GPIO21 (SDA), GPIO22 (SCL)");
  Serial.println("  OLED SDA: GPIO21, SCL: GPIO22");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Time | Mode | Alert | Raw Bus V | Raw Shunt mV");
}

void loop() {
  server.handleClient();

  unsigned long currentMillis = millis();
  if (currentMillis - lastMillis >= 2000) {
    lastMillis = currentMillis;
    float delta_t = 2.0;

    // Read discharging data (INA219 0x40, battery voltage)
    float shunt_load_mV = ina219_load.getShuntVoltage_mV();
    float bus_load_V = ina219_load.getBusVoltage_V();
    load_current_mA = ina219_load.getCurrent_mA();
    float power_load_mW = ina219_load.getPower_mW();
  

    // Read charging data
    float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
    float bus_charge_V = ina219_charge.getBusVoltage_V();
    charge_current_mA = ina219_charge.getCurrent_mA();
    float power_charge_mW = ina219_charge.getPower_mW();

    // Mode detection
    bool isDischarging = (load_current_mA > 5.0);
    bool isCharging = (!isDischarging && charge_current_mA > 0.2);
    String mode = isCharging ? "Charging" : isDischarging ? "Discharging" : "Idle";

    if (isDischarging) {
      battery_V = bus_load_V+0.22;
    }else{
      battery_V = bus_load_V + (shunt_load_mV / 1000.0); // Calibrated for 3.76V
    }

    // Alert detection (only in Charging or Discharging modes)
    lowBatteryAlert = (isCharging || isDischarging) && (battery_V < 3.4);
    highBatteryAlert = (isCharging || isDischarging) && (battery_V > 3.7) && !lowBatteryAlert;

    // Blink LEDs if alert
    if ((lowBatteryAlert || highBatteryAlert) && currentMillis - lastBlinkMillis >= 500) {
      ledState = !ledState;
      digitalWrite(BLUE_LED_PIN, lowBatteryAlert ? (ledState ? HIGH : LOW) : LOW);
      digitalWrite(BLUE_LED_PIN, highBatteryAlert ? (ledState ? HIGH : LOW) : LOW);
      lastBlinkMillis = currentMillis;
    } else if (!lowBatteryAlert && !highBatteryAlert) {
      digitalWrite(BLUE_LED_PIN, LOW);
      digitalWrite(BLUE_LED_PIN, LOW);
      ledState = false;
    }

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
      if (lowBatteryAlert) {
        display.println("ALERT: Low Battery!");
      } else if (highBatteryAlert) {
        display.println("ALERT: High Battery!");
      } else {
        display.println("Pin Config:");
        display.println("VIN: TP4056 OUT+");
        display.println("INA219 VIN+: Switch");
      }
    } else if (isDischarging) {
      display.println("Discharging Mode");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.print("I: ");
      display.print(load_current_mA, 1);
      display.println(" mA");
      display.print("Cap: ");
      display.print((int)capacity_mAh);
      display.println(" mAh");
      display.print("Time: ");
      display.print(remaining_time_h, 1);
      display.println(" h");
      if (lowBatteryAlert) {
        display.println("ALERT: Low Battery!");
      } else if (highBatteryAlert) {
        display.println("ALERT: High Battery!");
      } else {
        display.println("Pin Config:");
        display.println("VIN: DC Booster");
        display.println("INA219 VIN+: Batt+");
      }
    } else {
      display.println("Idle Mode");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.print("Charge I: ");
      display.print(charge_current_mA, 2);
      display.println(" mA");
      display.print("Cap: ");
      display.print((int)capacity_mAh);
      display.println(" mAh");
      display.println("Pin Config:");
      display.println("VIN: DC Booster");
      display.println("Check TP4056/Switch");
    }
    display.display();

    // Serial output with raw values for debugging
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
    Serial.print(mode);
    Serial.print(" | Alert: ");
    Serial.print(lowBatteryAlert ? "Low battery (" + String(battery_V, 2) + " V)" : highBatteryAlert ? "High battery (" + String(battery_V, 2) + " V)" : "None");
    Serial.print(" | Raw Bus V: ");
    Serial.print(bus_load_V, 2);
    Serial.print(" | Raw Shunt mV: ");
    Serial.println(shunt_load_mV, 2);
  }
}