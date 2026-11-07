// Dialysis Helper wristband firmware for the ESP32-C3.
//
// Receives one-character commands over BLE or USB serial and plays a vibration
// pattern. Both connections use the same commands, so USB can replace BLE if
// Bluetooth is unreliable at the venue.
//
//   O  step OK    one short tap
//   W  warning    two medium pulses (hand is approaching the wrong zone)
//   E  error      two long pulses (hand reached the wrong zone)
//   T  test       one long pulse
//   S  stop       motor off now

#include <BLEDevice.h>
#include <BLEServer.h>

// Avoid GPIO 2, 8 and 9: they affect how the ESP32-C3 boots.
const int MOTOR_PIN = 4;

const char *DEVICE_NAME = "DialysisBand";
const char *SERVICE_UUID = "7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00";
const char *COMMAND_UUID = "7a1e0002-3c5d-4b8a-9f21-6d2c8e4b1a00";

// Patterns alternate on and off durations in milliseconds, starting with on.
const uint16_t PATTERN_OK[] = {80};
const uint16_t PATTERN_WARN[] = {150, 100, 150};
const uint16_t PATTERN_ERROR[] = {600, 150, 600};
const uint16_t PATTERN_TEST[] = {400};

const uint16_t *activePattern = nullptr;
size_t activeLength = 0;
size_t activeIndex = 0;
unsigned long segmentStartMs = 0;

// Set from the BLE task and read in loop().
volatile char pendingCommand = 0;

void stopPattern() {
  activePattern = nullptr;
  digitalWrite(MOTOR_PIN, LOW);
}

void startPattern(const uint16_t *pattern, size_t length) {
  activePattern = pattern;
  activeLength = length;
  activeIndex = 0;
  segmentStartMs = millis();
  digitalWrite(MOTOR_PIN, HIGH);
}

#define PLAY(pattern) startPattern(pattern, sizeof(pattern) / sizeof(pattern[0]))

// A new command replaces whatever is playing, so a warning is never delayed.
void runCommand(char command) {
  switch (command) {
    case 'O': PLAY(PATTERN_OK); break;
    case 'W': PLAY(PATTERN_WARN); break;
    case 'E': PLAY(PATTERN_ERROR); break;
    case 'T': PLAY(PATTERN_TEST); break;
    case 'S': stopPattern(); break;
    default: return;  // Ignore unknown bytes, including line endings.
  }
  Serial.print("cmd ");
  Serial.println(command);
}

// Uses millis() rather than delay() so new commands are picked up immediately.
// Every pattern has a fixed length, so the motor can't get stuck on.
void updatePattern() {
  if (activePattern == nullptr) return;
  if (millis() - segmentStartMs < activePattern[activeIndex]) return;

  activeIndex++;
  if (activeIndex >= activeLength) {
    stopPattern();
    return;
  }
  segmentStartMs = millis();
  digitalWrite(MOTOR_PIN, activeIndex % 2 == 0 ? HIGH : LOW);
}

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    if (characteristic->getLength() > 0) {
      pendingCommand = (char)characteristic->getData()[0];
    }
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    Serial.println("ble connected");
  }
  void onDisconnect(BLEServer *server) override {
    // Advertising stops on connect, so restart it to allow reconnecting.
    Serial.println("ble disconnected");
    BLEDevice::startAdvertising();
  }
};

void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);
  BLECharacteristic *command = service->createCharacteristic(
      COMMAND_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  command->setCallbacks(new CommandCallbacks());
  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void setup() {
  pinMode(MOTOR_PIN, OUTPUT);
  digitalWrite(MOTOR_PIN, LOW);
  Serial.begin(115200);

  setupBle();
  Serial.println("ready");

  // A buzz at power-on shows that the motor wiring works.
  PLAY(PATTERN_OK);
}

void loop() {
  if (pendingCommand != 0) {
    char command = pendingCommand;
    pendingCommand = 0;
    runCommand(command);
  }
  while (Serial.available() > 0) {
    runCommand((char)Serial.read());
  }
  updatePattern();
  delay(1);
}
