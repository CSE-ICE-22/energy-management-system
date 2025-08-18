// Include libraries for I2C, INA219, OLED, and Non Volatile Storage
#include <Wire.h>              // I2C communication library
#include <Adafruit_INA219.h>   // INA219 current sensor library
#include <Adafruit_SSD1306.h>  // SSD1306 OLED display library
#include <Preferences.h>       // Non-volatile storage (Non Volatile Storage) library for ESP32

// Define OLED display parameters
#define SCREEN_WIDTH 128      
#define SCREEN_HEIGHT 64       
#define OLED_RESET -1          
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// Initialize INA219 modules
Adafruit_INA219 ina219_load(0x40);    // discharge INA219 at I2C address 0x40
Adafruit_INA219 ina219_charge(0x41);  // Charge INA219 at I2C address 0x41

// Initialize Non Volatile Storage for storing capacity
Preferences preferences;              

// Variables for capacity and time tracking
float capacity_mAh = 0.0;             // Battery capacity in mAh, initialized to 0 for charging
unsigned long lastMillis = 0;         // Store last loop time for delta calculation
const int ledPin = 26;                // Blue LED pin (GPIO26) to signal 3000 mAh
bool ledOn = false;                   // Track LED state (off by default)

void setup() {
  Serial.begin(115200);              
  while (!Serial) {                   
    delay(1);
  }
  
  pinMode(ledPin, OUTPUT);           // Set GPIO26 as output for blue LED
  digitalWrite(ledPin, LOW);         // Turn off LED initially
  
  Wire.begin(21, 22);                // Initialize I2C with SDA=GPIO21, SCL=GPIO22
  
  // Initialize load INA219 (0x40)
  if (!ina219_load.begin()) {      
    Serial.println("Failed to find load INA219 at address 0x40"); 
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->GND, A1->GND"); 
    while (1) { delay(10); }         
  }
  
  // Initialize charge INA219 (0x41)
  if (!ina219_charge.begin()) {     
    Serial.println("Failed to find charge INA219 at address 0x41"); 
    Serial.println("Check wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND, A0->VCC, A1->GND, VIN+->TP4056 OUT+ via switch, VIN-->Battery +, Battery - to TP4056 B- and GND"); 
    while (1) { delay(10); }         
  }
  
  // Initialize OLED (0x3C)
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { 
    Serial.println(F("SSD1306 allocation failed at address 0x3C")); 
    Serial.println("Check OLED wiring: SDA->GPIO21, SCL->GPIO22, VCC->3V3, GND->GND"); 
    while (1) { delay(10); }         
  }
  
  // Load stored capacity from Non Volatile Storage for discharging mode
  preferences.begin("battery", false); // Open Non Volatile Storage namespace "battery"
  capacity_mAh = preferences.getFloat("capacity", 3000.0); // Load capacity, default 3000 mAh
  if (capacity_mAh < 0 || capacity_mAh > 5000) capacity_mAh = 3000.0; // Clamp to 0–5000 mAh
  
  // Reset capacity to 0 for charging mode (assumes charging starts from 0)
  if (ina219_charge.getCurrent_mA() > 10.0) { // If charge INA219 detects current, assume charging
    capacity_mAh = 0.0;                      // Reset capacity to 0 for new charging cycle
    preferences.putFloat("capacity", capacity_mAh); // Store reset capacity
  }
  
  // Initialize OLED display
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
  // Calculate time delta
  unsigned long currentMillis = millis();    
  float delta_t = (currentMillis - lastMillis) / 3600.0; 
  lastMillis = currentMillis;                
  
  // Read load/discharge measurements (INA219 0x40)
  float shunt_load_mV = ina219_load.getShuntVoltage_mV(); // Get shunt voltage (mV)
  float bus_load_V = ina219_load.getBusVoltage_V();       // Get bus voltage (V)
  float current_load_mA = ina219_load.getCurrent_mA();    // Get load current (mA)
  
  // Calculate battery and load voltages
  float battery_V = bus_load_V + (shunt_load_mV / 1000.0); // Battery voltage (V)
  float load_V = bus_load_V;                              // Load voltage (V)
  
  // Read charge measurements (INA219 0x41)
  float shunt_charge_mV = ina219_charge.getShuntVoltage_mV(); // Get shunt voltage (mV)
  float bus_charge_V = ina219_charge.getBusVoltage_V();       // Get bus voltage (V)
  float current_charge_mA = ina219_charge.getCurrent_mA();    // Get charge current (mA)
  
  // Charge voltage
  float charge_V = bus_charge_V;                             // Charge voltage (V)
  
  // Mode detection based on INA219 activity
  bool isCharging = (current_charge_mA > 10.0);               // Charging if charge current > 10 mA
  bool isDischarging = (current_load_mA > 10.0);              // Discharging if load current > 10 mA
  
  // Variables for calculations
  float remaining_capacity_mAh = capacity_mAh;                // Remaining capacity (mAh)
  float remaining_time_h = 0.0;                              // Remaining time (hours)
  
  if (isCharging) {
    // Charging mode: calculate capacity
    capacity_mAh += (current_charge_mA * delta_t);            // capacity = time (h) * current (mA) = mAh
    if (capacity_mAh < 0) capacity_mAh = 0;                  // Prevent negative capacity
    if (capacity_mAh >= 3000) {                              // Check if capacity reaches 3000 mAh
      capacity_mAh = 3000;                                   // Cap at 3000 mAh
      digitalWrite(ledPin, HIGH);                            // Turn on blue LED
      ledOn = true;                                          // Set LED state
    } else if (!ledOn) {                                     // If below 3000 mAh and LED not on
      digitalWrite(ledPin, LOW);                             // Keep LED off
    }
    preferences.putFloat("capacity", capacity_mAh);           // Store capacity in Non Volatile Storage
  } else if (isDischarging) {
    // Discharging mode: calculate remaining capacity and time
    remaining_capacity_mAh = capacity_mAh - (current_load_mA * delta_t); // remaining_capacity = capacity - (time * load_current)
    if (remaining_capacity_mAh < 0) remaining_capacity_mAh = 0; // Prevent negative capacity
    capacity_mAh = remaining_capacity_mAh;                    // Update capacity
    preferences.putFloat("capacity", capacity_mAh);           // Store updated capacity in Non Volatile Storage
    if (current_load_mA > 0) {                               // Avoid division by zero
      remaining_time_h = capacity_mAh / current_load_mA;      // remaining_time = capacity / load_current (hours)
    }
  }
  
  // Serial output for debugging
  Serial.print("Battery V: ");                              
  Serial.print(battery_V, 2);                                
  Serial.print(" V | Load I: ");                            
  Serial.print(current_load_mA, 2);                          
  Serial.print(" mA | Charge I: ");                          
  Serial.print(current_charge_mA, 2);                      
  Serial.print(" mA | Capacity: ");                          
  Serial.print(capacity_mAh, 2);                             
  Serial.print(" mAh | Remaining Cap: ");                    
  Serial.print(remaining_capacity_mAh, 2);                   
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
    display.print(current_load_mA, 1);                      
    display.println(" mA");                              
    display.setCursor(0, 32);                              
    display.print("Rem Cap: ");                              
    display.print((int)remaining_capacity_mAh);               
    display.println(" mAh");                                 
    display.setCursor(0, 48);                                
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
  preferences.end();                                       
}