import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../models/battery_data.dart';
import '../models/battery_history.dart';

class RealBatteryService {
  static const MethodChannel _platform =
      MethodChannel('com.example.battery_analyzer/battery');
  static const EventChannel _eventChannel =
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

  final Duration _updateInterval = const Duration(seconds: 1);
  final int _maxHistory = 360;
  final int _maxLogs = 150;
  final int _maxCapacitySamples = 32;

  final List<BatteryHistory> _history = <BatteryHistory>[];
  final List<String> _logs = <String>[];
  final List<double> _capacitySamples = <double>[];

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _monitoringTimer;

  DateTime? _lastSampleTime;
  DateTime? _phaseStartTime;
  bool? _activePhaseCharging;

  Duration _totalChargingTime = Duration.zero;
  Duration _totalDischargingTime = Duration.zero;


  int _designCapacityMah = 4000;
  bool _capacityReceivedFromDevice = false;
  double _smoothedCapacityMah = 4000;
  int _cycleCount = 0;
  double _throughputMahForCycle = 0;

  double _chargedSinceStartMah = 0;
  double _dischargedSinceStartMah = 0;

  bool? _sessionCharging;
  int? _sessionStartLevel;
  double _sessionChargedMah = 0;
  double _sessionDischargedMah = 0;

  RealBatteryService() {
    _initializeData();
  }

