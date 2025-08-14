#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>

// OLED configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1 // No reset pin
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// Initialize INA219 at default I2C address 0x40
Adafruit_INA219 ina219;

void setup() {
  Serial.begin(115200);
  while (!Serial) {
    delay(1); // Wait for Serial Monitor
  }
  
  // Initialize I2C with SDA=GPIO21, SCL=GPIO22
  Wire.begin(21, 22);
  
  // Initialize INA219
  if (!ina219.begin()) {
    Serial.println("Failed to find INA219 chip at address 0x40");
    Serial.println("Check wiring: SDA->D21, SCL->D22, VCC->3V3, GND->GND");
    while (1) { delay(10); }
  }
  
  // Initialize OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println(F("SSD1306 allocation failed at address 0x3C"));
    Serial.println("Check OLED wiring: SDA->D21, SCL->D22, VCC->3V3, GND->GND");
    while (1) { delay(10); }
  }
  
  // Clear OLED and show startup message
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("INA219 Ready");
  display.println("Monitoring...");
  display.display();
  
  Serial.println("INA219 and OLED initialized successfully");
  Serial.println("Format: Battery Voltage | Battery Current | Motor Voltage | Motor Current");
  delay(2000);
}

void loop() {
  // Read measurements from INA219
  float shuntVoltage_mV = ina219.getShuntVoltage_mV();
  float busVoltage_V = ina219.getBusVoltage_V();
  float current_mA = ina219.getCurrent_mA();
  
  // Calculate battery voltage and motor (load) voltage/current
  float batteryVoltage_V = busVoltage_V + (shuntVoltage_mV / 1000.0);
  float motorVoltage_V = busVoltage_V;
  float motorCurrent_mA = current_mA;
  
  // Serial output
  Serial.print("Battery Voltage: ");
  Serial.print(batteryVoltage_V, 2);
  Serial.print(" V | Battery Current: ");
  Serial.print(current_mA, 2);
  Serial.print(" mA | Motor Voltage: ");
  Serial.print(motorVoltage_V, 2);
  Serial.print(" V | Motor Current: ");
  Serial.print(motorCurrent_mA, 2);
  Serial.println(" mA");
  
  // OLED output
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("Load V: ");
  display.print(motorVoltage_V, 2);
  display.println(" V");
  display.setCursor(0, 16);
  display.print("Load I: ");
  display.print(motorCurrent_mA, 1);
  display.println(" mA");
  display.display();
  
  delay(2000); // Update every 2 seconds
}