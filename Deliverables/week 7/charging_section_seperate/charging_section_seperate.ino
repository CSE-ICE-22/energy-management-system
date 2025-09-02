#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
Adafruit_INA219 ina219_charge(0x41);

float capacity_mAh = 3000.0; // Initial battery capacity
unsigned long lastMillis = 0;

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(1);
  
  // Initialize I2C with SDA=GPIO21, SCL=GPIO22
  Wire.begin(21, 22);
  
  // Initialize INA219 (0x41)
  if (!ina219_charge.begin()) {
    Serial.println("INA219 (0x41) failed. Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND, VIN+->TP4056 OUT+, VIN-->Battery +");
    while (1) delay(10);
  }
  
  // Initialize OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("SSD1306 failed. Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND");
    while (1) delay(10);
  }
  
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println("Charge Mode");
  display.display();
  Serial.println("Charge Mode Started");
  delay(2000);
}

void loop() {
  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0;
  lastMillis = currentMillis;
  
  // Read charge measurements
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  float current_charge_mA = ina219_charge.getCurrent_mA();
  
  float charge_V = bus_charge_V;
  
  // Update capacity
  capacity_mAh += (current_charge_mA * delta_t / 3600.0);
  if (capacity_mAh < 0) capacity_mAh = 0;
  if (capacity_mAh > 5000) capacity_mAh = 5000; // Adjust max based on battery
  
  // Serial output
  Serial.print("Charge V: "); Serial.print(charge_V, 2);
  Serial.print(" V | Charge I: "); Serial.print(current_charge_mA, 2);
  Serial.print(" mA | Cap: "); Serial.print(capacity_mAh, 2);
  Serial.println(" mAh");
  
  // OLED output
  display.clearDisplay();
  display.setCursor(0, 0);
  display.println("Charging");
  display.print("V: "); display.print(charge_V, 2); display.println(" V");
  display.setCursor(0, 16);
  display.print("I: "); display.print(current_charge_mA, 1); display.println(" mA");
  display.setCursor(0, 32);
  display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
  display.display();
  
  delay(2000);
}