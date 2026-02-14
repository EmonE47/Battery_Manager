import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/battery_data.dart';
import '../models/battery_history.dart';

class RealBatteryService {
  static const MethodChannel _platform =
      MethodChannel('com.example.battery_analyzer/battery');
  static const EventChannel _eventChannel =
      EventChannel('com.example.battery_analyzer/battery_events');

  static const String _manualCapacityKey = 'manual_design_capacity_mah';
  static const String _capacitySamplesKey = 'capacity_samples_mah_v1';

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
  final int _maxCapacitySamples = 40;

  final List<BatteryHistory> _history = <BatteryHistory>[];
  final List<String> _logs = <String>[];
  final List<double> _capacitySamples = <double>[];

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _monitoringTimer;
  Future<void>? _preferencesReady;
  SharedPreferences? _prefs;

  DateTime? _lastSampleTime;
  DateTime? _phaseStartTime;
  bool? _activePhaseCharging;

  Duration _totalChargingTime = Duration.zero;
  Duration _totalDischargingTime = Duration.zero;

  int _detectedDesignCapacityMah = 4000;
  int? _manualDesignCapacityMah;
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
  double? _lastChargeCounterMah;

  double _ewmaTemperatureC = 25;
  double _ewmaVoltageV = 3.85;
  double _ewmaCurrentMa = 0;
  double _thermalExposureScore = 0;
  double _highVoltageExposureScore = 0;
  double _highCRateExposureScore = 0;
  double _smoothedHealthPercentage = 90;

  String _manufacturer = 'Unknown';
  String _brand = 'Unknown';
  String _model = 'Unknown';
  String _device = 'Unknown';
  bool _loggedDeviceInfo = false;

  int get _activeDesignCapacityMah =>
      _manualDesignCapacityMah ?? _detectedDesignCapacityMah;

  RealBatteryService() {
    _preferencesReady = _loadPreferences();
    _initializeData();
  }

  Future<void> _loadPreferences() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      final int? manual = prefs.getInt(_manualCapacityKey);
      if (manual != null && manual >= 800 && manual <= 15000) {
        _manualDesignCapacityMah = manual;
        _addLog('Manual design capacity loaded: $_manualDesignCapacityMah mAh');
      }

      final List<String>? rawSamples = prefs.getStringList(_capacitySamplesKey);
      if (rawSamples != null && rawSamples.isNotEmpty) {
        _capacitySamples
          ..clear()
          ..addAll(
            rawSamples
                .map(double.tryParse)
                .whereType<double>()
                .where((double value) => value >= 650 && value <= 30000)
                .take(_maxCapacitySamples),
          );
      }