  Future<bool> isBackgroundServiceRunning() async {
    try {
      return await _platform.invokeMethod<bool>('isBackgroundServiceRunning') ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _initializeData() {
    _addLog('Battery Analyzer initialized');
    _addLog('Collecting samples for capacity calibration');

    final BatteryData initialData = BatteryData.empty();
    _batteryDataController.add(initialData);
    _historyController.add(const <BatteryHistory>[]);
    _logController.add(List<String>.from(_logs));
  }

  Future<void> startMonitoring() async {
    if (_monitoringTimer != null) {
      _addLog('Monitoring already active');
      return;
    }

    try {
      _addLog('Starting battery monitoring');

      final bool permissionGranted =
          await _platform.invokeMethod<bool>('requestPermissions') ?? false;
      if (!permissionGranted) {
        _addLog('Notification permission not granted yet');
      }

      try {
        await _platform.invokeMethod<void>('startBackgroundService');
        _addLog('Background service started');
      } catch (error) {
        _addLog('Background service start failed: $error');
      }

      _listenToBatteryEvents();
      _monitoringTimer = Timer.periodic(_updateInterval, (_) {
        _fetchBatteryData();
      });
      await _fetchBatteryData();
    } on PlatformException catch (error) {
      _addLog('Platform error while starting monitoring: ${error.message}');
    } catch (error) {
      _addLog('Error while starting monitoring: $error');
    }
  }

  Future<void> stopMonitoring() async {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _platform.invokeMethod<void>('stopBackgroundService');
      _addLog('Background service stopped');
    } catch (error) {
      _addLog('Background service stop failed: $error');
    }

    _addLog('Monitoring stopped');
  }

  void _listenToBatteryEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          _processBatteryData(Map<String, dynamic>.from(event));
        }
      },
      onError: (Object error) {
        _addLog('Battery event stream error: $error');
      },
    );
  }

  Future<void> _fetchBatteryData() async {
    try {
      final dynamic result = await _platform.invokeMethod<dynamic>(
        'getBatteryInfo',
      );

      if (result is Map) {
        _processBatteryData(Map<String, dynamic>.from(result));
      }
    } on PlatformException catch (error) {
      _addLog('Platform error while fetching battery info: ${error.message}');
    } catch (error) {
      _addLog('Error while fetching battery info: $error');
    }
  }

  void _processBatteryData(Map<String, dynamic> data) {
    final DateTime now = DateTime.now();

    final int levelRaw = _toInt(data['level'], fallback: 0);
    final int scale = _toInt(data['scale'], fallback: 100);
    final bool isPlugged = data['isPlugged'] == true;
    final int status = _toInt(data['status'], fallback: 0);
    final int healthStatus = _toInt(data['health'], fallback: 1);
    final double temperatureC =
        _toDouble(data['temperature'], fallback: 250) / 10.0;
    final double voltageV = _toDouble(data['voltage'], fallback: 3800) / 1000.0;
    final String technology = (data['technology'] as String?)?.trim().isNotEmpty ==
            true
        ? (data['technology'] as String).trim()
        : 'Unknown';

    final int currentMicroA = _toInt(data['current'], fallback: 0);
    final int currentMa = currentMicroA ~/ 1000;

    _tryUpdateDesignCapacity(data);

    final int levelPercent = scale > 0
        ? ((levelRaw * 100) / scale).round().clamp(0, 100)
        : 0;

    final bool isCharging = isPlugged ||
        status == 2 ||
        status == 5;

    _updatePhaseDurations(now, isCharging);

    final double elapsedSeconds = _resolveElapsedSeconds(now);
    final double deltaMah = (currentMa * elapsedSeconds) / 3600.0;
    _integrateCharge(deltaMah, isCharging, levelPercent);
    _updateCycleCount(deltaMah.abs());

    final double measuredCapacityMah =
        _smoothedCapacityMah <= 0 ? _designCapacityMah.toDouble() : _smoothedCapacityMah;

    final double chargingRate = currentMa > 0 ? currentMa.toDouble() : 0;
    final double dischargingRate = currentMa < 0 ? currentMa.abs().toDouble() : 0;
    final double powerMw = currentMa.abs() * voltageV;
    final double stressScore = _calculateStressScore(
      temperatureC,
      voltageV,
      currentMa,
      measuredCapacityMah,
    );
    final double healthPercentage = _calculateHealthPercentage(
      healthStatus,
      measuredCapacityMah,
      stressScore,
    );
    final String health = _getHealthString(healthStatus, healthPercentage);

    final Duration chargingTime = _currentChargingDuration(now, isCharging);
    final Duration dischargingTime = _currentDischargingDuration(now, isCharging);

    final double remainingMah = measuredCapacityMah * (levelPercent / 100.0);
    final double missingMah = measuredCapacityMah - remainingMah;

    final double projectedTimeToFullHours =
        chargingRate > 0 ? missingMah / chargingRate : 0;
    final double projectedTimeToEmptyHours =
        dischargingRate > 0 ? remainingMah / dischargingRate : 0;

    final BatteryData batteryData = BatteryData(
      level: levelPercent,
      temperature: temperatureC,
      voltage: voltageV,
      health: health,
      technology: technology,
      capacity: remainingMah.round().clamp(0, 1000000),
      current: currentMa,
      isCharging: isCharging,
      chargingRate: chargingRate,
      dischargingRate: dischargingRate,
      cycleCount: _cycleCount,
      estimatedCapacity: measuredCapacityMah,
      timestamp: now,
      chargingTime: chargingTime,
      dischargingTime: dischargingTime,
      healthPercentage: healthPercentage,
      actualCapacity: measuredCapacityMah,
      designCapacity: _designCapacityMah,
      chargedSinceStart: _chargedSinceStartMah,
      dischargedSinceStart: _dischargedSinceStartMah,
      netMahSinceStart: _chargedSinceStartMah - _dischargedSinceStartMah,
      averagePowerMw: powerMw,
      stressScore: stressScore,
      projectedTimeToFullHours: projectedTimeToFullHours,
      projectedTimeToEmptyHours: projectedTimeToEmptyHours,
    );

    _batteryDataController.add(batteryData);
    _addToHistory(batteryData);

    _lastSampleTime = now;
  }

  void _tryUpdateDesignCapacity(Map<String, dynamic> data) {
    final int? fromDesign = _parseCapacityField(data['designCapacity']);
    final int? fromFull = _parseCapacityField(data['fullChargeCapacity']);
    final int? fromCounter = _parseChargeCounter(data['chargeCounter']);

    final int? candidate = fromDesign ?? fromFull ?? fromCounter;
    if (candidate != null && candidate >= 1000 && candidate <= 30000) {
      if (!_capacityReceivedFromDevice || candidate != _designCapacityMah) {
        _designCapacityMah = candidate;
        _capacityReceivedFromDevice = true;
        if (_capacitySamples.isEmpty) {
          _smoothedCapacityMah = candidate.toDouble();
        }
        _addLog('Detected design capacity: $_designCapacityMah mAh');
      }
    }
  }

  int? _parseCapacityField(dynamic rawValue) {
    final int parsed = _toInt(rawValue, fallback: 0);
    if (parsed <= 0) {
      return null;
    }

    if (parsed > 1000 && parsed < 30000) {
      return parsed;
    }
    return null;
  }

  int? _parseChargeCounter(dynamic rawValue) {
    final int parsed = _toInt(rawValue, fallback: 0);
    if (parsed <= 0) {
      return null;
    }

    if (parsed > 1000000) {
      final int asMah = parsed ~/ 1000;
      if (asMah > 1000 && asMah < 30000) {
        return asMah;
      }
    }
    return null;
  }

  void _updatePhaseDurations(DateTime now, bool isCharging) {
    if (_phaseStartTime == null || _activePhaseCharging == null) {
      _phaseStartTime = now;
      _activePhaseCharging = isCharging;
      return;
    }

    if (_activePhaseCharging == isCharging) {
      return;
    }

    final Duration phaseDuration = now.difference(_phaseStartTime!);
    if (_activePhaseCharging!) {
      _totalChargingTime += phaseDuration;
      _addLog('Charging phase ended after ${_formatDuration(phaseDuration)}');
    } else {
      _totalDischargingTime += phaseDuration;
      _addLog('Discharging phase ended after ${_formatDuration(phaseDuration)}');
    }

    _phaseStartTime = now;
    _activePhaseCharging = isCharging;
  }

  Duration _currentChargingDuration(DateTime now, bool isCharging) {
    if (_phaseStartTime == null || !isCharging) {
      return _totalChargingTime;
    }

    return _totalChargingTime + now.difference(_phaseStartTime!);
  }

  Duration _currentDischargingDuration(DateTime now, bool isCharging) {
    if (_phaseStartTime == null || isCharging) {
      return _totalDischargingTime;
    }

    return _totalDischargingTime + now.difference(_phaseStartTime!);
  }

  double _resolveElapsedSeconds(DateTime now) {
    if (_lastSampleTime == null) {
      return _updateInterval.inSeconds.toDouble();
    }

    final int elapsedMs = now.difference(_lastSampleTime!).inMilliseconds;
    if (elapsedMs <= 0) {
      return 1;
    }
    return max(1.0, elapsedMs / 1000.0);
  }

  void _integrateCharge(double deltaMah, bool isCharging, int levelPercent) {
    if (deltaMah > 0) {
      _chargedSinceStartMah += deltaMah;
      if (_sessionCharging == true) {
        _sessionChargedMah += deltaMah;
      }
    } else if (deltaMah < 0) {
      final double discharge = deltaMah.abs();
      _dischargedSinceStartMah += discharge;
      if (_sessionCharging == false) {
        _sessionDischargedMah += discharge;
      }
    }

    if (_sessionCharging == null || _sessionStartLevel == null) {
      _sessionCharging = isCharging;
      _sessionStartLevel = levelPercent;
      return;
    }

    if (_sessionCharging != isCharging) {
      _commitSessionEstimate(levelPercent);
      _sessionCharging = isCharging;
      _sessionStartLevel = levelPercent;
      _sessionChargedMah = 0;
      _sessionDischargedMah = 0;
      return;
    }

    _commitSessionEstimate(levelPercent);
  }

  void _commitSessionEstimate(int currentLevel) {
    if (_sessionStartLevel == null || _sessionCharging == null) {
      return;
    }

    final int deltaPercent = (currentLevel - _sessionStartLevel!).abs();
    if (deltaPercent < 3) {
      return;
    }

    final double throughputMah =
        _sessionCharging! ? _sessionChargedMah : _sessionDischargedMah;
    if (throughputMah < 20) {
      return;
    }

    final double estimate = throughputMah * 100.0 / deltaPercent;
    _pushCapacitySample(estimate);

    _sessionStartLevel = currentLevel;
    _sessionChargedMah = 0;
    _sessionDischargedMah = 0;
  }

  void _pushCapacitySample(double estimateMah) {
    final double minEstimate = max(700, _designCapacityMah * 0.45);
    final double maxEstimate = _designCapacityMah * 1.6;

    if (estimateMah < minEstimate || estimateMah > maxEstimate) {
      return;
    }

    _capacitySamples.add(estimateMah);
    if (_capacitySamples.length > _maxCapacitySamples) {
      _capacitySamples.removeAt(0);
    }

    double weightedSum = 0;
    double totalWeight = 0;
    for (int index = 0; index < _capacitySamples.length; index++) {
      final double weight = index + 1;
      weightedSum += _capacitySamples[index] * weight;
      totalWeight += weight;
    }

    _smoothedCapacityMah =
        totalWeight == 0 ? _designCapacityMah.toDouble() : weightedSum / totalWeight;
  }

  void _updateCycleCount(double throughputMah) {
    if (throughputMah <= 0) {
      return;
    }

    _throughputMahForCycle += throughputMah;
    while (_throughputMahForCycle >= _designCapacityMah) {
      _cycleCount += 1;
      _throughputMahForCycle -= _designCapacityMah;
      _addLog('Cycle count increased to $_cycleCount');
    }
  }

  double _calculateStressScore(
    double temperatureC,
    double voltageV,
    int currentMa,
    double measuredCapacityMah,
  ) {
    double score = 0;

    if (temperatureC > 38) {
      score += (temperatureC - 38) * 4;
    } else if (temperatureC < 5) {
      score += (5 - temperatureC) * 2;
    }

    if (voltageV > 4.25 || voltageV < 3.3) {
      score += 10;
    }

    if (measuredCapacityMah > 0) {
      final double cRate = currentMa.abs() / measuredCapacityMah;
      if (cRate > 0.8) {
        score += (cRate - 0.8) * 35;
      }
    }

    return score.clamp(0, 100).toDouble();
  }

  double _calculateHealthPercentage(
    int healthStatus,
    double measuredCapacityMah,
    double stressScore,
  ) {
    final double capacityHealth =
        (measuredCapacityMah / _designCapacityMah) * 100.0;

    final double statusPenalty = switch (healthStatus) {
      2 => 0, // good
      3 => 18, // overheat
      4 => 45, // dead
      5 => 20, // over voltage
      6 => 28, // unspecified failure
      7 => 12, // cold
      _ => 8,
    };

    final double stressPenalty = stressScore * 0.22;
    final double health = capacityHealth - statusPenalty - stressPenalty;
    return health.clamp(0, 100).toDouble();
  }

  String _getHealthString(int status, double healthPercentage) {
    if (status == 3) {
      return 'Overheat';
    }
    if (status == 4) {
      return 'Dead';
    }
    if (status == 5) {
      return 'Over voltage';
    }
    if (status == 6) {
      return 'Failure';
    }
    if (status == 7) {
      return 'Cold';
    }

    if (healthPercentage >= 90) {
      return 'Excellent';
    }
    if (healthPercentage >= 80) {
      return 'Good';
    }
    if (healthPercentage >= 70) {
      return 'Fair';
    }
    if (healthPercentage >= 55) {
      return 'Aging';
    }
    return 'Weak';
  }

  void _addToHistory(BatteryData data) {
    final BatteryHistory entry = BatteryHistory(
      current: data.current,
      level: data.level,
      isCharging: data.isCharging,
      timestamp: data.timestamp,
    );

    _history.add(entry);
    if (_history.length > _maxHistory) {
      _history.removeAt(0);
    }
    _historyController.add(List<BatteryHistory>.from(_history));
  }

  void _addLog(String message) {
    final DateTime now = DateTime.now();
    final String timestamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    _logs.insert(0, '$timestamp  $message');
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }
    _logController.add(List<String>.from(_logs));
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  double _toDouble(dynamic value, {required double fallback}) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  void clearData() {
    _history.clear();
    _historyController.add(const <BatteryHistory>[]);

    _logs.clear();
    _addLog('History and counters cleared');

    _lastSampleTime = null;
    _phaseStartTime = null;
    _activePhaseCharging = null;
    _totalChargingTime = Duration.zero;
    _totalDischargingTime = Duration.zero;


    _smoothedCapacityMah = _designCapacityMah.toDouble();
    _capacitySamples.clear();
    _cycleCount = 0;
    _throughputMahForCycle = 0;
    _chargedSinceStartMah = 0;
    _dischargedSinceStartMah = 0;

    _sessionCharging = null;
    _sessionStartLevel = null;
    _sessionChargedMah = 0;
    _sessionDischargedMah = 0;
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _eventSubscription?.cancel();
    _batteryDataController.close();
    _historyController.close();
    _logController.close();
  }
}
