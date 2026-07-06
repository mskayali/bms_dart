import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jk_bms/jk_bms.dart';
import 'package:universal_ble/universal_ble.dart';

import '../widgets/connection_indicator.dart';
import 'device_screen.dart';

/// BLE scan screen — discovers JK-BMS devices and allows connection.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final JkBmsManager _manager = JkBmsManager();
  final List<BleDevice> _devices = [];
  bool _isScanning = false;
  AvailabilityState? _bleState;
  StreamSubscription<BleDevice>? _scanSub;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    _checkBleAvailability();
    _cleanupStaleConnections();

    _scanSub = _manager.scanStream.listen((device) {
      // Only show devices that look like a BMS
      if (!JkBmsManager.isBmsDevice(device)) return;

      // Avoid duplicates
      final idx = _devices.indexWhere((d) => d.deviceId == device.deviceId);
      setState(() {
        if (idx >= 0) {
          _devices[idx] = device;
        } else {
          _devices.add(device);
        }
      });
    });
  }

  /// Disconnect any stale BLE connections left over from hot restart.
  ///
  /// During hot restart, the Dart state resets but the native BLE
  /// connection persists. This method finds connected devices and
  /// disconnects them so we start fresh.
  Future<void> _cleanupStaleConnections() async {
    try {
      final connected = await UniversalBle.getSystemDevices();
      for (final device in connected) {
        debugPrint('[JK-BMS] Cleaning up stale connection: ${device.deviceId}');
        await UniversalBle.disconnect(device.deviceId);
      }
    } catch (e) {
      debugPrint('[JK-BMS] Stale cleanup error (safe to ignore): $e');
    }
  }

  Future<void> _checkBleAvailability() async {
    final state = await UniversalBle.getBluetoothAvailabilityState();
    setState(() => _bleState = state);

    UniversalBle.onAvailabilityChange = (state) {
      setState(() => _bleState = state);
    };
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _manager.stopScan();
      setState(() => _isScanning = false);
    } else {
      _devices.clear();
      setState(() => _isScanning = true);
      await _manager.startScan();

      // Auto-stop after 15 seconds
      Future.delayed(const Duration(seconds: 15), () {
        if (_isScanning && mounted) {
          _manager.stopScan();
          setState(() => _isScanning = false);
        }
      });
    }
  }

  Future<void> _connectToDevice(BleDevice device) async {
    setState(() => _connectingDeviceId = device.deviceId);

    try {
      await _manager.stopScan();
      setState(() => _isScanning = false);

      await _manager.connect(device.deviceId);

      if (mounted) {
        setState(() => _connectingDeviceId = null);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceScreen(
              manager: _manager,
              device: device,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _connectingDeviceId = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bağlantı hatası: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleAvailable = _bleState == AvailabilityState.poweredOn;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BMS Scanner',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          ConnectionIndicator(state: _bleState),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // BLE Status Banner
          if (!bleAvailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.orange.shade900.withValues(alpha: 0.3),
              child: Row(
                children: [
                  const Icon(Icons.bluetooth_disabled, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bluetooth ${_bleState?.name ?? "bilinmiyor"}. '
                      'Lütfen Bluetooth\'u etkinleştirin.',
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          // Device List
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isScanning
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth,
                          size: 64,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'BMS cihazları aranıyor...'
                              : 'Tarama başlatmak için butona basın',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final isConnecting =
                          _connectingDeviceId == device.deviceId;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF238636).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.battery_charging_full,
                              color: Color(0xFF3FB950),
                            ),
                          ),
                          title: Text(
                            device.name ?? 'Bilinmeyen Cihaz',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            device.deviceId,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                          trailing: isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF3FB950),
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (device.rssi != null) ...[
                                      Icon(
                                        _rssiIcon(device.rssi!),
                                        size: 16,
                                        color: _rssiColor(device.rssi!),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${device.rssi} dBm',
                                        style: TextStyle(
                                          color: _rssiColor(device.rssi!),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white38,
                                    ),
                                  ],
                                ),
                          onTap: isConnecting
                              ? null
                              : () => _connectToDevice(device),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: bleAvailable ? _toggleScan : null,
        backgroundColor:
            _isScanning ? Colors.red.shade700 : const Color(0xFF238636),
        icon: Icon(_isScanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(_isScanning ? 'Durdur' : 'Tara'),
      ),
    );
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -50) return Icons.signal_cellular_4_bar;
    if (rssi >= -70) return Icons.signal_cellular_alt;
    return Icons.signal_cellular_alt_1_bar;
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -50) return const Color(0xFF3FB950);
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}
