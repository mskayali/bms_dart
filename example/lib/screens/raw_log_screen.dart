import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jk_bms/jk_bms.dart';

/// Raw BLE frame log screen for debugging.
///
/// Displays a scrollable list of all TX/RX BLE packets with
/// timestamps, direction, hex dumps, and frame type labels.
class RawLogScreen extends StatefulWidget {
  const RawLogScreen({super.key, required this.manager});

  final JkBmsManager manager;

  @override
  State<RawLogScreen> createState() => _RawLogScreenState();
}

class _RawLogScreenState extends State<RawLogScreen> {
  final List<BmsLogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<BmsLogEntry>? _logSub;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _logSub = widget.manager.logStream.listen((entry) {
      setState(() {
        _logs.add(entry);
        // Limit log size
        if (_logs.length > 500) {
          _logs.removeRange(0, _logs.length - 500);
        }
      });

      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ham Veri Logu',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          // Auto-scroll toggle
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.unfold_more,
              color: _autoScroll ? const Color(0xFF3FB950) : Colors.white38,
            ),
            tooltip: 'Otomatik kaydırma',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          // Clear logs
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Logları temizle',
            onPressed: () => setState(() => _logs.clear()),
          ),
        ],
      ),
      body: _logs.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 48, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'Henüz log verisi yok.\n'
                    'BMS\'ye komut gönderin veya\n'
                    'otomatik sorgulamayı başlatın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final entry = _logs[index];
                final isTx = entry.direction == 'TX';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isTx
                          ? const Color(0xFF58A6FF).withValues(alpha: 0.05)
                          : const Color(0xFF3FB950).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timestamp
                        Text(
                          _formatTime(entry.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Color(0xFF8B949E),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Direction badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isTx
                                ? const Color(0xFF58A6FF).withValues(alpha: 0.2)
                                : const Color(0xFF3FB950).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.direction,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: isTx
                                  ? const Color(0xFF58A6FF)
                                  : const Color(0xFF3FB950),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Message
                        Expanded(
                          child: Text(
                            entry.message,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFFC9D1D9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      // Quick send buttons
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          border: Border(top: BorderSide(color: Color(0xFF30363D))),
        ),
        child: SafeArea(
          child: Row(
            children: [
              _commandButton(
                'Device Info',
                Icons.info_outline,
                () => widget.manager.requestDeviceInfo(),
              ),
              const SizedBox(width: 8),
              _commandButton(
                'Cell Status',
                Icons.battery_full,
                () => widget.manager.requestCellStatus(),
              ),
              const SizedBox(width: 8),
              _commandButton(
                'Logbook',
                Icons.book,
                () => widget.manager.requestLogbook(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _commandButton(String label, IconData icon, VoidCallback onPressed) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF58A6FF),
          side: const BorderSide(color: Color(0xFF30363D)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}.'
        '${dt.millisecond.toString().padLeft(3, '0')}';
  }
}
