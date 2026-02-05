// history_panel.dart implementation
import 'package:flutter/material.dart';
import '../models/battery_history.dart';

class HistoryPanel extends StatelessWidget {
  final List<BatteryHistory> history;

  const HistoryPanel({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HISTORY',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: history.isEmpty
                  ? const Center(
                      child: Text('No history data yet'),
                    )
                  : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final entry = history[history.length - 1 - index];
                        return ListTile(
                          leading: Icon(
                            entry.isCharging ? Icons.bolt : Icons.battery_alert,
                            color:
                                entry.isCharging ? Colors.green : Colors.blue,
                          ),
                          title: Text(entry.currentFormatted),
                          subtitle:
                              Text('${entry.level}% • ${entry.formattedTime}'),
                          trailing: Text('${entry.level}%'),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
