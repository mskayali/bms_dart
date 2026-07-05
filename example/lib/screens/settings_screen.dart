import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jk_bms/jk_bms.dart';

/// Settings detail screen — shows BMS configuration parameters.
///
/// Ported from batmon-ha's settings frame handling. Displays protection
/// thresholds, current limits, battery type, and cell count.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.manager,
    this.initialSettings,
  });

  final JkBmsManager manager;
  final JkSettings? initialSettings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  JkSettings? _settings;
  StreamSubscription<BmsEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;

    _eventSub = widget.manager.eventStream.listen((event) {
      if (event is BmsSettingsEvent) {
        setState(() => _settings = event.data);
      }
    });

    // Request settings on open
    widget.manager.requestSettings();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BMS Ayarları',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.manager.requestSettings(),
          ),
        ],
      ),
      body: _settings == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF3FB950)),
                  SizedBox(height: 16),
                  Text(
                    'Ayar verisi bekleniyor...',
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // General info
                _sectionTitle('Genel'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row('Hücre Sayısı', '${_settings!.numCells}S'),
                        _row('Batarya Tipi', _settings!.batteryTypeName),
                        _row('Nominal Kapasite',
                            '${_settings!.nominalCapacity.toStringAsFixed(1)} Ah'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Voltage protection
                _sectionTitle('Voltaj Korumaları'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _protectionRow(
                          'OVP (Aşırı Voltaj)',
                          _settings!.cellOvp,
                          _settings!.cellOvpRecovery,
                          'V',
                          const Color(0xFFF85149),
                        ),
                        const Divider(color: Color(0xFF30363D), height: 16),
                        _protectionRow(
                          'UVP (Düşük Voltaj)',
                          _settings!.cellUvp,
                          _settings!.cellUvpRecovery,
                          'V',
                          const Color(0xFFFFA657),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Balancing
                _sectionTitle('Dengeleme'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row('Başlangıç Voltajı',
                            '${_settings!.balanceStartVoltage.toStringAsFixed(3)} V'),
                        _row('Delta Eşiği',
                            '${(_settings!.balanceDelta * 1000).toStringAsFixed(0)} mV'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Current limits
                _sectionTitle('Akım Limitleri'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _limitRow(
                          'Maks Şarj Akımı',
                          _settings!.maxChargeCurrent,
                          'A',
                          const Color(0xFF3FB950),
                        ),
                        const Divider(color: Color(0xFF30363D), height: 16),
                        _limitRow(
                          'Maks Deşarj Akımı',
                          _settings!.maxDischargeCurrent,
                          'A',
                          const Color(0xFFF85149),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Temperature protection
                _sectionTitle('Sıcaklık Korumaları'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _row('Şarj OTP',
                            '${_settings!.chargeOtp.toStringAsFixed(1)} °C'),
                        _row('Şarj UTP',
                            '${_settings!.chargeUtp.toStringAsFixed(1)} °C'),
                        const Divider(color: Color(0xFF30363D), height: 16),
                        _row('Deşarj OTP',
                            '${_settings!.dischargeOtp.toStringAsFixed(1)} °C'),
                        _row('Deşarj UTP',
                            '${_settings!.dischargeUtp.toStringAsFixed(1)} °C'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) {
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

  Widget _row(String label, String value) {
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

  Widget _protectionRow(
    String label,
    double threshold,
    double recovery,
    String unit,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        _row('Eşik', '${threshold.toStringAsFixed(3)} $unit'),
        _row('Kurtarma', '${recovery.toStringAsFixed(3)} $unit'),
      ],
    );
  }

  Widget _limitRow(String label, double value, String unit, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF8B949E))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${value.toStringAsFixed(1)} $unit',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
