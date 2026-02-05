class BatteryHistory {
  final int current;
  final int level;
  final bool isCharging;
  final DateTime timestamp;

  BatteryHistory({
    required this.current,
    required this.level,
    required this.isCharging,
    required this.timestamp,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get currentFormatted {
    if (current > 0) return '+${current.abs()} mA';
    if (current < 0) return '-${current.abs()} mA';
    return '0 mA';
  }
}
