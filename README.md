# jk_bms

A robust Flutter plugin for communicating with **JK BMS** and **Daly BMS** devices over Bluetooth Low Energy (BLE). This library provides complete protocol parsers for real-time telemetry, device information, and battery statistics.

## Features

- **Multi-Protocol Support**: Seamlessly communicates with both JK BMS (JK02_24S, JK02_32S) and Daly BMS devices.
- **BLE Abstraction**: Uses `universal_ble` for robust cross-platform Bluetooth connections (iOS, macOS, Android, Windows, Linux).
- **Comprehensive Parsers**:
  - Cell Voltages & Balancer States
  - Total Voltage, Current, Power, and SOC
  - MOSFET Temperatures & Sensor Data
  - Device Information (Hardware Version, Software Version, Serial Number, Production Date)
  - Remaining Capacity and Cycle Count
- **Reactive API**: Exposes `Stream`s for device events (Connection, Telemetry, Device Info, Errors).

## Getting Started

Add `jk_bms` to your `pubspec.yaml`:

```yaml
dependencies:
  jk_bms: ^0.1.0
```

### Permissions
Ensure you have configured the required Bluetooth permissions for your target platforms (Android, iOS/macOS) as required by `universal_ble`.

**Android (`AndroidManifest.xml`):**
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**iOS/macOS (`Info.plist`):**
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>We need Bluetooth to connect to BMS devices.</string>
```

## Usage

```dart
import 'package:jk_bms/jk_bms.dart';

void main() async {
  final manager = JkBmsManager();

  // 1. Listen to BMS events
  manager.events.listen((event) {
    if (event is BmsStateEvent) {
      print('BMS Connected: ${event.isConnected}');
      print('Protocol Detected: ${event.protocol}');
    } else if (event is BmsTelemetryEvent) {
      final status = event.data;
      print('SOC: ${status.soc}%');
      print('Total Voltage: ${status.totalVoltage}V');
      print('Current: ${status.current}A');
    } else if (event is BmsDeviceInfoEvent) {
      print('Device Name: ${event.data.deviceName}');
      print('Hardware: ${event.data.hardwareVersion}');
    } else if (event is BmsErrorEvent) {
      print('Error: ${event.message}');
    }
  });

  // 2. Connect to a known BMS device by its BLE ID (MAC address or UUID)
  await manager.connect('9A0216E0-C944-99CB-F880-5F3A9A2602AA');
  
  // Note: The manager automatically discovers the protocol (JK vs Daly),
  // subscribes to the relevant characteristics, and starts polling for telemetry.
}
```

## Example App
Check the `example/` folder for a complete Flutter application demonstrating how to scan for BLE devices, connect to a BMS, and display its real-time telemetry in a beautiful dashboard.

## Contributing
Contributions are welcome! If you encounter issues or want to add support for another BMS protocol, feel free to open an issue or submit a pull request.
