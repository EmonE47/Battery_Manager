import 'package:flutter/material.dart';

class StatusIndicator extends StatelessWidget {
  final bool isCharging;
  final String health;
  final int current;

  const StatusIndicator({
    super.key,
    required this.isCharging,
    required this.health,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final (statusText, icon, bgColor) = _getStatusInfo();

    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Health: $health | Current: ${_formatCurrent(current)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.info, color: Colors.white),
          ],
        ),
      ),
    );
  }

  (String, IconData, Color) _getStatusInfo() {
    if (isCharging) {
      return (
        'CHARGING',
        Icons.battery_charging_full,
        Colors.green,
      );
    } else {
      return (
        'DISCHARGING',
        Icons.battery_alert,
        current.abs() > 500 ? Colors.red : Colors.blue,
      );
    }
  }

  String _formatCurrent(int current) {
    if (current > 0) return '+${current.abs()} mA';
    if (current < 0) return '-${current.abs()} mA';
    return '0 mA';
  }
}
