import 'package:flutter/material.dart';

class BatteryCard extends StatelessWidget {
  final int current;
  final int level;
  final bool isCharging;
  final double voltage;
  final int? capacity;

  const BatteryCard({
    super.key,
    required this.current,
    required this.level,
    required this.isCharging,
    required this.voltage,
    this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  isCharging ? Icons.battery_charging_full : Icons.battery_full,
                  size: 40,
                  color: isCharging ? Colors.green : Colors.blue,
                ),
                Column(
                  children: [
                    const Text(
                      'LIVE CURRENT',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCurrent(current),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _getCurrentColor(),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text(
                      'VOLTAGE',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${voltage.toStringAsFixed(2)}V',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Battery Level Bar
            Container(
              height: 30,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                children: [
                  // Background
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),

                  // Battery Fill
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 500),
                    widthFactor: level / 100,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _getBatteryColor(level),
                            _getBatteryColor(level).withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),

                  // Percentage Text
                  Center(
                    child: Text(
                      '$level%',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Battery: $level%',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  isCharging ? '⚡ Charging' : '🔋 Discharging',
                  style: TextStyle(
                    color: isCharging ? Colors.green : Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            if (capacity != null) ...[
              const SizedBox(height: 8),
              Text(
                'Capacity: ${capacity}mAh',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCurrent(int current) {
    if (current == 0) return '0 mA';
    return current > 0 ? '+${current.abs()} mA' : '-${current.abs()} mA';
  }

  Color _getCurrentColor() {
    if (current == 0) return Colors.grey;
    return current > 0 ? Colors.green : Colors.red;
  }

  Color _getBatteryColor(int level) {
    if (level < 20) return Colors.red;
    if (level < 50) return Colors.orange;
    return Colors.green;
  }
}
