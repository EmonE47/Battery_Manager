import 'dart:async';
import 'package:flutter/services.dart';
import '../models/battery_data.dart';
import '../models/battery_history.dart';

class RealBatteryService {
  static const platform = MethodChannel('com.example.battery_analyzer/battery');
  static const eventChannel =
      EventChannel('com.example.battery_analyzer/battery_events');

  final StreamController<BatteryData> _batteryDataController =
      StreamController<BatteryData>.broadcast();

  final StreamController<List<BatteryHistory>> _historyController =
      StreamController<List<BatteryHistory>>.broadcast();

  final StreamController<List<String>> _logController =
      StreamController<List<String>>.broadcast();

  Stream<BatteryData> get batteryDataStream => _batteryDataController.stream;
  Stream<List<BatteryHistory>> get historyStream => _historyController.stream;
  Stream<List<String>> get logStream => _logController.stream;

  List<BatteryHistory> _history = [];
  List<String> _logs = [];
  Timer? _monitoringTimer;

  final int _maxHistory = 50;
  final Duration _updateInterval = const Duration(seconds: 1);

  RealBatteryService() {
    _initializeData();
  }

  void _initializeData() {
    // Emit initial logs
    _addLog('🚀 Battery Analyzer Pro initialized');
    _addLog('📱 Waiting for battery data...');
    
    // Emit placeholder initial battery data
    final now = DateTime.now();
    final initialData = BatteryData(
      level: 0,
      temperature: 0,
      voltage: 0,
      health: 'Loading...',
      technology: 'Unknown',
      capacity: 0,
      current: 0,
      isCharging: false,
      chargingRate: 0,
      dischargingRate: 0,
      cycleCount: 0,
      estimatedCapacity: 0,
      timestamp: now,
      chargingTime: Duration.zero,
      dischargingTime: Duration.zero,
    );
    
    _batteryDataController.add(initialData);
    _historyController.add([]);
  }

  // Store real battery data
  int _lastLevel = 0;
  bool _lastIsCharging = false;
  DateTime? _lastChargingStart;
  DateTime? _lastDischargingStart;
  Duration _totalChargingTime = Duration.zero;
  Duration _totalDischargingTime = Duration.zero;
  int _cycleCount = 0;
  double _accumulatedCharge = 0;
  int _designCapacity = 4000; // Default, will be updated from device
  bool _capacityReceivedFromDevice = false; // Track if we got real capacity

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

  Future<void> startMonitoring() async {
    try {
      _addLog('✅ Starting real battery monitoring...');

      // Request battery permissions on Android
      // Note: BatteryManager API doesn't require special permissions
      final bool hasPermission =
          await platform.invokeMethod('requestPermissions');

      if (!hasPermission) {
        _addLog('⚠️ Permission check returned false, continuing anyway...');
      }

      _addLog('✅ Accessing real battery data via Android BatteryManager API');

      // Start background service for persistent monitoring
      try {
        await platform.invokeMethod('startBackgroundService');
        _addLog('🔔 Background notification service started');
      } catch (e) {
        _addLog('⚠️ Could not start background service: $e');
      }

      // Start listening to battery events
      _listenToBatteryEvents();

      // Also poll regularly for updates
      _monitoringTimer = Timer.periodic(_updateInterval, (_) async {
        await _fetchBatteryData();
      });

      // Get initial data
      await _fetchBatteryData();
    } on PlatformException catch (e) {
      _addLog('❌ Platform error: ${e.message}');
    } catch (e) {
      _addLog('❌ Error: $e');
    }
  }

  Future<void> stopMonitoring() async {
    try {
      _monitoringTimer?.cancel();
      _addLog('⏹️ Stopped monitoring');

      // Stop background service
      try {
        await platform.invokeMethod('stopBackgroundService');
        _addLog('🔔 Background notification service stopped');
      } catch (e) {
        _addLog('⚠️ Could not stop background service: $e');
      }
    } on PlatformException catch (e) {
      _addLog('❌ Platform error: ${e.message}');
    } catch (e) {
      _addLog('❌ Error: $e');
    }
  }

