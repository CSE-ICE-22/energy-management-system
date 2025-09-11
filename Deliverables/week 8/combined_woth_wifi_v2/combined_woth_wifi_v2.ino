#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WebServer.h>

// OLED configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1 // No reset pin
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// INA219 for load/discharge (battery to load) at address 0x40
Adafruit_INA219 ina219_load(0x40);

// INA219 for charging (TP4056 to battery) at address 0x41
Adafruit_INA219 ina219_charge(0x41);

// Preferences for storing capacity
Preferences preferences;

// Battery capacity (mAh)
float capacity_mAh = 0.0; // Start at 0
unsigned long lastMillis = 0;

// LED pins (adjust if different for your ESP32 board)
#define BLUE_LED 2  // Built-in blue LED
#define RED_LED  4  // Built-in red LED

// Wi-Fi AP configuration
const char* ssid = "ESP32_Battery_Monitor";
const char* password = "12345678";

// Web server on port 80
WebServer server(80);

// Global variables for handleRoot (declared before use)
float battery_V = 0.0;
float shunt_load_mV = 0.0;
float load_V = 0.0;
float current_load_mA = 0.0;
float shunt_charge_mV = 0.0;
float charge_V = 0.0;
float current_charge_mA = 0.0;
float remaining_time_h = 0.0;

void handleRoot() {
  // Prepare JSON response with required fields
  String json = "{";
  json += "\"battery_V\":" + String(battery_V, 2) + ",";
  json += "\"charge_shunt_mV\":" + String(shunt_charge_mV, 2) + ",";
  json += "\"charge_I_mA\":" + String(current_charge_mA, 2) + ",";
  json += "\"charge_power_mW\":" + String(charge_V * current_charge_mA, 2) + ",";
  json += "\"capacity_mAh\":" + String(capacity_mAh, 2) + ",";
  json += "\"load_shunt_mV\":" + String(shunt_load_mV, 2) + ",";
  json += "\"load_I_mA\":" + String(current_load_mA, 2) + ",";
  json += "\"load_power_mW\":" + String(load_V * current_load_mA, 2) + ",";
  json += "\"remaining_time_h\":" + String(remaining_time_h, 2);
  json += "}";
  
  server.send(200, "application/json", json);
}

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(1); // Wait for Serial Monitor
  }
  
  // Initialize LEDs
  pinMode(BLUE_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  digitalWrite(BLUE_LED, LOW); // Off initially
  digitalWrite(RED_LED, LOW);  // Off initially
  
  // Initialize I2C with SDA=GPIO21, SCL=GPIO22
  Wire.begin(21, 22);
  
  // Initialize load INA219 (A0 and A1 to GND for 0x40)
  if (!ina219_load.begin()) {
    Serial.println("Failed to find load INA219 at address 0x40");
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->GND, A1->GND");
    while (1) { delay(10); }
  }
  
  // Initialize charge INA219 (A0 to VCC, A1 to GND for 0x41)
  if (!ina219_charge.begin()) {
    Serial.println("Failed to find charge INA219 at address 0x41");
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND");
    while (1) { delay(10); }
  }
  
  // Initialize OLED (address 0x3C)
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("SSD1306 allocation failed at address 0x3C"));
    Serial.println("Check OLED wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND");
    while (1) { delay(10); }
  }
  
  // Load stored capacity from NVS
  preferences.begin("battery", false);
  capacity_mAh = preferences.getFloat("capacity", 0.0); // Default to 0 if not set
  if (capacity_mAh < 0 || capacity_mAh > 5000) capacity_mAh = 0.0; // Clamp to reasonable range
  
  // Setup Wi-Fi AP
  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid, password);
  Serial.println("Wi-Fi AP started");
  Serial.print("AP IP address: ");
  Serial.println(WiFi.softAPIP()); // Should be 192.168.4.1
  
  // Setup web server
  server.on("/", handleRoot);
  server.begin();
  Serial.println("Web server started");
  
  // Clear OLED and show startup message
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("System Ready");
  display.println("Monitoring...");
  display.print("AP: ");
  display.println(ssid);
  display.display();
  
  Serial.println("INA219s and OLED initialized successfully");
  Serial.println("Charging mode: ESP32 powered by external 5V supply (VIN to power supply positive)");
  Serial.println("Discharging mode: ESP32 powered by battery (VIN to battery positive)");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Remaining Time | Mode");
  delay(2000);
}

