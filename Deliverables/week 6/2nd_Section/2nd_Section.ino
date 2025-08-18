#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>
#include <Preferences.h>

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
float capacity_mAh = 0; // assumption
unsigned long lastMillis = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(1); 
  }
  
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
  
  // Load stored capacity from Non Volatile Storage
  preferences.begin("battery", false);
  capacity_mAh = preferences.getFloat("capacity", 3000.0); 
  if (capacity_mAh < 0 || capacity_mAh > 5000) capacity_mAh = 3000.0; 
  
  // Clear OLED and show startup message
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("System Ready");
  display.println("Monitoring...");
  display.display();
  
  Serial.println("INA219s and OLED initialized successfully");
  Serial.println("Format: Battery V | Load I | Charge I | Capacity | Remaining Time");
  delay(2000);
}

void loop() {
  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0; 
  lastMillis = currentMillis;
  
  // Read load/discharge measurements
  float shunt_load_mV = ina219_load.getShuntVoltage_mV();
  float bus_load_V = ina219_load.getBusVoltage_V();
  float current_load_mA = ina219_load.getCurrent_mA();
  
  // Calculate battery voltage and load values
  float battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  float load_V = bus_load_V;
  float load_current_mA = current_load_mA;
  
  // Read charge measurements (from TP4056 to battery)
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  float current_charge_mA = ina219_charge.getCurrent_mA();
  
  // Charge voltage
  float charge_V = bus_charge_V;
  
  // Mode detection(charging or discharging)
  bool isCharging = (current_charge_mA > 10.0); 
  bool isDischarging = (current_load_mA > 10.0 && current_charge_mA < 10.0); 
  
  // Capacity and remaining time
  float remaining_time_h = 0.0;
  if (isCharging) {
    // Charging mode: calculate capacity
    capacity_mAh += (current_charge_mA * delta_t / 3600.0); 
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (capacity_mAh > 5000) capacity_mAh = 5000; 
    // Store in Non Volatile Storage
    preferences.putFloat("capacity", capacity_mAh); 
  } else if (isDischarging) {
    // Discharging mode: update capacity and calculate remaining time
    capacity_mAh -= (current_load_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    // Store in Non Volatile Storage
    preferences.putFloat("capacity", capacity_mAh); 
    if (load_current_mA > 0) {
      remaining_time_h = capacity_mAh / load_current_mA; 
    }
  }
  
  // Serial output
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
  Serial.println(" h");
  
  // OLED output
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
  }
  display.display();
  
  delay(2000); 
}

void loopEnd() {
  // Close Non Volatile Storage
  preferences.end(); 
}