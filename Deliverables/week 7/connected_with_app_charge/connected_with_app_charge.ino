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

// INA219 Setup (Charging only)
Adafruit_INA219 ina219_charge(0x41);

// WebSocket Server
WebSocketsServer webSocket = WebSocketsServer(81);

float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;

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
  digitalWrite(RELAY_PIN, HIGH); // Start in charging mode

  // Initialize I2C
  Wire.begin(21, 22);

  // Initialize INA219 (Charging)
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

  // Read INA219 Data (Charging)
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  float current_charge_mA = ina219_charge.getCurrent_mA();
  float charge_V = bus_charge_V;

  // Update Capacity (Charging)
  capacity_mAh += (current_charge_mA * delta_t / 3600.0);
  if (capacity_mAh > 5000) capacity_mAh = 5000;

  // Create JSON Data for WebSocket
  StaticJsonDocument<200> doc;
  doc["mode"] = "charging";
  doc["charge_V"] = charge_V;
  doc["charge_current_mA"] = current_charge_mA;
  doc["capacity_mAh"] = capacity_mAh;
  doc["timestamp"] = currentMillis / 1000.0;

  // Send to WebSocket Clients
  String json;
  serializeJson(doc, json);
  webSocket.broadcastTXT(json);

  // Update OLED
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("Charging");
  display.print("V: "); display.print(charge_V, 2); display.println(" V");
  display.print("I: "); display.print(current_charge_mA, 1); display.println(" mA");
  display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
  display.display();

  delay(2000);
}