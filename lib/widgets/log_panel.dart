import 'package:flutter/material.dart';

class LogPanel extends StatelessWidget {
  final List<String> logs;

  const LogPanel({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Monitoring log',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        'No events yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (BuildContext context, int index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            logs[index],
                            style: Theme.of(context).textTheme.bodyMedium,
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
