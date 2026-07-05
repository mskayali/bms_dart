import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jk_bms/jk_bms.dart';
import 'package:universal_ble/universal_ble.dart';

import '../widgets/cell_voltage_chart.dart';
import '../widgets/status_card.dart';
import 'raw_log_screen.dart';
import 'settings_screen.dart';

/// Device dashboard screen — displays live BMS data.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({
    super.key,
    required this.manager,
    required this.device,
  });

  final JkBmsManager manager;
  final BleDevice device;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  JkCellStatus? _cellStatus;
  JkDeviceInfo? _deviceInfo;
  JkSettings? _settings;
  String? _lastError;
  bool _isPolling = false;
  Timer? _pollTimer;
  StreamSubscription<BmsEvent>? _eventSub;
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();

    _eventSub = widget.manager.eventStream.listen((event) {
      setState(() {
        switch (event) {
          case BmsCellStatusEvent(:final data):
            _cellStatus = data;
            _updateCount++;
            _lastError = null;
          case BmsDeviceInfoEvent(:final data):
            _deviceInfo = data;
            _lastError = null;
          case BmsRawFrameEvent():
            break;
          case BmsSettingsEvent(:final data):
            _settings = data;
            _lastError = null;
          case BmsErrorEvent(:final message):
            _lastError = message;
        }
      });
    });

    // Initial requests
    _requestData();
  }

  Future<void> _requestData() async {
    await widget.manager.requestDeviceInfo();
    await Future.delayed(const Duration(milliseconds: 500));
    await widget.manager.requestCellStatus();
  }

  void _togglePolling() {
    if (_isPolling) {
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() => _isPolling = false);
    } else {
      setState(() => _isPolling = true);
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => widget.manager.requestCellStatus(),
      );
    }
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    await widget.manager.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.name ?? 'JK-BMS',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          // Update counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF238636).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '#$_updateCount',
              style: const TextStyle(
                color: Color(0xFF3FB950),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Settings button
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'BMS Ayarları',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    manager: widget.manager,
                    initialSettings: _settings,
                  ),
                ),
              );
            },
          ),

          // Raw log button
          IconButton(
            icon: const Icon(Icons.terminal),
            tooltip: 'Ham Veri Logu',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RawLogScreen(manager: widget.manager),
                ),
              );
            },
          ),

          // Disconnect button
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Bağlantıyı Kes',
            onPressed: _disconnect,
          ),
        ],
      ),
      body: _cellStatus == null && _deviceInfo == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF3FB950)),
                  SizedBox(height: 16),
                  Text(
                    'BMS verisi bekleniyor...',
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _requestData,
              color: const Color(0xFF3FB950),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Error banner
                  if (_lastError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade800),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastError!,
                              style: const TextStyle(color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Device info
                  if (_deviceInfo != null) ...[
                    _buildSectionTitle('Cihaz Bilgisi'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_deviceInfo!.deviceName != null) _infoRow('Ad', _deviceInfo!.deviceName!),
                            if (_deviceInfo!.hardwareVersion != null) _infoRow('Donanım', _deviceInfo!.hardwareVersion!),
                            if (_deviceInfo!.softwareVersion != null) _infoRow('Yazılım', _deviceInfo!.softwareVersion!),
                            if (_deviceInfo!.serialNumber != null) _infoRow('Seri No', _deviceInfo!.serialNumber!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Main status cards
                  if (_cellStatus != null) ...[
                    _buildSectionTitle('Genel Durum'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusCard(
                          title: 'Voltaj',
                          value: '${_cellStatus!.totalVoltage.toStringAsFixed(2)} V',
                          icon: Icons.electric_bolt,
                          color: const Color(0xFF58A6FF),
                        ),
                        StatusCard(
                          title: 'Akım',
                          value: '${_cellStatus!.current.toStringAsFixed(2)} A',
                          icon: Icons.speed,
                          color: _cellStatus!.current >= 0 ? const Color(0xFF3FB950) : const Color(0xFFF85149),
                        ),
                        StatusCard(
                          title: 'Güç',
                          value: '${_cellStatus!.power.toStringAsFixed(1)} W',
                          icon: Icons.power,
                          color: const Color(0xFFD2A8FF),
                        ),
                        StatusCard(
                          title: 'SOC',
                          value: '${_cellStatus!.soc}%',
                          icon: Icons.battery_std,
                          color: _socColor(_cellStatus!.soc),
                        ),
                        StatusCard(
                          title: 'SOH',
                          value: '${_cellStatus!.soh}%',
                          icon: Icons.health_and_safety,
                          color: const Color(0xFF79C0FF),
                        ),
                        StatusCard(
                          title: 'Döngü',
                          value: '${_cellStatus!.cycleCount}',
                          icon: Icons.loop,
                          color: const Color(0xFFFFA657),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Temperatures
                    _buildSectionTitle('Sıcaklıklar'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusCard(
                          title: 'Sensör 1',
                          value: '${_cellStatus!.temperature1.toStringAsFixed(1)} °C',
                          icon: Icons.thermostat,
                          color: _tempColor(_cellStatus!.temperature1),
                        ),
                        StatusCard(
                          title: 'Sensör 2',
                          value: '${_cellStatus!.temperature2.toStringAsFixed(1)} °C',
                          icon: Icons.thermostat,
                          color: _tempColor(_cellStatus!.temperature2),
                        ),
                        if (_cellStatus!.mosTemperature != 0)
                          StatusCard(
                            title: 'MOS',
                            value: '${_cellStatus!.mosTemperature.toStringAsFixed(1)} °C',
                            icon: Icons.memory,
                            color: _tempColor(_cellStatus!.mosTemperature),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // MOSFET & Balancer status
                    _buildSectionTitle('Kontrol Durumları'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _switchRow('Şarj MOSFET', _cellStatus!.chargingEnabled),
                            _switchRow('Deşarj MOSFET', _cellStatus!.dischargingEnabled),
                            _switchRow('Ön Şarj', _cellStatus!.prechargeEnabled),
                            _switchRow('Dengeleme', _cellStatus!.balancerWorking),
                            _switchRow('Isıtma', _cellStatus!.heatingEnabled),
                            const Divider(color: Color(0xFF30363D)),
                            _infoRow('Denge Akımı', '${_cellStatus!.balanceCurrent.toStringAsFixed(3)} A'),
                            _infoRow('Denge Modu', _balancerActionText(_cellStatus!.balancerAction)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cell voltages chart
                    _buildSectionTitle(
                      'Hücre Voltajları (${_cellStatus!.enabledCellCount} aktif)',
                    ),
                    CellVoltageChart(
                      voltages: _cellStatus!.cellVoltages,
                      enabledCellCount: _cellStatus!.enabledCellCount,
                    ),
                    const SizedBox(height: 16),

                    // Cell voltage stats
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _infoRow('Ortalama', '${_cellStatus!.averageCellVoltage.toStringAsFixed(3)} V'),
                            _infoRow('Delta', '${_cellStatus!.deltaCellVoltage.toStringAsFixed(3)} V'),
                            _infoRow('Maks Hücre', '#${_cellStatus!.maxVoltageCellNumber}'),
                            _infoRow('Min Hücre', '#${_cellStatus!.minVoltageCellNumber}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Capacity info
                    _buildSectionTitle('Kapasite'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _infoRow('Kalan', '${_cellStatus!.capacityRemaining.toStringAsFixed(1)} Ah'),
                            _infoRow('Tam Kapasite', '${_cellStatus!.fullCapacity.toStringAsFixed(1)} Ah'),
                            _infoRow('Toplam Çalışma', _cellStatus!.totalRuntimeFormatted),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 80), // FAB clearance
                  ],
                ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Manual refresh
          FloatingActionButton.small(
            heroTag: 'refresh',
            backgroundColor: const Color(0xFF30363D),
            onPressed: _requestData,
            child: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(height: 8),
          // Auto-poll toggle
          FloatingActionButton.extended(
            heroTag: 'poll',
            backgroundColor: _isPolling ? Colors.red.shade700 : const Color(0xFF238636),
            icon: Icon(_isPolling ? Icons.stop : Icons.play_arrow),
            label: Text(_isPolling ? 'Durdur' : 'Otomatik'),
            onPressed: _togglePolling,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8B949E),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8B949E))),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8B949E))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: enabled ? const Color(0xFF238636).withValues(alpha: 0.2) : const Color(0xFFF85149).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              enabled ? 'AÇIK' : 'KAPALI',
              style: TextStyle(
                color: enabled ? const Color(0xFF3FB950) : const Color(0xFFF85149),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _socColor(int soc) {
    if (soc >= 60) return const Color(0xFF3FB950);
    if (soc >= 30) return const Color(0xFFFFA657);
    return const Color(0xFFF85149);
  }

  Color _tempColor(double temp) {
    if (temp <= 35) return const Color(0xFF3FB950);
    if (temp <= 50) return const Color(0xFFFFA657);
    return const Color(0xFFF85149);
  }

  String _balancerActionText(int action) {
    switch (action) {
      case 0:
        return 'Kapalı';
      case 1:
        return 'Şarj Dengeleme';
      case 2:
        return 'Deşarj Dengeleme';
      default:
        return 'Bilinmiyor ($action)';
    }
  }
}
