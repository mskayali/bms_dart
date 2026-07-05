import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

/// Bluetooth availability state indicator widget.
///
/// Shows a colored dot with the current BLE state.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, this.state});

  final AvailabilityState? state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      AvailabilityState.poweredOn => (const Color(0xFF3FB950), 'BLE Açık'),
      AvailabilityState.poweredOff => (const Color(0xFFF85149), 'BLE Kapalı'),
      AvailabilityState.resetting => (const Color(0xFFFFA657), 'Sıfırlanıyor'),
      AvailabilityState.unsupported => (Colors.grey, 'Desteklenmiyor'),
      AvailabilityState.unauthorized => (const Color(0xFFF85149), 'İzin Yok'),
      _ => (Colors.grey, 'Bilinmiyor'),
    };

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
