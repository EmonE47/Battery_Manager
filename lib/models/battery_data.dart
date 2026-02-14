class BatteryData {
  final int level;
  final double temperature;
  final double voltage;
  final String health;
  final String technology;
  final int capacity;
  final int current;
  final bool isCharging;
  final double chargingRate;
  final double dischargingRate;
  final int cycleCount;
  final double estimatedCapacity;
  final DateTime timestamp;
  final Duration chargingTime;
  final Duration dischargingTime;
  final double healthPercentage;
  final double actualCapacity;
  final int designCapacity;
  final double chargedSinceStart;
  final double dischargedSinceStart;
  final double netMahSinceStart;
  final double averagePowerMw;
  final double stressScore;
  final double projectedTimeToFullHours;
  final double projectedTimeToEmptyHours;
  final String manufacturer;
  final String brand;
  final String model;
  final String device;
  final bool isDesignCapacityManual;
  final int? manualDesignCapacity;

  const BatteryData({
    required this.level,
    required this.temperature,
    required this.voltage,
    required this.health,
    required this.technology,
    required this.capacity,
    required this.current,
    required this.isCharging,
    this.chargingRate = 0,
    this.dischargingRate = 0,
    this.cycleCount = 0,
    this.estimatedCapacity = 0,
    required this.timestamp,
    required this.chargingTime,
    required this.dischargingTime,
    this.healthPercentage = 100.0,
    this.actualCapacity = 4000.0,
    this.designCapacity = 4000,
    this.chargedSinceStart = 0,
    this.dischargedSinceStart = 0,
    this.netMahSinceStart = 0,
    this.averagePowerMw = 0,
    this.stressScore = 0,
    this.projectedTimeToFullHours = 0,
    this.projectedTimeToEmptyHours = 0,
    this.manufacturer = 'Unknown',
    this.brand = 'Unknown',
    this.model = 'Unknown',
    this.device = 'Unknown',
    this.isDesignCapacityManual = false,
    this.manualDesignCapacity,
  });

  factory BatteryData.empty() {
    return BatteryData(
      level: 0,
      temperature: 0,
      voltage: 0,
      health: 'Unknown',
      technology: 'Unknown',
      capacity: 0,
      current: 0,
      isCharging: false,
      timestamp: DateTime.now(),
      chargingTime: Duration.zero,
      dischargingTime: Duration.zero,
      healthPercentage: 0,
      actualCapacity: 0,
      designCapacity: 0,
      manualDesignCapacity: null,
    );
  }

  BatteryData copyWith({
    int? level,
    double? temperature,
    double? voltage,
    String? health,
    String? technology,
    int? capacity,
    int? current,
    bool? isCharging,
    double? chargingRate,
    double? dischargingRate,
    int? cycleCount,
    double? estimatedCapacity,
    DateTime? timestamp,
    Duration? chargingTime,
    Duration? dischargingTime,
    double? healthPercentage,
    double? actualCapacity,
    int? designCapacity,
    double? chargedSinceStart,
    double? dischargedSinceStart,
    double? netMahSinceStart,
    double? averagePowerMw,
    double? stressScore,
    double? projectedTimeToFullHours,
    double? projectedTimeToEmptyHours,
    String? manufacturer,
    String? brand,
    String? model,
    String? device,
    bool? isDesignCapacityManual,
    int? manualDesignCapacity,
  }) {
    return BatteryData(
      level: level ?? this.level,
      temperature: temperature ?? this.temperature,
      voltage: voltage ?? this.voltage,
      health: health ?? this.health,
      technology: technology ?? this.technology,
      capacity: capacity ?? this.capacity,
      current: current ?? this.current,
      isCharging: isCharging ?? this.isCharging,
      chargingRate: chargingRate ?? this.chargingRate,
      dischargingRate: dischargingRate ?? this.dischargingRate,
      cycleCount: cycleCount ?? this.cycleCount,
      estimatedCapacity: estimatedCapacity ?? this.estimatedCapacity,
      timestamp: timestamp ?? this.timestamp,
      chargingTime: chargingTime ?? this.chargingTime,
      dischargingTime: dischargingTime ?? this.dischargingTime,
      healthPercentage: healthPercentage ?? this.healthPercentage,
      actualCapacity: actualCapacity ?? this.actualCapacity,
      designCapacity: designCapacity ?? this.designCapacity,
      chargedSinceStart: chargedSinceStart ?? this.chargedSinceStart,
      dischargedSinceStart: dischargedSinceStart ?? this.dischargedSinceStart,
      netMahSinceStart: netMahSinceStart ?? this.netMahSinceStart,
      averagePowerMw: averagePowerMw ?? this.averagePowerMw,
      stressScore: stressScore ?? this.stressScore,
      projectedTimeToFullHours:
          projectedTimeToFullHours ?? this.projectedTimeToFullHours,
      projectedTimeToEmptyHours:
          projectedTimeToEmptyHours ?? this.projectedTimeToEmptyHours,
      manufacturer: manufacturer ?? this.manufacturer,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      device: device ?? this.device,
      isDesignCapacityManual:
          isDesignCapacityManual ?? this.isDesignCapacityManual,
      manualDesignCapacity: manualDesignCapacity ?? this.manualDesignCapacity,
    );
  }
}
