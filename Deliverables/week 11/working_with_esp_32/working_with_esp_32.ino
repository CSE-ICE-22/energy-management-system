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

// INA219 instance for discharging
Adafruit_INA219 ina219_load(0x40);

// LED pin for low battery alert
#define LED_PIN 5

// Battery and timing variables
float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;
float battery_V = 0.0, load_current_mA = 0.0;
bool lowBatteryAlert = false;
unsigned long lastBlinkMillis = 0;
bool ledState = false;

void handleRoot() {
  // Create JSON response
  StaticJsonDocument<200> doc;
  doc["battery_V"] = battery_V;
  doc["load_I_mA"] = load_current_mA;
  doc["load_shunt_mV"] = ina219_load.getShuntVoltage_mV();
  doc["load_power_mW"] = ina219_load.getPower_mW();
  doc["capacity_mAh"] = capacity_mAh;
  doc["remaining_time_h"] = (load_current_mA > 0) ? capacity_mAh / load_current_mA : 0.0;
  doc["mode"] = (load_current_mA > 5.0) ? "Discharging" : "Idle";
  if (lowBatteryAlert) {
    String alertMsg = "Low battery voltage: " + String(battery_V, 2) + " V";
    doc["alert"] = alertMsg;
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

  // Initialize LED pin
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // Initialize I2C on GPIO21 (SDA), GPIO22 (SCL)
  Wire.begin(21, 22);

  // Initialize INA219 for discharging
  if (!ina219_load.begin()) {
    Serial.println("Failed to find INA219 at 0x40");
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
  display.println("ESP32 Discharge Test");
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

  Serial.println("Pin Configuration (ESP32, Discharging):");
  Serial.println("  ESP32 VIN: Battery+ (~3.7-4.2V)");
  Serial.println("  INA219(0x40) VIN+: Battery+");
  Serial.println("  INA219(0x40) VIN-: Load+");
  Serial.println("  INA219(0x40) VCC: ESP32 3V3");
  Serial.println("  INA219(0x40) A0: GND, A1: GND");
  Serial.println("  Load-: GND");
  Serial.println("  Red LED: GPIO5 (via 220R)");
  Serial.println("  I2C: GPIO21 (SDA), GPIO22 (SCL)");
  Serial.println("  OLED VCC: ESP32 3V3");
  Serial.println("  OLED SDA: GPIO21, SCL: GPIO22");
  Serial.println("Format: Battery V | Load I | Capacity | Time | Mode | Alert");
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
    battery_V = bus_load_V + (shunt_load_mV / 1000.0); // Adjust offset if needed

    // Mode detection
    bool isDischarging = (load_current_mA > 5.0);
    String mode = isDischarging ? "Discharging" : "Idle";

    // Low battery alert
    lowBatteryAlert = (battery_V < 3.4);

    // Update capacity
    if (isDischarging) {
      capacity_mAh -= (load_current_mA * delta_t / 3600.0);
      if (capacity_mAh < 0) capacity_mAh = 0;
    }

    // Calculate remaining time
    float remaining_time_h = (load_current_mA > 0 && isDischarging) ? capacity_mAh / load_current_mA : 0.0;

    // Blink LED if low battery
    if (lowBatteryAlert && currentMillis - lastBlinkMillis >= 500) {
      ledState = !ledState;
      digitalWrite(LED_PIN, ledState ? HIGH : LOW);
      lastBlinkMillis = currentMillis;
    } else if (!lowBatteryAlert) {
      digitalWrite(LED_PIN, LOW);
      ledState = false;
    }

    // Display on OLED
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(0, 0);
    if (isDischarging) {
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
      } else {
        display.println("Pin Config:");
        display.println("VIN: Batt+");
        display.println("INA219 VIN+: Batt+");
      }
    } else {
      display.println("Idle Mode");
      display.print("V: ");
      display.print(battery_V, 2);
      display.println(" V");
      display.print("I: ");
      display.print(load_current_mA, 2);
      display.println(" mA");
      display.print("Cap: ");
      display.print((int)capacity_mAh);
      display.println(" mAh");
      if (lowBatteryAlert) {
        display.println("ALERT: Low Battery!");
      } else {
        display.println("Pin Config:");
        display.println("VIN: Batt+");
        display.println("Check Load");
      }
    }
    display.display();

    // Serial output
    Serial.print("Data: ");
    Serial.print(battery_V, 2);
    Serial.print(" V | ");
    Serial.print(load_current_mA, 2);
    Serial.print(" mA | ");
    Serial.print(capacity_mAh, 2);
    Serial.print(" mAh | ");
    Serial.print(remaining_time_h, 2);
    Serial.print(" h | ");
    Serial.print(mode);
    Serial.print(" | Alert: ");
    Serial.println(lowBatteryAlert ? "Low battery (" + String(battery_V, 2) + " V)" : "None");
  }
}