      if (_capacitySamples.isEmpty) {
        _smoothedCapacityMah = _activeDesignCapacityMah.toDouble();
      } else {
        _recomputeSmoothedCapacity();
        _addLog('Loaded ${_capacitySamples.length} saved capacity samples');
      }
    } catch (error) {
      _addLog('Could not load preferences: $error');
    }
  }

  Future<void> setManualDesignCapacity(int? capacityMah) async {
    await _preferencesReady;

    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;

    if (capacityMah == null) {
      await prefs.remove(_manualCapacityKey);
      _manualDesignCapacityMah = null;
      _addLog('Manual design capacity cleared. Using auto-detected capacity.');
    } else {
      final int sanitized = capacityMah.clamp(800, 15000);
      await prefs.setInt(_manualCapacityKey, sanitized);
      _manualDesignCapacityMah = sanitized;
      _addLog('Manual design capacity set to $sanitized mAh');
    }

    if (_capacitySamples.isEmpty) {
      _smoothedCapacityMah = _activeDesignCapacityMah.toDouble();
    }

    await _fetchBatteryData();
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
    _addLog('Collecting samples for precision calibration');

    final BatteryData initialData = BatteryData.empty();
    _batteryDataController.add(initialData);
    _historyController.add(const <BatteryHistory>[]);
    _logController.add(List<String>.from(_logs));
  }

  Future<void> startMonitoring() async {
    await _preferencesReady;

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
    final String technology = _cleanString(data['technology']);

    _manufacturer = _cleanString(data['manufacturer']);
    _brand = _cleanString(data['brand']);
    _model = _cleanString(data['model']);
    _device = _cleanString(data['device']);

    if (!_loggedDeviceInfo && _model != 'Unknown') {
      _addLog('Device detected: $_manufacturer $_model ($_device)');
      _loggedDeviceInfo = true;
    }

    final int currentMicroA = _toInt(data['current'], fallback: 0);
    final int currentMa = currentMicroA ~/ 1000;

    final int levelPercent =
        scale > 0 ? ((levelRaw * 100) / scale).round().clamp(0, 100) : 0;

    _tryUpdateDetectedDesignCapacity(data, levelPercent);
    final int designCapacityMah = _activeDesignCapacityMah;
    final double? chargeCounterMah = _parseChargeCounterMah(data['chargeCounter']);

    final bool isCharging = isPlugged || status == 2 || status == 5;

    _updatePhaseDurations(now, isCharging);

    final double elapsedSeconds = _resolveElapsedSeconds(now);
    final double currentMagnitudeMah =
        (currentMa.abs() * elapsedSeconds) / 3600.0;
    final double throughputMah = _integrateCharge(
      currentMagnitudeMah,
      isCharging,
      levelPercent,
      chargeCounterMah,
      elapsedSeconds,
    );
    _updateCycleCount(throughputMah, designCapacityMah);

    final double measuredCapacityMah = _smoothedCapacityMah <= 0
        ? designCapacityMah.toDouble()
        : _smoothedCapacityMah;

    _updateSignalAverages(temperatureC, voltageV, currentMa, elapsedSeconds);
    _updateStressExposure(
      elapsedSeconds,
      temperatureC,
      voltageV,
      currentMa,
      measuredCapacityMah,
    );

    final double chargingRate = currentMa > 0 ? currentMa.toDouble() : 0;
    final double dischargingRate =
        currentMa < 0 ? currentMa.abs().toDouble() : 0;
    final double powerMw = currentMa.abs() * voltageV;

    final double stressScore = _calculateStressScore(measuredCapacityMah);
    final double healthPercentage = _calculateHealthPercentage(
      healthStatus,
      measuredCapacityMah,
      designCapacityMah,
      stressScore,
    );
    final String health = _getHealthString(healthStatus, healthPercentage);

    final Duration chargingTime = _currentChargingDuration(now, isCharging);
    final Duration dischargingTime =
        _currentDischargingDuration(now, isCharging);

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
      designCapacity: designCapacityMah,
      chargedSinceStart: _chargedSinceStartMah,
      dischargedSinceStart: _dischargedSinceStartMah,
      netMahSinceStart: _chargedSinceStartMah - _dischargedSinceStartMah,
      averagePowerMw: powerMw,
      stressScore: stressScore,
      projectedTimeToFullHours: projectedTimeToFullHours,
      projectedTimeToEmptyHours: projectedTimeToEmptyHours,
      manufacturer: _manufacturer,
      brand: _brand,
      model: _model,
      device: _device,
      isDesignCapacityManual: _manualDesignCapacityMah != null,
      manualDesignCapacity: _manualDesignCapacityMah,
    );

    _batteryDataController.add(batteryData);
    _addToHistory(batteryData);

    _lastSampleTime = now;
  }

  void _tryUpdateDetectedDesignCapacity(
    Map<String, dynamic> data,
    int levelPercent,
  ) {
    final int? fromDesign = _parseCapacityField(data['designCapacity']);
    final int? fromFull = _parseCapacityField(data['fullChargeCapacity']);
    final int? fromCounter = _parseChargeCounter(data['chargeCounter']);
    final int? fromCounterAndSoc = _estimateFromChargeCounterAndSoc(
      data['chargeCounter'],
      levelPercent,
    );
    final int? fromEnergyAndSoc = _estimateFromEnergyAndSoc(
      data['remainingCapacityFromEnergy'],
      levelPercent,
    );

    final int? candidate = fromDesign ??
        fromFull ??
        fromCounterAndSoc ??
        fromCounter ??
        fromEnergyAndSoc;

    if (candidate != null && candidate >= 1000 && candidate <= 30000) {
      if (!_capacityReceivedFromDevice ||
          candidate != _detectedDesignCapacityMah) {
        _detectedDesignCapacityMah = candidate;
        _capacityReceivedFromDevice = true;
        if (_capacitySamples.isEmpty && _manualDesignCapacityMah == null) {
          _smoothedCapacityMah = candidate.toDouble();
        }
        _addLog(
            'Auto design capacity detected: $_detectedDesignCapacityMah mAh');
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
    if (parsed > 30000) {
      final int asMah = parsed ~/ 1000;
      if (asMah > 1000 && asMah < 30000) {
        return asMah;
      }
    }
    if (parsed > 1000 && parsed < 30000) {
      return parsed;
    }
    return null;
  }

  int? _estimateFromChargeCounterAndSoc(dynamic rawChargeCounter, int soc) {
    final double? remainingMah = _parseChargeCounterMah(rawChargeCounter);
    if (remainingMah == null || soc <= 0 || soc > 100) {
      return null;
    }
    final double estimate = remainingMah / (soc / 100.0);
    if (estimate > 800 && estimate < 30000) {
      return estimate.round();
    }
    return null;
  }

  int? _estimateFromEnergyAndSoc(dynamic rawRemainingFromEnergy, int soc) {
    final int remainingMah = _toInt(rawRemainingFromEnergy, fallback: 0);
    if (remainingMah <= 0 || soc <= 0 || soc > 100) {
      return null;
    }
    final double estimate = remainingMah / (soc / 100.0);
    if (estimate > 800 && estimate < 30000) {
      return estimate.round();
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
      _addLog(
          'Discharging phase ended after ${_formatDuration(phaseDuration)}');
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

  double _integrateCharge(
    double currentMagnitudeMah,
    bool isCharging,
    int levelPercent,
    double? chargeCounterMah,
    double elapsedSeconds,
  ) {
    final double? counterDeltaMah =
        _consumeChargeCounterDelta(chargeCounterMah, elapsedSeconds);
    final bool counterMatchesDirection = counterDeltaMah != null &&
        ((isCharging && counterDeltaMah >= 0) ||
            (!isCharging && counterDeltaMah <= 0));

    final double throughputMah = counterMatchesDirection
        ? counterDeltaMah.abs()
        : currentMagnitudeMah;
    final double signedDeltaMah = isCharging ? throughputMah : -throughputMah;

    if (signedDeltaMah > 0) {
      _chargedSinceStartMah += signedDeltaMah;
      if (_sessionCharging == true) {
        _sessionChargedMah += signedDeltaMah;
      }
    } else if (signedDeltaMah < 0) {
      final double discharge = signedDeltaMah.abs();
      _dischargedSinceStartMah += discharge;
      if (_sessionCharging == false) {
        _sessionDischargedMah += discharge;
      }
    }

    if (_sessionCharging == null || _sessionStartLevel == null) {
      _sessionCharging = isCharging;
      _sessionStartLevel = levelPercent;
      return throughputMah;
    }

    if (_sessionCharging != isCharging) {
      _commitSessionEstimate(levelPercent);
      _sessionCharging = isCharging;
      _sessionStartLevel = levelPercent;
      _sessionChargedMah = 0;
      _sessionDischargedMah = 0;
      return throughputMah;
    }

    _commitSessionEstimate(levelPercent);
    return throughputMah;
  }

  double? _parseChargeCounterMah(dynamic rawValue) {
    final int parsed = _toInt(rawValue, fallback: 0);
    if (parsed <= 0) {
      return null;
    }
    if (parsed > 30000) {
      final double asMah = parsed / 1000.0;
      if (asMah > 800 && asMah < 30000) {
        return asMah;
      }
      return null;
    }
    if (parsed > 800 && parsed < 30000) {
      return parsed.toDouble();
    }
    return null;
  }

  double? _consumeChargeCounterDelta(
    double? chargeCounterMah,
    double elapsedSeconds,
  ) {
    if (chargeCounterMah == null) {
      return null;
    }

    if (_lastChargeCounterMah == null) {
      _lastChargeCounterMah = chargeCounterMah;
      return null;
    }

    final double deltaMah = chargeCounterMah - _lastChargeCounterMah!;
    _lastChargeCounterMah = chargeCounterMah;

    if (!deltaMah.isFinite || deltaMah == 0) {
      return null;
    }

    final double normalizedSeconds = elapsedSeconds <= 0 ? 1.0 : elapsedSeconds;
    final double maxReasonableDelta = max(
      0.6,
      (_activeDesignCapacityMah * 6.0) * (normalizedSeconds / 3600.0),
    );

    if (deltaMah.abs() > maxReasonableDelta) {
      return null;
    }

    return deltaMah;
  }

  void _commitSessionEstimate(int currentLevel) {
    if (_sessionStartLevel == null || _sessionCharging == null) {
      return;
    }

    final int deltaPercent = (currentLevel - _sessionStartLevel!).abs();
    if (deltaPercent < 2) {
      return;
    }

    final double throughputMah =
        _sessionCharging! ? _sessionChargedMah : _sessionDischargedMah;
    if (throughputMah < 15) {
      return;
    }

    final double estimate = throughputMah * 100.0 / deltaPercent;
    _pushCapacitySample(estimate);

    _sessionStartLevel = currentLevel;
    _sessionChargedMah = 0;
    _sessionDischargedMah = 0;
  }

  void _pushCapacitySample(double estimateMah) {
    final int effectiveDesignMah = _activeDesignCapacityMah;
    final double minEstimate = max(650, effectiveDesignMah * 0.45);
    final double maxEstimate = effectiveDesignMah * 1.7;

    if (estimateMah < minEstimate || estimateMah > maxEstimate) {
      return;
    }

    _capacitySamples.add(estimateMah);
    if (_capacitySamples.length > _maxCapacitySamples) {
      _capacitySamples.removeAt(0);
    }

    _recomputeSmoothedCapacity();
    _persistCapacitySamples();
  }

  void _recomputeSmoothedCapacity() {
    if (_capacitySamples.isEmpty) {
      _smoothedCapacityMah = _activeDesignCapacityMah.toDouble();
      return;
    }

    double weightedSum = 0;
    double totalWeight = 0;
    for (int index = 0; index < _capacitySamples.length; index++) {
      final double weight = 1 + (index / _capacitySamples.length) * 2;
      weightedSum += _capacitySamples[index] * weight;
      totalWeight += weight;
    }

    _smoothedCapacityMah = totalWeight == 0
        ? _activeDesignCapacityMah.toDouble()
        : weightedSum / totalWeight;
  }

  void _persistCapacitySamples() {
    Future<void>(() async {
      final SharedPreferences prefs =
          _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final List<String> serialized = _capacitySamples
          .map((double value) => value.toStringAsFixed(2))
          .toList(growable: false);
      await prefs.setStringList(_capacitySamplesKey, serialized);
    }).catchError((_) {});
  }

  void _updateCycleCount(double throughputMah, int designCapacityMah) {
    if (throughputMah <= 0 || designCapacityMah <= 0) {
      return;
    }

    _throughputMahForCycle += throughputMah;
    while (_throughputMahForCycle >= designCapacityMah) {
      _cycleCount += 1;
      _throughputMahForCycle -= designCapacityMah;
      _addLog('Cycle count increased to $_cycleCount');
    }
  }

  void _updateSignalAverages(
    double temperatureC,
    double voltageV,
    int currentMa,
    double elapsedSeconds,
  ) {
    final double alpha = (elapsedSeconds / 15).clamp(0.05, 0.4);
    _ewmaTemperatureC += (temperatureC - _ewmaTemperatureC) * alpha;
    _ewmaVoltageV += (voltageV - _ewmaVoltageV) * alpha;
    _ewmaCurrentMa += (currentMa.toDouble() - _ewmaCurrentMa) * alpha;
  }

  void _updateStressExposure(
    double elapsedSeconds,
    double temperatureC,
    double voltageV,
    int currentMa,
    double measuredCapacityMah,
  ) {
    final double hours = elapsedSeconds / 3600.0;
    final double cRate =
        measuredCapacityMah > 0 ? currentMa.abs() / measuredCapacityMah : 0;

    final double thermalInstant = max(0.0, temperatureC - 35.0) / 10.0;
    final double voltageInstant = max(0.0, voltageV - 4.15) * 6.0;
    final double cRateInstant = max(0.0, cRate - 0.8) * 2.0;

    _thermalExposureScore =
        (_thermalExposureScore * 0.999) + thermalInstant * hours * 100;
    _highVoltageExposureScore =
        (_highVoltageExposureScore * 0.999) + voltageInstant * hours * 100;
    _highCRateExposureScore =
        (_highCRateExposureScore * 0.999) + cRateInstant * hours * 100;
  }

  double _calculateStressScore(double measuredCapacityMah) {
    final double cRate = measuredCapacityMah > 0
        ? _ewmaCurrentMa.abs() / measuredCapacityMah
        : 0;

    final double thermalInstant = _ewmaTemperatureC <= 35
        ? 0
        : pow(_ewmaTemperatureC - 35, 1.35).toDouble() * 1.4;
    final double voltageInstant = _ewmaVoltageV > 4.2
        ? (_ewmaVoltageV - 4.2) * 220
        : (_ewmaVoltageV < 3.35 ? (3.35 - _ewmaVoltageV) * 100 : 0);
    final double cRateInstant = cRate > 0.8 ? (cRate - 0.8) * 35 : 0;

    final double exposurePenalty = (_thermalExposureScore * 0.06) +
        (_highVoltageExposureScore * 0.08) +
        (_highCRateExposureScore * 0.09);

    return (thermalInstant + voltageInstant + cRateInstant + exposurePenalty)
        .clamp(0, 100)
        .toDouble();
  }

  double _calculateHealthPercentage(
    int healthStatus,
    double measuredCapacityMah,
    int designCapacityMah,
    double stressScore,
  ) {
    final double capacityHealth = designCapacityMah <= 0
        ? 0
        : (measuredCapacityMah / designCapacityMah) * 100.0;

    final double statusPenalty = switch (healthStatus) {
      2 => 0, // good
      3 => 12, // overheat
      4 => 40, // dead
      5 => 16, // over voltage
      6 => 24, // unspecified failure
      7 => 10, // cold
      _ => 6,
    };

    final double cyclePenalty = min(22.0, _cycleCount * 0.018);
    final double exposurePenalty = min(
      16.0,
      (_thermalExposureScore * 0.03) +
          (_highVoltageExposureScore * 0.05) +
          (_highCRateExposureScore * 0.05),
    );
    final double stressPenalty = stressScore * 0.16;

    final double rawHealth = capacityHealth -
        statusPenalty -
        cyclePenalty -
        exposurePenalty -
        stressPenalty;

    _smoothedHealthPercentage += (rawHealth - _smoothedHealthPercentage) * 0.12;
    return _smoothedHealthPercentage.clamp(0, 100).toDouble();
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

    if (healthPercentage >= 92) {
      return 'Excellent';
    }
    if (healthPercentage >= 84) {
      return 'Good';
    }
    if (healthPercentage >= 74) {
      return 'Fair';
    }
    if (healthPercentage >= 60) {
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

  String _cleanString(dynamic value) {
    if (value == null) {
      return 'Unknown';
    }
    final String text = value.toString().trim();
    if (text.isEmpty) {
      return 'Unknown';
    }
    return text;
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

    _smoothedCapacityMah = _activeDesignCapacityMah.toDouble();
    _capacitySamples.clear();
    _cycleCount = 0;
    _throughputMahForCycle = 0;
    _chargedSinceStartMah = 0;
    _dischargedSinceStartMah = 0;

    _sessionCharging = null;
    _sessionStartLevel = null;
    _sessionChargedMah = 0;
    _sessionDischargedMah = 0;
    _lastChargeCounterMah = null;

    _ewmaTemperatureC = 25;
    _ewmaVoltageV = 3.85;
    _ewmaCurrentMa = 0;
    _thermalExposureScore = 0;
    _highVoltageExposureScore = 0;
    _highCRateExposureScore = 0;
    _smoothedHealthPercentage = 90;

    Future<void>(() async {
      final SharedPreferences prefs =
          _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.remove(_capacitySamplesKey);
    }).catchError((_) {});
  }

  void dispose() {
    _monitoringTimer?.cancel();
    _eventSubscription?.cancel();
    _batteryDataController.close();
    _historyController.close();
    _logController.close();
  }
}
