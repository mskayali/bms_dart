import 'package:flutter/material.dart';

/// Horizontal bar chart displaying individual cell voltages.
///
/// Each cell is shown as a colored bar with its voltage label.
/// Only the first [enabledCellCount] cells are displayed if it's > 0.
class CellVoltageChart extends StatelessWidget {
  const CellVoltageChart({
    super.key,
    required this.voltages,
    this.enabledCellCount = 0,
  });

  /// Cell voltages in volts. Index 0 = Cell 1.
  final List<double> voltages;

  /// Number of enabled cells (from bitmask). If 0, show all non-zero cells.
  final int enabledCellCount;

  @override
  Widget build(BuildContext context) {
    // Determine which cells to display
    final displayCount = enabledCellCount > 0
        ? enabledCellCount
        : voltages.where((v) => v > 0).length;

    if (displayCount == 0) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Hücre verisi yok',
              style: TextStyle(color: Color(0xFF8B949E)),
            ),
          ),
        ),
      );
    }

    final displayVoltages = voltages.take(displayCount).toList();

    // Find min/max for scaling
    final nonZero = displayVoltages.where((v) => v > 0);
    if (nonZero.isEmpty) {
      return const SizedBox.shrink();
    }

    final minV = nonZero.reduce((a, b) => a < b ? a : b);
    final maxV = nonZero.reduce((a, b) => a > b ? a : b);
    final range = maxV - minV;

    // For coloring: cells close to min are warm, close to max are cool
    Color cellColor(double voltage) {
      if (voltage <= 0) return Colors.grey;
      if (range < 0.001) return const Color(0xFF3FB950); // all equal

      final normalized = (voltage - minV) / range;
      if (normalized < 0.25) return const Color(0xFFF85149); // low
      if (normalized < 0.50) return const Color(0xFFFFA657); // below avg
      return const Color(0xFF3FB950); // good
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Min: ${minV.toStringAsFixed(3)} V',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFF85149),
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'Δ: ${(range * 1000).toStringAsFixed(0)} mV',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8B949E),
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'Max: ${maxV.toStringAsFixed(3)} V',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF3FB950),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bars
            ...displayVoltages.asMap().entries.map((entry) {
              final cellNum = entry.key + 1;
              final voltage = entry.value;

              // Bar fill ratio (0..1) relative to range
              double fillRatio;
              if (range < 0.001) {
                fillRatio = 1.0;
              } else {
                fillRatio = ((voltage - minV) / range).clamp(0.0, 1.0);
              }
              // Ensure minimum bar width for visibility
              fillRatio = 0.3 + fillRatio * 0.7;

              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$cellNum',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF8B949E),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              // Background
                              Container(
                                height: 18,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF21262D),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              // Fill
                              Container(
                                height: 18,
                                width: constraints.maxWidth * fillRatio,
                                decoration: BoxDecoration(
                                  color: cellColor(voltage).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 60,
                      child: Text(
                        voltage > 0
                            ? voltage.toStringAsFixed(3)
                            : '—',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: cellColor(voltage),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
