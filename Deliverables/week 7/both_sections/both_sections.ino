#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Adafruit_SSD1306.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
Adafruit_INA219 ina219_load(0x40);
Adafruit_INA219 ina219_charge(0x41);

const int RELAY_PIN = 25;
float capacity_mAh = 3000.0;
unsigned long lastMillis = 0;
bool isCharging = true;

void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, HIGH); // Start charging (NO closed)
  
  Wire.begin(21, 22);
  
  if (!ina219_load.begin()) {
    Serial.println("INA219 (0x40) failed. Check: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->GND, A1->GND");
    while (1) delay(10);
  }
  
  if (!ina219_charge.begin()) {
    Serial.println("INA219 (0x41) failed. Check: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND");
    while (1) delay(10);
  }
  
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
  Serial.println("System Started");
  delay(2000);
}

void loop() {
  unsigned long currentMillis = millis();
  float delta_t = (currentMillis - lastMillis) / 1000.0;
  lastMillis = currentMillis;
  
  float shunt_load_mV = ina219_load.getShuntVoltage_mV();
  float bus_load_V = ina219_load.getBusVoltage_V();
  float current_load_mA = ina219_load.getCurrent_mA();
  
  float battery_V = bus_load_V + (shunt_load_mV / 1000.0);
  float load_current_mA = current_load_mA;
  
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV();
  float bus_charge_V = ina219_charge.getBusVoltage_V();
  float current_charge_mA = ina219_charge.getCurrent_mA();
  
  float charge_V = bus_charge_V;
  
  if (isCharging && battery_V >= 3.7) {
    isCharging = false;
    digitalWrite(RELAY_PIN, LOW); // Switch to discharging (NC closed)
  }
  
  float remaining_time_h = 0.0;
  if (isCharging) {
    capacity_mAh += (current_charge_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (capacity_mAh > 5000) capacity_mAh = 5000;
  } else {
    capacity_mAh -= (load_current_mA * delta_t / 3600.0);
    if (capacity_mAh < 0) capacity_mAh = 0;
    if (load_current_mA > 0) {
      remaining_time_h = capacity_mAh / load_current_mA;
    }
  }
  
  Serial.print("V: "); Serial.print(battery_V, 2);
  Serial.print(" V | Load I: "); Serial.print(load_current_mA, 2);
  Serial.print(" mA | Charge I: "); Serial.print(current_charge_mA, 2);
  Serial.print(" mA | Cap: "); Serial.print(capacity_mAh, 2);
  Serial.print(" mAh | Time: "); Serial.print(remaining_time_h, 2);
  Serial.println(" h");
  
  display.clearDisplay();
  display.setCursor(0, 0);
  if (isCharging) {
    display.println("Charging");
    display.print("V: "); display.print(charge_V, 2); display.println(" V");
    display.setCursor(0, 16);
    display.print("I: "); display.print(current_charge_mA, 1); display.println(" mA");
    display.setCursor(0, 32);
    display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
  } else {
    display.println("Discharging");
    display.print("V: "); display.print(battery_V, 2); display.println(" V");
    display.setCursor(0, 16);
    display.print("I: "); display.print(load_current_mA, 1); display.println(" mA");
    display.setCursor(0, 32);
    display.print("Cap: "); display.print((int)capacity_mAh); display.println(" mAh");
    display.setCursor(0, 48);
    display.print("Time: "); display.print(remaining_time_h, 1); display.println(" h");
  }
  display.display();
  
  delay(2000);
}