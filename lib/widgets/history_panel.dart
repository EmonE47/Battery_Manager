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
          children: <Widget>[
            Text(
              'Recent battery samples',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: history.isEmpty
                  ? Center(
                      child: Text(
                        'No history captured yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final BatteryHistory entry = history[history.length - 1 - index];
                        final bool isCharging = entry.isCharging;
                        final Color color = isCharging ? Colors.green : Colors.red;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: color.withValues(alpha: 0.14),
                            child: Icon(
                              isCharging ? Icons.north_east : Icons.south_east,
                              size: 16,
                              color: color,
                            ),
                          ),
                          title: Text(
                            entry.currentFormatted,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          subtitle: Text(
                            'Level ${entry.level}% at ${entry.formattedTime}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          trailing: Text(
                            isCharging ? 'Charge' : 'Discharge',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: color),
                          ),
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
