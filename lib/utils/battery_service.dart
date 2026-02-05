import 'dart:async';
import 'dart:math';
import '../models/battery_data.dart';
import '../models/battery_history.dart';

class BatteryService {
  static final BatteryService _instance = BatteryService._internal();
  factory BatteryService() => _instance;
  BatteryService._internal();

  final StreamController<BatteryData> _batteryDataController =
      StreamController<BatteryData>.broadcast();

  final StreamController<List<BatteryHistory>> _historyController =
      StreamController<List<BatteryHistory>>.broadcast();

  final StreamController<List<String>> _logController =
      StreamController<List<String>>.broadcast();

  Stream<BatteryData> get batteryDataStream => _batteryDataController.stream;
  Stream<List<BatteryHistory>> get historyStream => _historyController.stream;
  Stream<List<String>> get logStream => _logController.stream;

  Timer? _monitoringTimer;
  final Random _random = Random();

  List<BatteryHistory> _history = [];
  List<String> _logs = [];

  // REALISTIC BATTERY PARAMETERS
  int _batteryLevel = 85; // 0-100%
  int _current = -350; // mA (negative = discharging, positive = charging)
  bool _isCharging = false;
  double _temperature = 25.0; // °C
  double _voltage = 3.8; // Volts
  int _designCapacity = 4000; // mAh (typical phone battery)
  int _cycleCount = 42; // Typical used cycles
  double _healthPercentage = 0.92; // 92% health
  String _technology = "Li-ion";

  // TRACKING VARIABLES - ADDED MISSING VARIABLES
  double _accumulatedCharge = 0; // mAh
  DateTime? _lastChargingStart;
  DateTime? _lastDischargingStart;
  Duration _totalChargingTime = Duration.zero; // ADDED THIS
  Duration _totalDischargingTime = Duration.zero; // ADDED THIS
  int _lastBatteryLevel = -1;
  bool _wasCharging = false;
  List<double> _capacityEstimates = [];

  // CONSTANTS
  final int _maxHistory = 50;
  final Duration _updateInterval = const Duration(seconds: 1);
  static const double CYCLE_THRESHOLD = 0.8; // 80% charge = 1 cycle

  void startMonitoring() {
    _addLog('✅ Monitoring started');
    _isCharging = _batteryLevel < 95 && _random.nextBool();

    // Start battery updates
    _monitoringTimer =
        Timer.periodic(_updateInterval, (_) => _updateBatteryData());

    // Add initial log
    _addLog('📱 Design capacity: $_designCapacity mAh');
    _addLog('⚡ Current: $_current mA');
  }