void loop() {
  // Handle client requests
  server.handleClient();
  
  // Calculate time delta for coulomb counting
  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0; // Seconds
  lastMillis = currentMillis;
  
  // Read load/discharge measurements
  shunt_load_mV = ina219_load.getShuntVoltage_mV();
  float bus_load_V = ina219_load.getBusVoltage_V();
  current_load_mA = ina219_load.getCurrent_mA();
  
  // Calculate battery voltage and load values
  battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  load_V = bus_load_V;
  
  // Read charge measurements (from TP4056 to battery)
  shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  current_charge_mA = ina219_charge.getCurrent_mA();
  
  // Charge voltage
  charge_V = bus_charge_V + (shunt_charge_mV / 1000.0); // Fixed as per previous request
  
  // Diagnostic output
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
  
  // Mode detection: Prioritize discharging if load current is detected
  bool isDischarging = (current_load_mA > 5.0); // Discharging if load current > 5 mA
  bool isCharging = (!isDischarging && current_charge_mA > 1.0 && bus_charge_V > 1.0); // Charging if no load, charge current > 1 mA, voltage > 1V
  
  // LED control
  digitalWrite(BLUE_LED, (isCharging && battery_V >= 3.7) ? HIGH : LOW); // Blue LED on at 3.7V during charging
  digitalWrite(RED_LED, (isDischarging && battery_V <= 3.3) ? HIGH : LOW); // Red LED on at 3.3V during discharging
  
  // Capacity and remaining time
  String mode;
  
  if (isCharging && battery_V < 3.7) {
    mode = "Charging";
    // Charging mode: calculate capacity starting from 0
    capacity_mAh += (current_charge_mA * delta_t / 3600.0); // mAh
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (capacity_mAh > 5000) capacity_mAh = 5000; // Adjust max based on battery
    preferences.putFloat("capacity", capacity_mAh); // Store in NVS
  } else if (isCharging && battery_V >= 3.7) {
    mode = "Charge Complete";
    // Stop incrementing capacity
    preferences.putFloat("capacity", capacity_mAh); // Store final capacity
  } else if (isDischarging) {
    mode = "Discharging";
    // Discharging mode: update capacity and calculate remaining time
    capacity_mAh -= (current_load_mA * delta_t / 3600.0); // Update capacity
    if (capacity_mAh < 0) capacity_mAh = 0;
    preferences.putFloat("capacity", capacity_mAh); // Store in NVS
    if (current_load_mA > 0) {
      remaining_time_h = capacity_mAh / current_load_mA; // Hours
    }
  } else {
    mode = "Idle";
  }
  
  // Serial output
  Serial.print("Battery V: ");
  Serial.print(battery_V, 2);
  Serial.print(" V | Load I: ");
  Serial.print(current_load_mA, 2);
  Serial.print(" mA | Charge I: ");
  Serial.print(current_charge_mA, 2);
  Serial.print(" mA | Capacity: ");
  Serial.print(capacity_mAh, 2);
  Serial.print(" mAh | Time: ");
  Serial.print(remaining_time_h, 2);
  Serial.print(" h | Mode: ");
  Serial.println(mode);
  
  // OLED output
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  if (isCharging && battery_V < 3.7) {
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
  } else if (isCharging && battery_V >= 3.7) {
    display.println("Charge Complete");
    display.print("Charge V: ");
    display.print(charge_V, 2);
    display.println(" V");
    display.setCursor(0, 16);
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
    display.print(current_load_mA, 1);
    display.println(" mA");
    display.setCursor(0, 32);
    display.print("Cap: ");
    display.print((int)capacity_mAh);
    display.println(" mAh");
    display.setCursor(0, 48);
    display.print("Time: ");
    display.print(remaining_time_h, 1);
    display.println(" h");
  } else {
    display.println("Idle Mode");
    display.println("No activity");
    display.setCursor(0, 32);
    display.print("Cap: ");
    display.print((int)capacity_mAh);
    display.println(" mAh");
  }
  display.display();
  
  delay(2000); // Update every 2 seconds
}

void loopEnd() {
  preferences.end(); // Close NVS
}