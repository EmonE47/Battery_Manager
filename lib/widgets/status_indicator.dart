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
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color statusColor = isCharging
        ? Colors.green
        : (current.abs() > 900 ? Colors.red : colors.primary);
    final IconData statusIcon =
        isCharging ? Icons.battery_charging_full : Icons.battery_6_bar;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 20,
              backgroundColor: statusColor.withValues(alpha: 0.14),
              child: Icon(statusIcon, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isCharging ? 'Charging session active' : 'Discharging session active',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Health: $health | Current: ${_formatCurrent(current)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrent(int current) {
    if (current > 0) return '+$current mA';
    if (current < 0) return '$current mA';
    return '0 mA';
  }
}