  void _updateBatteryData() {
    final now = DateTime.now();

    // REALISTIC BATTERY BEHAVIOR LOGIC

    // 1. Determine if charging or discharging based on realistic conditions
    if (_isCharging) {
      // CHARGING LOGIC
      if (_lastChargingStart == null) {
        _lastChargingStart = now;
        _addLog('⚡ Charging started');
      }

      // Realistic charging: faster at low battery, slower near full
      double chargeRateMultiplier = 1.0;
      if (_batteryLevel < 20) {
        chargeRateMultiplier = 2.5; // Fast charging at low battery
      } else if (_batteryLevel < 80) {
        chargeRateMultiplier = 1.8; // Medium charging
      } else {
        chargeRateMultiplier = 0.3; // Trickle charging near full
      }

      // Update battery level
      int levelIncrease =
          (chargeRateMultiplier * _random.nextDouble() * 2).round();
      _batteryLevel = (_batteryLevel + levelIncrease).clamp(0, 100);

      // Realistic charging current: varies based on charger and battery level
      if (_batteryLevel < 80) {
        _current =
            1500 + _random.nextInt(500); // Fast charging current (1500-2000 mA)
      } else {
        _current = 300 + _random.nextInt(200); // Trickle charging (300-500 mA)
      }

      // Calculate accumulated charge in mAh
      // mAh = (mA * hours) = (mA * seconds/3600)
      double chargeIncrement =
          (_current / 1000.0) * (_updateInterval.inSeconds / 3600.0);
      _accumulatedCharge += chargeIncrement;

      // Stop charging when full
      if (_batteryLevel >= 100) {
        _isCharging = false;
        _current = 0; // No current flow when full

        // Calculate charging cycle
        if (_accumulatedCharge >= _designCapacity * CYCLE_THRESHOLD) {
          _cycleCount++;
          _addLog('🔄 Charge cycle #$_cycleCount completed');
          _accumulatedCharge = 0;
        }

        if (_lastChargingStart != null) {
          final chargingDuration = now.difference(_lastChargingStart!);
          _totalChargingTime += chargingDuration;
          _lastChargingStart = null;
          _addLog(
              '🔋 Fully charged after ${_formatDuration(chargingDuration)}');
        }
      }

      // Reset discharging timer
      if (_lastDischargingStart != null) {
        final dischargingDuration = now.difference(_lastDischargingStart!);
        _totalDischargingTime += dischargingDuration;
        _lastDischargingStart = null;
        _addLog(
            '📉 Discharging stopped after ${_formatDuration(dischargingDuration)}');
      }
    } else {
      // DISCHARGING LOGIC
      if (_lastDischargingStart == null) {
        _lastDischargingStart = now;
        _addLog('🔋 Discharging started');
      }

      // Realistic discharging: faster with screen on, heavy usage
      double dischargeRateMultiplier = 1.0;
      if (_batteryLevel > 80) {
        dischargeRateMultiplier = 0.5; // Slower discharge at high battery
      } else if (_batteryLevel > 20) {
        dischargeRateMultiplier = 1.2; // Normal discharge
      } else {
        dischargeRateMultiplier = 1.5; // Faster discharge at low battery
      }

      // Simulate usage spikes
      if (_random.nextDouble() < 0.1) {
        // 10% chance of heavy usage
        dischargeRateMultiplier *= 3.0;
      }

      // Update battery level
      int levelDecrease =
          (dischargeRateMultiplier * _random.nextDouble() * 1.5).round();
      _batteryLevel = (_batteryLevel - levelDecrease).clamp(0, 100);

      // Realistic discharging current
      if (_random.nextDouble() < 0.3) {
        // 30% chance of screen on
        _current = -400 - _random.nextInt(300); // Screen on: -400 to -700 mA
      } else {
        _current = -150 - _random.nextInt(150); // Idle: -150 to -300 mA
      }

      // Start charging if battery low
      if (_batteryLevel <= 15 && !_isCharging) {
        _isCharging = true;
        _addLog('⚡ Started charging (low battery: $_batteryLevel%)');
      }

      // Reset charging timer
      if (_lastChargingStart != null) {
        final chargingDuration = now.difference(_lastChargingStart!);
        _totalChargingTime += chargingDuration;
        _lastChargingStart = null;
        _addLog(
            '⚡ Charging stopped after ${_formatDuration(chargingDuration)}');
      }
    }

    // 2. Update temperature based on current flow
    _updateTemperature();

    // 3. Update voltage based on battery level
    _updateVoltage();

    // 4. Track battery health degradation
    _updateHealth();

    // 5. Calculate current charging/discharging time
    Duration currentChargingTime = _totalChargingTime;
    Duration currentDischargingTime = _totalDischargingTime;

    if (_lastChargingStart != null) {
      currentChargingTime += now.difference(_lastChargingStart!);
    }

    if (_lastDischargingStart != null) {
      currentDischargingTime += now.difference(_lastDischargingStart!);
    }

    // 6. Calculate rates
    final chargingRate = _isCharging ? _current.abs() * 3.6 : 0; // mA/h
    final dischargingRate = !_isCharging ? _current.abs() * 3.6 : 0; // mA/h

    // 7. Estimate current capacity based on health
    final estimatedCapacity = _designCapacity * _healthPercentage;
    _capacityEstimates.add(estimatedCapacity);
    if (_capacityEstimates.length > 10) _capacityEstimates.removeAt(0);

    // 8. Track charge cycles via accumulation only (no duplicate detection)
    // Removed: if (_wasCharging && !_isCharging && _lastBatteryLevel > 80)

    // 9. Create battery data
    final batteryData = BatteryData(
      level: _batteryLevel,
      temperature: _temperature,
      voltage: _voltage,
      health: _getHealthString(),
      technology: _technology,
      capacity: estimatedCapacity.round(),
      current: _current,
      isCharging: _isCharging,
      chargingRate: chargingRate.toDouble(),
      dischargingRate: dischargingRate.toDouble(),
      cycleCount: _cycleCount,
      estimatedCapacity: _calculateAverageCapacity(),
      timestamp: now,
      chargingTime: currentChargingTime, // ADDED
      dischargingTime: currentDischargingTime, // ADDED
    );

    // 10. Emit data
    _batteryDataController.add(batteryData);

    // 11. Add to history
    _addToHistory(batteryData);

    // 12. Store for next cycle detection
    _lastBatteryLevel = _batteryLevel;
    _wasCharging = _isCharging;
  }

