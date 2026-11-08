// ArmGuard vibration band — ESP32 / ESP32-S3 / ESP32-C3 (any ESP32 with Bluetooth LE).
// NOTE: the ESP32-S2 has no Bluetooth and cannot run this sketch.
//
// Built from the basic motor example (motorPin 4 + analogWrite). The iPhone app
// (BandClient.swift) connects to "DialysisBand" and sends the current warning:
//
//   Command characteristic ...0002  ("Existing fixed patterns" in the app):
//     'W' = MEDIUM risk   'E' = HIGH risk   'S' = stop   'T' = test buzz
//   Intensity characteristic ...0003 ("PWM intensity v2" in the app):
//     [mode, duty]  mode 0 = off, 1 = MEDIUM, 2 = HIGH
//
// MEDIUM -> pulsing (on/off), HIGH -> continuous full strength.
// Safety: motor stops on Bluetooth disconnect, and in v2 mode if the phone
// stops refreshing for 300 ms. The same letters also work over USB serial
// (115200 baud), handy for testing the motor without the phone.
//
// Wiring: drive the motor through a transistor/MOSFET or motor driver board
// (with a flyback diode). Do not power the motor straight from the GPIO pin.

#include <BLEDevice.h>
#include <BLEServer.h>

const int motorPin = 4;

const char *DEVICE_NAME    = "DialysisBand";
const char *SERVICE_UUID   = "7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00";
const char *COMMAND_UUID   = "7a1e0002-3c5d-4b8a-9f21-6d2c8e4b1a00";
const char *INTENSITY_UUID = "7a1e0003-3c5d-4b8a-9f21-6d2c8e4b1a00";

// Tune these on the assembled band.
const uint8_t MEDIUM_DUTY = 200;          // same strength as the example sketch
const uint8_t HIGH_DUTY   = 255;
const unsigned long MEDIUM_ON_MS  = 250;
const unsigned long MEDIUM_OFF_MS = 250;
const unsigned long V2_WATCHDOG_MS = 300;
const unsigned long LEGACY_LIMIT_MS = 1500; // legacy writes have no heartbeat
const unsigned long TEST_MS = 400;

enum Level : uint8_t { LEVEL_OFF = 0, LEVEL_MEDIUM = 1, LEVEL_HIGH = 2 };

// Written by the BLE task, read in loop(): one replaceable command, no queue.
portMUX_TYPE commandLock = portMUX_INITIALIZER_UNLOCKED;
volatile bool hasPending = false;
volatile uint8_t pendingLevel = LEVEL_OFF;
volatile uint8_t pendingDuty = 0;
volatile bool pendingFromV2 = false;
volatile bool pendingTest = false;

Level level = LEVEL_OFF;
uint8_t duty = 0;
bool usingWatchdog = false;
unsigned long lastCommandMs = 0;
unsigned long levelStartMs = 0;   // pulse timing; reset only when the level changes
unsigned long testUntilMs = 0;

void setMotor(uint8_t value) { analogWrite(motorPin, value); }

void post(uint8_t newLevel, uint8_t newDuty, bool fromV2, bool test = false) {
  portENTER_CRITICAL(&commandLock);
  pendingLevel = newLevel;
  pendingDuty = newDuty;
  pendingFromV2 = fromV2;
  pendingTest = test;
  hasPending = true;
  portEXIT_CRITICAL(&commandLock);
}

// Single-letter commands (legacy characteristic and USB serial).
void postLetter(char c) {
  switch (c) {
    case 'W': post(LEVEL_MEDIUM, MEDIUM_DUTY, false); break;
    case 'E': post(LEVEL_HIGH, HIGH_DUTY, false); break;
    case 'S': post(LEVEL_OFF, 0, false); break;
    case 'T': post(LEVEL_OFF, 0, false, true); break;
    default: break;   // ignore 'O', line endings, anything unknown
  }
}

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    if (characteristic->getLength() > 0) postLetter((char)characteristic->getData()[0]);
  }
};

class IntensityCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    if (characteristic->getLength() != 2) return;
    const uint8_t *b = characteristic->getData();
    if (b[0] > 2) return;
    // Honor the supplied intensity, including zero, in both nonzero modes.
    post(b[0], b[0] == LEVEL_OFF ? 0 : b[1], true);
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override { Serial.println("ble connected"); }
  void onDisconnect(BLEServer *server) override {
    post(LEVEL_OFF, 0, false);          // never leave the motor running
    Serial.println("ble disconnected");
    BLEDevice::startAdvertising();       // allow the phone to reconnect
  }
};

void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *command = service->createCharacteristic(
      COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  command->setCallbacks(new CommandCallbacks());

  BLECharacteristic *intensity = service->createCharacteristic(
      INTENSITY_UUID, BLECharacteristic::PROPERTY_WRITE_NR);
  intensity->setCallbacks(new IntensityCallbacks());

  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void setup() {
  pinMode(motorPin, OUTPUT);
  analogWrite(motorPin, 0);
  Serial.begin(115200);
  setupBle();
  Serial.println("ready: send W (medium), E (high), S (stop), T (test)");

  // Short buzz at power-on proves the motor wiring works (like the example).
  analogWrite(motorPin, 200);
  delay(150);
  analogWrite(motorPin, 0);
}

void loop() {
  unsigned long now = millis();

  // 1. Take the newest command, if any.
  bool got = false, fromV2 = false, test = false;
  uint8_t newLevel = 0, newDuty = 0;
  portENTER_CRITICAL(&commandLock);
  if (hasPending) {
    got = true; newLevel = pendingLevel; newDuty = pendingDuty;
    fromV2 = pendingFromV2; test = pendingTest; hasPending = false;
  }
  portEXIT_CRITICAL(&commandLock);

  if (got) {
    if (test) {
      testUntilMs = now + TEST_MS;
    } else {
      testUntilMs = 0; // stop/disconnect must also cancel an active test pulse
      if ((Level)newLevel != level) {
        Serial.print("level ");
        Serial.println(newLevel == LEVEL_HIGH ? "HIGH" : newLevel == LEVEL_MEDIUM ? "MEDIUM" : "OFF");
        levelStartMs = now;
      }
      level = (Level)newLevel;
      duty = newDuty;
      usingWatchdog = fromV2;
      lastCommandMs = now;
    }
  }

  // 2. v2 safety watchdog: the phone refreshes every 100 ms while warning.
  if (usingWatchdog && level != LEVEL_OFF && now - lastCommandMs > V2_WATCHDOG_MS) {
    level = LEVEL_OFF;
    Serial.println("level OFF (watchdog)");
  }
  if (!usingWatchdog && level != LEVEL_OFF && now - lastCommandMs > LEGACY_LIMIT_MS) {
    level = LEVEL_OFF;
  }

  // 3. Drive the motor without delay(), so a new warning takes effect immediately.
  if (level == LEVEL_HIGH) {
    setMotor(duty);                                    // continuous
  } else if (level == LEVEL_MEDIUM) {
    unsigned long phase = (now - levelStartMs) % (MEDIUM_ON_MS + MEDIUM_OFF_MS);
    setMotor(phase < MEDIUM_ON_MS ? duty : 0);         // pulsing
  } else if (now < testUntilMs) {
    setMotor(200);
  } else {
    setMotor(0);
  }

  // 4. USB serial uses the same letters.
  while (Serial.available() > 0) postLetter((char)Serial.read());

  delay(5);
}
