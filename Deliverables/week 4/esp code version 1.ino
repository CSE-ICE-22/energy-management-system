#include <Wire.h>
#include <Adafruit_INA219.h>
#include <LiquidCrystal_I2C.h>

// Initialize INA219s and LCD
Adafruit_INA219 ina219_battery(0x40); // Battery/load
Adafruit_INA219 ina219_charger(0x41); // Charger
LiquidCrystal_I2C lcd(0x27, 16, 2); // Adjust to 0x3F if needed

// Pins
const int mosfetPin = 23; // FQP27P06 gate
const int backlightPin = 25; // LCD backlight (via 2N3904)

// SoC thresholds for 3.7V Li-ion
const float socLow = 3.65;  // 40% SoC
const float socHigh = 3.8;  // 70% SoC
bool switchState = false;

// Backlight control
const unsigned long backlightTimeout = 30000;
unsigned long lastInteraction = 0;
bool backlightOn = true;

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22); // I²C pins (SDA, SCL)
  
  // Initialize MOSFET and backlight pins
  pinMode(mosfetPin, OUTPUT);
  digitalWrite(mosfetPin, HIGH); // P-MOSFET OFF
  pinMode(backlightPin, OUTPUT);
  digitalWrite(backlightPin, HIGH); // Backlight ON
  
  // Initialize INA219s
  if (!ina219_battery.begin()) {
    Serial.println("Failed INA219 #1 (0x40)");
    while (1);
  }
  if (!ina219_charger.begin()) {
    Serial.println("Failed INA219 #2 (0x41)");
    while (1);
  }
  
  // Initialize LCD
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("Battery Monitor");
  delay(2000);
  lcd.clear();
  lastInteraction = millis();
}

void loop() {
  // Read battery/load (INA219 #1)
  float battery_voltage = ina219_battery.getBusVoltage_V();
  float load_current_mA = ina219_battery.getCurrent_mA();
  
  // Read charger (INA219 #2)
  float charger_current_mA = ina219_charger.getCurrent_mA();
  
  // Estimate SoC
  float soc = map(battery_voltage, 3.0, 4.2, 0, 100);
  soc = constrain(soc, 0, 100);
  
  // Control charger
  if (battery_voltage <= socLow && !switchState) {
    digitalWrite(mosfetPin, LOW); // Charger ON
    switchState = true;
    Serial.println("Battery <= 40%, Charger ON");
    lcd.setCursor(0, 1);
    lcd.print("Chg:ON          ");
    digitalWrite(backlightPin, HIGH);
    backlightOn = true;
    lastInteraction = millis();
  } else if (battery_voltage >= socHigh && switchState) {
    digitalWrite(mosfetPin, HIGH); // Charger OFF
    switchState = false;
    Serial.println("Battery >= 70%, Charger OFF");
    lcd.setCursor(0, 1);
    lcd.print("Chg:OFF         ");
    digitalWrite(backlightPin, HIGH);
    backlightOn = true;
    lastInteraction = millis();
  }
  
  // Display on LCD
  lcd.setCursor(0, 0);
  lcd.print("V:");
  lcd.print(battery_voltage, 1);
  lcd.print(" I:");
  lcd.print(load_current_mA / 1000, 1);
  lcd.print("A");
  lcd.setCursor(0, 1);
  lcd.print("C:");
  lcd.print(charger_current_mA / 1000, 1);
  lcd.print("A");
  lcd.setCursor(10, 1);
  lcd.print(soc, 0);
  lcd.print("%");
  
  // Backlight control
  if (millis() - lastInteraction > backlightTimeout && backlightOn) {
    digitalWrite(backlightPin, LOW);
    lcd.noBacklight();
    backlightOn = false;
  }
  
  // Serial output
  Serial.print("Battery Voltage: ");
  Serial.print(battery_voltage, 2);
  Serial.print(" V, Load Current: ");
  Serial.print(load_current_mA / 1000, 2);
  Serial.print(" A, Charger Current: ");
  Serial.print(charger_current_mA / 1000, 2);
  Serial.print(" A, SoC: ");
  Serial.print(soc, 0);
  Serial.println("%");
  
  delay(1000);
}