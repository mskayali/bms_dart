import 'package:flutter/material.dart';

/// Compact status card widget for displaying a single BMS metric.
///
/// Usage:
/// ```dart
/// StatusCard(
///   title: 'Voltaj',
///   value: '51.23 V',
///   icon: Icons.electric_bolt,
///   color: Colors.blue,
/// )
/// ```
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF58A6FF),
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 3,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8B949E),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