  void _updateTemperature() {
    // Temperature increases with high current flow
    double tempChange = 0;

    if (_current.abs() > 1000) {
      tempChange = 0.2; // Fast charging/Heavy usage
    } else if (_current.abs() > 500) {
      tempChange = 0.1; // Moderate usage
    } else {
      tempChange = -0.05; // Cooling when idle
    }

    // Add some randomness
    tempChange += (_random.nextDouble() - 0.5) * 0.1;

    _temperature += tempChange;
    _temperature = _temperature.clamp(20.0, 45.0); // Realistic phone temp range
  }

  void _updateVoltage() {
    // Voltage decreases as battery discharges
    double baseVoltage = 4.2; // Fully charged Li-ion voltage
    double minVoltage = 3.3; // Minimum safe voltage

    // Linear voltage drop (simplified)
    _voltage = minVoltage + (baseVoltage - minVoltage) * (_batteryLevel / 100);

    // Add small fluctuations
    _voltage += (_random.nextDouble() - 0.5) * 0.05;
    _voltage = _voltage.clamp(3.3, 4.2);
  }

  void _updateHealth() {
    // Health degrades slowly with cycles
    double degradationPerCycle = 0.0005; // 0.05% degradation per cycle

    if (_random.nextDouble() < 0.01) {
      // 1% chance per update
      _healthPercentage -= degradationPerCycle;
      _healthPercentage = _healthPercentage.clamp(0.5, 1.0);

      if (_cycleCount % 10 == 0) {
        _addLog(
            '📉 Health updated: ${(_healthPercentage * 100).toStringAsFixed(1)}%');
      }
    }
  }

  String _getHealthString() {
    if (_healthPercentage >= 0.9) return 'Excellent';
    if (_healthPercentage >= 0.8) return 'Good';
    if (_healthPercentage >= 0.7) return 'Fair';
    if (_healthPercentage >= 0.6) return 'Poor';
    return 'Bad';
  }

  double _calculateAverageCapacity() {
    if (_capacityEstimates.isEmpty) return _designCapacity.toDouble();

    double sum = 0;
    for (var estimate in _capacityEstimates) {
      sum += estimate;
    }
    return sum / _capacityEstimates.length;
  }

  void _addToHistory(BatteryData data) {
    final historyEntry = BatteryHistory(
      current: data.current,
      level: data.level,
      isCharging: data.isCharging,
      timestamp: data.timestamp,
    );

    _history.add(historyEntry);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }

    _historyController.add(List.from(_history));
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }

  void _addLog(String message) {
    final timestamp = DateTime.now();
    final formattedTime = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';

    _logs.insert(0, '$formattedTime: $message');
    if (_logs.length > 10) {
      _logs.removeLast();
    }

    _logController.add(List.from(_logs));
  }

  void stopMonitoring() {
    _monitoringTimer?.cancel();
    _addLog('⏹️ Monitoring stopped');

    // Log summary
    _addLog('📊 Final battery level: $_batteryLevel%');
    _addLog('🔄 Total cycles: $_cycleCount');
    _addLog(
        '📈 Average capacity: ${_calculateAverageCapacity().toStringAsFixed(0)} mAh');

    // Log total times
    _addLog('⚡ Total charging time: ${_formatDuration(_totalChargingTime)}');
    _addLog(
        '🔋 Total discharging time: ${_formatDuration(_totalDischargingTime)}');
  }

  void clearData() {
    _history.clear();
    _logs.clear();
    _batteryLevel = 85;
    _current = -350;
    _cycleCount = 42;
    _accumulatedCharge = 0;
    _healthPercentage = 0.92;
    _capacityEstimates.clear();
    _lastChargingStart = null;
    _lastDischargingStart = null;
    _totalChargingTime = Duration.zero;
    _totalDischargingTime = Duration.zero;

    _addLog('🔄 All data cleared');

    _historyController.add([]);
    _logController.add([]);
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _batteryDataController.close();
    _historyController.close();
    _logController.close();
  }
}