  void _listenToBatteryEvents() {
    // Listen to native battery events
    eventChannel.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        _processBatteryData(
            Map<String, dynamic>.from(event));
      }
    }, onError: (error) {
      _addLog('❌ Event channel error: $error');
    });
  }

  Future<void> _fetchBatteryData() async {
    try {
      final dynamic result = await platform.invokeMethod('getBatteryInfo');

      if (result is Map) {
        _processBatteryData(Map<String, dynamic>.from(result));
      } else if (result == null) {
        _addLog('⚠️ Received null battery data from native code');
      } else {
        _addLog('⚠️ Invalid battery data format: ${result.runtimeType}');
      }
    } on PlatformException catch (e) {
      _addLog('❌ Platform error: ${e.code} - ${e.message}');
    } catch (e) {
      _addLog('❌ Error fetching battery data: $e');
    }
  }

  void _processBatteryData(Map<String, dynamic> data) {
    final now = DateTime.now();

    // Extract data from Android BatteryManager
    int level = data['level'] ?? 0;
    int scale = data['scale'] ?? 100;
    bool isPlugged = data['isPlugged'] ?? false;
    int status = data['status'] ?? 0;
    double temperature = (data['temperature'] ?? 250) / 10.0;
    double voltage = (data['voltage'] ?? 3800) / 1000.0;
    int health = data['health'] ?? 1;
    String technology = data['technology'] ?? 'Unknown';
    int currentMicroA = data['current'] ?? 0;
    int current = currentMicroA ~/ 1000; // Convert μA to mA

    // Get actual design capacity from device
    if (data['designCapacity'] != null && !_capacityReceivedFromDevice) {
      int deviceCapacity = (data['designCapacity'] as num).toInt();
      if (deviceCapacity > 1000 && deviceCapacity < 30000) {
        _designCapacity = deviceCapacity;
        _capacityReceivedFromDevice = true;
        _addLog('✅ Device capacity detected: ${_designCapacity}mAh');
      }
    } else if (data['fullChargeCapacity'] != null && !_capacityReceivedFromDevice) {
      int deviceCapacity = (data['fullChargeCapacity'] as num).toInt();
      if (deviceCapacity > 1000 && deviceCapacity < 30000) {
        _designCapacity = deviceCapacity;
        _capacityReceivedFromDevice = true;
        _addLog('✅ Full charge capacity detected: ${_designCapacity}mAh');
      }
    }

    // Calculate battery percentage
    int batteryPercent = (scale > 0) ? (level * 100 ~/ scale) : 0;

    // Determine charging status
    bool isCharging = isPlugged ||
        status == 2 || // BatteryManager.BATTERY_STATUS_CHARGING
        status == 5; // BatteryManager.BATTERY_STATUS_FULL

    // Track charging/discharging time
    _trackChargingTime(isCharging, now);

    // Calculate charging/discharging rates
    // Note: current is negative when discharging, positive when charging
    double chargingRate = isCharging && current > 0 ? current * 3.6 : 0;
    double dischargingRate =
        !isCharging && current < 0 ? current.abs() * 3.6 : 0;

    // Track charge cycles
    _trackChargeCycles(batteryPercent, isCharging, current);

    // Estimate capacity and health
    double estimatedCapacity = _estimateCapacity(data);
    double healthPercentage = _calculateHealthPercentage(health, voltage, temperature);
    double actualCapacity = _designCapacity * (healthPercentage / 100.0);

    // Get health string
    String healthString = _getHealthString(health);

    // Create battery data
    final batteryData = BatteryData(
      level: batteryPercent,
      temperature: temperature,
      voltage: voltage,
      health: healthString,
      technology: technology,
      capacity: estimatedCapacity.round(),
      current: current,
      isCharging: isCharging,
      chargingRate: chargingRate,
      dischargingRate: dischargingRate,
      cycleCount: _cycleCount,
      estimatedCapacity: estimatedCapacity,
      timestamp: now,
      chargingTime: _totalChargingTime,
      dischargingTime: _totalDischargingTime,
      healthPercentage: healthPercentage,
      actualCapacity: actualCapacity,
    );

    // Emit data
    _batteryDataController.add(batteryData);

    // Add to history
    _addToHistory(batteryData);

    // Store for next update
    _lastLevel = batteryPercent;
    _lastIsCharging = isCharging;
  }

  void _trackChargingTime(bool isCharging, DateTime now) {
    if (isCharging) {
      if (_lastChargingStart == null) {
        _lastChargingStart = now;
        _addLog('⚡ Real charging detected');
      }
      if (_lastDischargingStart != null) {
        _totalDischargingTime += now.difference(_lastDischargingStart!);
        _lastDischargingStart = null;
      }
    } else {
      if (_lastDischargingStart == null) {
        _lastDischargingStart = now;
        _addLog('🔋 Real discharging detected');
      }
      if (_lastChargingStart != null) {
        _totalChargingTime += now.difference(_lastChargingStart!);
        _lastChargingStart = null;
      }
    }
  }

  void _trackChargeCycles(int level, bool isCharging, int current) {
    if (isCharging && current > 0) {
      // Accumulate charge during charging
      double chargeIncrement =
          (current / 1000.0) * (_updateInterval.inSeconds / 3600.0);
      _accumulatedCharge += chargeIncrement;

      // Check if we completed a charge cycle (80% of capacity)
      if (_accumulatedCharge >= _designCapacity * 0.8) {
        _cycleCount++;
        _accumulatedCharge = 0;
        _addLog('🔄 Real charge cycle detected: $_cycleCount');
      }
    }
    // Removed duplicate cycle detection based on level changes
  }

  double _estimateCapacity(Map<String, dynamic> data) {
    try {
      // Try to get capacity property first (percentage of design capacity - available on API 21+)
      int capacity = data['capacity'] ?? 0;
      if (capacity > 0 && capacity <= 100) {
        // Capacity is percentage of design capacity
        double estimatedCap = _designCapacity * capacity / 100.0;
        _addLog('📊 Capacity from API: ${estimatedCap.toInt()}mAh (${capacity}%)');
        return estimatedCap;
      }

      // Try to get charge counter (available on API level 21+)
      int chargeCounter = data['chargeCounter'] ?? 0;
      if (chargeCounter > 0) {
        // Charge counter is in nAh, convert to mAh
        double estimatedCap = chargeCounter / 1000000.0;
        _addLog('📊 Capacity from charge counter: ${estimatedCap.toInt()}mAh');
        return estimatedCap;
      }

      // Fallback: estimate based on voltage and current
      double voltage = (data['voltage'] ?? 3800) / 1000.0;
      int currentMicroA = data['current'] ?? 0;
      int current = currentMicroA ~/ 1000; // Convert to mA

      // Estimate based on voltage curve for Li-ion
      double estimatedCap;
      if (voltage > 4.15) {
        estimatedCap = _designCapacity * 0.98;
      } else if (voltage > 4.0) {
        estimatedCap = _designCapacity * 0.90;
      } else if (voltage > 3.8) {
        estimatedCap = _designCapacity * 0.70;
      } else if (voltage > 3.6) {
        estimatedCap = _designCapacity * 0.40;
      } else if (voltage > 3.2) {
        estimatedCap = _designCapacity * 0.10;
      } else {
        estimatedCap = _designCapacity * 0.05;
      }
      
      _addLog('📊 Capacity estimated from voltage: ${estimatedCap.toInt()}mAh');
      return estimatedCap;
    } catch (e) {
      _addLog('⚠️ Error estimating capacity: $e');
      return _designCapacity.toDouble();
    }
  }

  String _getHealthString(int health) {
    switch (health) {
      case 2:
        return 'Good';
      case 3:
        return 'Overheat';
      case 4:
        return 'Dead';
      case 5:
        return 'Over Voltage';
      case 6:
        return 'Unspecified Failure';
      case 7:
        return 'Cold';
      default:
        return 'Unknown';
    }
  }

  double _calculateHealthPercentage(int health, double voltage, double temperature) {
    double healthScore = 100.0;
    
    // Health based on battery status constant
    switch (health) {
      case 2: // BATTERY_HEALTH_GOOD
        healthScore = 95.0;
        break;
      case 3: // BATTERY_HEALTH_OVERHEAT
        healthScore = 60.0;
        break;
      case 4: // BATTERY_HEALTH_DEAD
        healthScore = 10.0;
        break;
      case 5: // BATTERY_HEALTH_OVER_VOLTAGE
        healthScore = 50.0;
        break;
      case 6: // BATTERY_HEALTH_UNSPECIFIED_FAILURE
        healthScore = 30.0;
        break;
      case 7: // BATTERY_HEALTH_COLD
        healthScore = 70.0;
        break;
      default:
        healthScore = 85.0; // Unknown status
    }
    
    // Adjust health based on voltage (Li-ion batteries degrade when over/under charged)
    if (voltage > 4.25) {
      healthScore -= 5; // Over-voltage reduces health
    } else if (voltage < 2.5) {
      healthScore -= 10; // Deep discharge reduces health significantly
    }
    
    // Adjust health based on temperature
    if (temperature > 45) {
      healthScore -= (temperature - 45) * 2; // High temp reduces health
    } else if (temperature < 0) {
      healthScore -= (0 - temperature) * 1.5; // Low temp slightly reduces health
    }
    
    // Ensure health is between 0 and 100
    return healthScore.clamp(0.0, 100.0);
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

  void _provideFallbackData() {
    // Provide simulated data if real data fails
    final now = DateTime.now();
    final fallbackData = BatteryData(
      level: 85,
      temperature: 25.0,
      voltage: 3.8,
      health: 'Good',
      technology: 'Li-ion',
      capacity: 4000,
      current: -350,
      isCharging: false,
      chargingRate: 0,
      dischargingRate: 1260, // 350mA * 3.6
      cycleCount: _cycleCount,
      estimatedCapacity: 4000.0,
      timestamp: now,
      chargingTime: _totalChargingTime,
      dischargingTime: _totalDischargingTime,
    );

    _batteryDataController.add(fallbackData);
    _addToHistory(fallbackData);
    _addLog('⚠️ Using simulated data (real data unavailable)');
  }

  void clearData() {
    _history.clear();
    _logs.clear();
    _cycleCount = 0;
    _accumulatedCharge = 0;
    _totalChargingTime = Duration.zero;
    _totalDischargingTime = Duration.zero;
    _lastChargingStart = null;
    _lastDischargingStart = null;

    _addLog('🔄 Real data cleared');
    _historyController.add([]);
    _logController.add([]);
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _batteryDataController.close();
    _historyController.close();
    _logController.close();
  }
}
