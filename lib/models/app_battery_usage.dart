class AppBatteryUsage {
  final String packageName;
  final String appName;
  final double foregroundMah;
  final double backgroundMah;
  final DateTime lastUpdated;

  const AppBatteryUsage({
    required this.packageName,
    required this.appName,
    this.foregroundMah = 0,
    this.backgroundMah = 0,
    required this.lastUpdated,
  });

  double get totalMah => foregroundMah + backgroundMah;

  AppBatteryUsage copyWith({
    String? packageName,
    String? appName,
    double? foregroundMah,
    double? backgroundMah,
    DateTime? lastUpdated,
  }) {
    return AppBatteryUsage(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      foregroundMah: foregroundMah ?? this.foregroundMah,
      backgroundMah: backgroundMah ?? this.backgroundMah,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
