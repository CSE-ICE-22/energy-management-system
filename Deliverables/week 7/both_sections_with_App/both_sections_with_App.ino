#include <WiFi.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

// WiFi AP Credentials
#define AP_SSID "ESP32_AP"
#define AP_PASSWORD "password123"

// Relay Pin
#define RELAY_PIN 25

// OLED Setup
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// INA219 Setup
Adafruit_INA219 ina219_load(0x40);
Adafruit_INA219 ina219_charge(0x41);

// WebSocket Server
WebSocketsServer webSocket = WebSocketsServer(81);

float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;
bool isCharging = true;

void webSocketEvent(uint8_t num, WStype_t type, uint8_t * payload, size_t length) {
  if (type == WStype_DISCONNECTED) {
    Serial.printf("Client %u disconnected\n", num);
  } else if (type == WStype_CONNECTED) {
    Serial.printf("Client %u connected\n", num);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH); // Start charging

  // Initialize I2C
  Wire.begin(21, 22);

  // Initialize INA219s
  if (!ina219_load.begin()) {
    Serial.println("INA219 (0x40) failed. Check: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->GND, A1->GND");
    while (1) delay(10);
  }
  if (!ina219_charge.begin()) {
    Serial.println("INA219 (0x41) failed. Check: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND");
    while (1) delay(10);
  }

  // Initialize OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("SSD1306 failed. Check: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND");
    while (1) delay(10);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("System Ready");
  display.display();

  // Setup WiFi AP
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());

  // Start WebSocket Server
  webSocket.begin();
  webSocket.onEvent(webSocketEvent);
}

void loop() {
  webSocket.loop();

  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0;
  lastMillis = currentMillis;

  // Read INA219 Data
  float battery_V = 0.0;
  float load_current_mA = 0.0;
  float charge_V = 0.0;
  float charge_current_mA = 0.0;
  float remaining_time_h = 0.0;

  // Read INA219 (0x40) only during discharging
  if (!isCharging) {
    float shunt_load_mV = ina219_load.getShuntVoltage_mV();
    float bus_load_V = ina219_load.getBusVoltage_V();
    load_current_mA = ina219_load.getCurrent_mA();
    battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  }

  // Read INA219 (0x41) only during charging
  if (isCharging) {
    float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
    float bus_charge_V = ina219_charge.getBusVoltage_V();
    charge_current_mA = ina219_charge.getCurrent_mA();
    charge_V = bus_charge_V;
    // Use INA219 (0x40) for battery voltage during charging
    float shunt_load_mV = ina219_load.getShuntVoltage_mV();
    float bus_load_V = ina219_load.getBusVoltage_V();
    battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  }

  // Relay Control
  if (isCharging && battery_V >= 3.7) {
    isCharging = false;
    digitalWrite(RELAY_PIN, LOW); // Switch to discharging
    Serial.println("Switching to DISCHARGING: battery_V >= 3.7V");
  } else if (!isCharging && battery_V <= 3.0) {
    isCharging = true;
    digitalWrite(RELAY_PIN, HIGH); // Switch to charging
    Serial.println("Switching to CHARGING: battery_V <= 3.0V");
  }

  // Explicitly set relay state
  digitalWrite(RELAY_PIN, isCharging ? HIGH : LOW);

  // Debug Output
  Serial.print("Battery Voltage: "); Serial.print(battery_V, 2); Serial.print(" V, Mode: ");
  Serial.print(isCharging ? "Charging" : "Discharging");
  Serial.print(", Relay: "); Serial.println(isCharging ? "HIGH (NO)" : "LOW (NC)");
  if (isCharging) {
    Serial.print("Charging - V: "); Serial.print(charge_V, 2); Serial.print(" V, I: ");
    Serial.print(charge_current_mA, 1); Serial.println(" mA");
  } else {
    Serial.print("Discharging - V: "); Serial.print(battery_V, 2); Serial.print(" V, I: ");
    Serial.print(load_current_mA, 1); Serial.println(" mA");
  }

  // Update Capacity
  if (isCharging) {
    capacity_mAh += (charge_current_mA * delta_t / 3600.0);
    if (capacity_mAh > 5000) capacity_mAh = 5000;
  } else {
    capacity_mAh -= (load_current_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (load_current_mA > 0) {
      remaining_time_h = capacity_mAh / load_current_mA;
    }
  }

  // Create JSON Data for WebSocket
  StaticJsonDocument<200> doc;
  doc["mode"] = isCharging ? "charging" : "discharging";
  doc["battery_V"] = battery_V;
  if (isCharging) {
    doc["charge_V"] = charge_V;
    doc["charge_current_mA"] = charge_current_mA;
  } else {
    doc["load_current_mA"] = load_current_mA;
    doc["remaining_time_h"] = remaining_time_h;
  }
  doc["capacity_mAh"] = capacity_mAh;
  doc["timestamp"] = currentMillis / 1000.0;

  // Send to WebSocket Clients
  String json;
  serializeJson(doc, json);
  webSocket.broadcastTXT(json);

  // Update OLED
  display.clearDisplay();
  display.setCursor(0, 0);
  if (isCharging) {
    display.println("Charging");
    display.print("V: "); display.print(charge_V, 2); display.println(" V");
    display.print("I: "); display.print(charge_current_mA, 1); display.println(" mA");
    display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
  } else {
    display.println("Discharging");
    display.print("V: "); display.print(battery_V, 2); display.println(" V");
    display.print("I: "); display.print(load_current_mA, 1); display.println(" mA");
    display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
    display.print("Time: "); display.print(remaining_time_h, 1); display.println(" h");
  }
  display.display();

  delay(2000);
}