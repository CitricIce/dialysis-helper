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
//
// Optional intensity characteristic ...0003: [mode, 0..255 PWM duty].
// Adafruit motor drive supports variable duty; useful perceived range must be
// measured on the assembled band. Use a suitable transistor/driver, not a motor
// directly on GPIO. Existing ASCII characteristic and USB commands still work.

#include <BLEDevice.h>
#include <BLEServer.h>
#include <esp_arduino_version.h>

// Avoid GPIO 2, 8 and 9: they affect how the ESP32-C3 boots.
const int MOTOR_PIN = 4;

const char *DEVICE_NAME = "DialysisBand";
const char *SERVICE_UUID = "7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00";
const char *INTENSITY_UUID = "7a1e0003-3c5d-4b8a-9f21-6d2c8e4b1a00";
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
// One replaceable command across both characteristics; no stale command queue.
portMUX_TYPE commandLock = portMUX_INITIALIZER_UNLOCKED;
uint32_t pendingPacket = 0;
bool intensityActive = false;
unsigned long intensityReceiptMs = 0;
const unsigned long INTENSITY_WATCHDOG_MS = 300;

void setMotor(uint8_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(MOTOR_PIN, duty);
#else
  ledcWrite(0, duty);
#endif
}

void enqueue(uint32_t packet) {
  portENTER_CRITICAL(&commandLock);
  pendingPacket = packet;
  portEXIT_CRITICAL(&commandLock);
}

void stopPattern() {
  activePattern = nullptr;
  setMotor(0);
}

void startPattern(const uint16_t *pattern, size_t length) {
  activePattern = pattern;
  activeLength = length;
  activeIndex = 0;
  segmentStartMs = millis();
  setMotor(255);
}

#define PLAY(pattern) startPattern(pattern, sizeof(pattern) / sizeof(pattern[0]))

// A new command replaces whatever is playing, so a warning is never delayed.
void runCommand(char command) {
  if (command != 'O' && command != 'W' && command != 'E' && command != 'T' && command != 'S') return;
  intensityActive = false;
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
  setMotor(activeIndex % 2 == 0 ? 255 : 0);
}

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    if (characteristic->getLength() > 0) {
      enqueue(0x10000 | characteristic->getData()[0]);
    }
  }
};

// V2: exactly [mode, duty]. Mode 0=off, 1=proximity, 2=review cue.
// A nonzero mode needs a fresh packet every <=300 ms or shuts off. The phone
// sends at 100 ms intervals; invalid packets never extend this watchdog.
class IntensityCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    if (characteristic->getLength() != 2) return;
    const uint8_t *bytes = characteristic->getData();
    if (bytes[0] > 2) return;
    enqueue(0x20000 | (uint32_t(bytes[0]) << 8) | bytes[1]);
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    Serial.println("ble connected");
  }
  void onDisconnect(BLEServer *server) override {
    // Advertising stops on connect, so restart it to allow reconnecting.
    enqueue(0x10000 | 'S');
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
  pinMode(MOTOR_PIN, OUTPUT);
  digitalWrite(MOTOR_PIN, LOW);
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  if (!ledcAttach(MOTOR_PIN, 200, 8)) return; // Remain off if PWM setup fails.
#else
  ledcSetup(0, 200, 8);
  ledcAttachPin(MOTOR_PIN, 0);
#endif
  setMotor(0);
  Serial.begin(115200);

  setupBle();
  Serial.println("ready");

  // A buzz at power-on shows that the motor wiring works.
  PLAY(PATTERN_OK);
}

void loop() {
  portENTER_CRITICAL(&commandLock);
  uint32_t packet = pendingPacket;
  pendingPacket = 0;
  portEXIT_CRITICAL(&commandLock);
  if ((packet & 0xF0000) == 0x10000) {
    runCommand(char(packet & 0xFF));
  } else if ((packet & 0xF0000) == 0x20000) {
    stopPattern();
    uint8_t mode = (packet >> 8) & 0xFF;
    intensityActive = mode != 0;
    intensityReceiptMs = millis();
    setMotor(mode == 0 ? 0 : uint8_t(packet & 0xFF));
  }
  if (intensityActive && millis() - intensityReceiptMs > INTENSITY_WATCHDOG_MS) {
    intensityActive = false;
    setMotor(0);
  }
  while (Serial.available() > 0) {
    runCommand((char)Serial.read());
  }
  updatePattern();
  delay(1);
}
