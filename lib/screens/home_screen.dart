import 'dart:math';

import 'package:flutter/material.dart';

import '../models/battery_data.dart';
import '../models/battery_history.dart';
import '../utils/real_battery_service.dart';
import '../widgets/history_panel.dart';
import '../widgets/log_panel.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_indicator.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final RealBatteryService _batteryService = RealBatteryService();

  late final TabController _tabController;

  BatteryData _batteryData = BatteryData.empty();
  List<BatteryHistory> _history = <BatteryHistory>[];
  List<String> _logs = <String>[];
  bool _isMonitoring = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _setupListeners();
    _bootstrapMonitoring();
  }

  Future<void> _bootstrapMonitoring() async {
    final bool backgroundRunning =
        await _batteryService.isBackgroundServiceRunning();
    if (backgroundRunning) {
      setState(() => _isMonitoring = true);
    }

    await _startMonitoring();
  }

  void _setupListeners() {
    _batteryService.batteryDataStream.listen((BatteryData data) {
      if (!mounted) return;
      setState(() => _batteryData = data);
    });

    _batteryService.historyStream.listen((List<BatteryHistory> entries) {
      if (!mounted) return;
      setState(() => _history = entries);
    });

    _batteryService.logStream.listen((List<String> entries) {
      if (!mounted) return;
      setState(() => _logs = entries);
    });
  }

  Future<void> _startMonitoring() async {
    await _batteryService.startMonitoring();
    if (!mounted) return;
    setState(() => _isMonitoring = true);
  }

  Future<void> _stopMonitoring() async {
    await _batteryService.stopMonitoring();
    if (!mounted) return;
    setState(() => _isMonitoring = false);
  }

  void _clearData() {
    _batteryService.clearData();
  }

  Future<void> _showThemePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.brightness_auto),
                title: const Text('System theme'),
                trailing: widget.themeMode == ThemeMode.system
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  widget.onThemeModeChanged(ThemeMode.system);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: const Text('Light theme'),
                trailing: widget.themeMode == ThemeMode.light
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  widget.onThemeModeChanged(ThemeMode.light);
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark theme'),
                trailing: widget.themeMode == ThemeMode.dark
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  widget.onThemeModeChanged(ThemeMode.dark);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _batteryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Analyzer'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Theme',
            onPressed: _showThemePicker,
            icon: const Icon(Icons.palette_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
              label: Text(_isMonitoring ? 'Stop' : 'Start'),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              isDark
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.34)
                  : colors.primaryContainer.withValues(alpha: 0.44),
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _InfoPill(
                          label: 'Current',
                          value: _formatSignedCurrent(_batteryData.current),
                          icon: _batteryData.current >= 0
                              ? Icons.north_east
                              : Icons.south_east,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoPill(
                          label: 'Level',
                          value: '${_batteryData.level}%',
                          icon: Icons.battery_std_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoPill(
                          label: 'Capacity',
                          value: '${_batteryData.actualCapacity.toInt()} mAh',
                          icon: Icons.battery_full,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    tabs: const <Tab>[
                      Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
                      Tab(text: 'Health', icon: Icon(Icons.favorite)),
                      Tab(text: 'History', icon: Icon(Icons.show_chart)),
                      Tab(text: 'Logs', icon: Icon(Icons.terminal)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _buildOverviewTab(),
                  _buildHealthTab(),
                  _buildHistoryTab(),
                  _buildLogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _startMonitoring,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: <Widget>[
          _HeroBatteryCard(
            level: _batteryData.level,
            isCharging: _batteryData.isCharging,
            current: _batteryData.current,
            health: _batteryData.health,
            voltage: _batteryData.voltage,
            temperature: _batteryData.temperature,
            timeToFullHours: _batteryData.projectedTimeToFullHours,
            timeToEmptyHours: _batteryData.projectedTimeToEmptyHours,
          ),
          const SizedBox(height: 14),
          StatusIndicator(
            isCharging: _batteryData.isCharging,
            health: _batteryData.health,
            current: _batteryData.current,
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 1.03,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: <Widget>[
              StatCard(
                icon: Icons.thermostat,
                title: 'Temp',
                value: '${_batteryData.temperature.toStringAsFixed(1)} C',
                color: _temperatureColor(_batteryData.temperature),
              ),
              StatCard(
                icon: Icons.bolt,
                title: 'Voltage',
                value: '${_batteryData.voltage.toStringAsFixed(2)} V',
                color: Colors.amber,
              ),
              StatCard(
                icon: Icons.flash_on,
                title: 'Power',
                value: '${_batteryData.averagePowerMw.toStringAsFixed(0)} mW',
                color: Colors.deepOrange,
              ),
              StatCard(
                icon: Icons.update,
                title: 'Cycles',
                value: _batteryData.cycleCount.toString(),
                color: Colors.blue,
              ),
              StatCard(
                icon: Icons.timelapse,
                title: 'Charging',
                value: _formatDuration(_batteryData.chargingTime),
                color: Colors.green,
              ),
              StatCard(
                icon: Icons.timelapse_outlined,
                title: 'Discharge',
                value: _formatDuration(_batteryData.dischargingTime),
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Throughput counters',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _kvRow('Charged since start',
                      '${_batteryData.chargedSinceStart.toStringAsFixed(1)} mAh'),
                  _kvRow(
                    'Discharged since start',
                    '${_batteryData.dischargedSinceStart.toStringAsFixed(1)} mAh',
                  ),
                  _kvRow(
                    'Net battery flow',
                    '${_batteryData.netMahSinceStart.toStringAsFixed(1)} mAh',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _clearData,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Reset samples'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHealthTab() {
    final double capacityPercent = _batteryData.designCapacity <= 0
        ? 0
        : (_batteryData.actualCapacity / _batteryData.designCapacity) * 100;
    final double health = _batteryData.healthPercentage.clamp(0, 100);
    final double stress = _batteryData.stressScore.clamp(0, 100);
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _startMonitoring,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Measured battery health',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: health / 100),
                    duration: const Duration(milliseconds: 550),
                    builder: (BuildContext context, double value, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 14,
                          value: value,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _kvRow('Health score', '${health.toStringAsFixed(1)}%'),
                  _kvRow(
                    'Measured full capacity',
                    '${_batteryData.actualCapacity.toStringAsFixed(0)} mAh',
                  ),
                  _kvRow(
                    'Design capacity',
                    '${_batteryData.designCapacity} mAh',
                  ),
                  _kvRow(
                    'Capacity ratio',
                    '${capacityPercent.toStringAsFixed(1)}%',
                  ),
                  _kvRow(
                    'Estimated remaining now',
                    '${_batteryData.capacity} mAh',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Stress and wear', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: stress / 100),
                    duration: const Duration(milliseconds: 550),
                    builder: (BuildContext context, double value, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          minHeight: 12,
                          value: value,
                          color: _stressColor(stress),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _kvRow('Stress score', '${stress.toStringAsFixed(1)}/100'),
                  _kvRow(
                    'Charge rate',
                    '${_batteryData.chargingRate.toStringAsFixed(0)} mA',
                  ),
                  _kvRow(
                    'Discharge rate',
                    '${_batteryData.dischargingRate.toStringAsFixed(0)} mA',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _healthAdvice(_batteryData),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('AccuBattery-style estimates',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _kvRow('Predicted time to full',
                      _formatHours(_batteryData.projectedTimeToFullHours)),
                  _kvRow('Predicted time to empty',
                      _formatHours(_batteryData.projectedTimeToEmptyHours)),
                  _kvRow(
                    'Charge throughput',
                    '${_batteryData.chargedSinceStart.toStringAsFixed(1)} mAh',
                  ),
                  _kvRow(
                    'Discharge throughput',
                    '${_batteryData.dischargedSinceStart.toStringAsFixed(1)} mAh',
                  ),
                  _kvRow(
                    'Equivalent cycles',
                    _batteryData.cycleCount.toString(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final int records = _history.length;
    final int chargingRecords = _history.where((BatteryHistory e) => e.isCharging).length;
    final int dischargingRecords = records - chargingRecords;
    final double avgLevel = records == 0
        ? 0
        : _history.map((BatteryHistory e) => e.level).reduce((int a, int b) => a + b) /
            records;

    final List<int> recentCurrents = _history
        .reversed
        .take(40)
        .map((BatteryHistory e) => e.current.abs())
        .toList();
    final double avgCurrent = recentCurrents.isEmpty
        ? 0
        : recentCurrents.reduce((int a, int b) => a + b) / recentCurrents.length;

    return RefreshIndicator(
      onRefresh: _startMonitoring,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: <Widget>[
          HistoryPanel(history: _history),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Trend summary',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  _kvRow('Records', '$records'),
                  _kvRow('Charging records', '$chargingRecords'),
                  _kvRow('Discharging records', '$dischargingRecords'),
                  _kvRow('Average level', '${avgLevel.toStringAsFixed(1)}%'),
                  _kvRow('Average absolute current',
                      '${avgCurrent.toStringAsFixed(0)} mA'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    return RefreshIndicator(
      onRefresh: _startMonitoring,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: <Widget>[
          LogPanel(logs: _logs),
        ],
      ),
    );
  }

  Widget _kvRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              key,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Color _temperatureColor(double temp) {
    if (temp <= 10) return Colors.lightBlue;
    if (temp <= 35) return Colors.green;
    if (temp <= 42) return Colors.orange;
    return Colors.red;
  }

  Color _stressColor(double stress) {
    if (stress < 25) return Colors.green;
    if (stress < 55) return Colors.orange;
    return Colors.red;
  }

  String _formatSignedCurrent(int current) {
    if (current > 0) {
      return '+$current mA';
    }
    if (current < 0) {
      return '$current mA';
    }
    return '0 mA';
  }

  String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${duration.inMinutes}m';
  }

  String _formatHours(double hours) {
    if (hours <= 0 || hours.isNaN || hours.isInfinite) {
      return 'N/A';
    }
    final int totalMinutes = (hours * 60).round();
    final int h = totalMinutes ~/ 60;
    final int m = totalMinutes % 60;
    return '${h}h ${m}m';
  }

  String _healthAdvice(BatteryData data) {
    final double stress = data.stressScore;
    if (stress > 65) {
      return 'High stress detected. Reduce heat and avoid sustained heavy load while charging.';
    }
    if (data.temperature > 42) {
      return 'Battery temperature is high. Remove case or reduce fast charging sessions.';
    }
    if (data.healthPercentage < 75) {
      return 'Health is below 75%. Avoid deep discharge and keep charge between 20% and 80% when possible.';
    }
    return 'Battery conditions are stable. Continue tracking more full sessions for better calibration.';
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 1),
                Text(value, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroBatteryCard extends StatelessWidget {
  final int level;
  final bool isCharging;
  final int current;
  final String health;
  final double voltage;
  final double temperature;
  final double timeToFullHours;
  final double timeToEmptyHours;

  const _HeroBatteryCard({
    required this.level,
    required this.isCharging,
    required this.current,
    required this.health,
    required this.voltage,
    required this.temperature,
    required this.timeToFullHours,
    required this.timeToEmptyHours,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final double progress = (level / 100).clamp(0, 1);
    final Color fill = Color.lerp(Colors.red, Colors.green, progress)!;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.primaryContainer.withValues(alpha: 0.7),
              colors.surfaceContainerHigh,
            ],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    isCharging ? 'Charging now' : 'Discharging now',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    isCharging ? Icons.bolt : Icons.power,
                    size: 18,
                  ),
                  label: Text(health),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 110,
                  height: 110,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 500),
                    builder: (BuildContext context, double value, _) {
                      return Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          CircularProgressIndicator(
                            value: 1,
                            strokeWidth: 9,
                            color: colors.surfaceContainerHighest,
                          ),
                          CircularProgressIndicator(
                            value: value,
                            strokeWidth: 9,
                            color: fill,
                          ),
                          Center(
                            child: Text(
                              '$level%',
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: <Widget>[
                      _inlineMetric('Current', _currentLabel(current)),
                      const SizedBox(height: 10),
                      _inlineMetric('Voltage', '${voltage.toStringAsFixed(2)} V'),
                      const SizedBox(height: 10),
                      _inlineMetric(
                        'Temperature',
                        '${temperature.toStringAsFixed(1)} C',
                      ),
                      const SizedBox(height: 10),
                      _inlineMetric(
                        isCharging ? 'To full' : 'To empty',
                        isCharging
                            ? _formatHours(timeToFullHours)
                            : _formatHours(timeToEmptyHours),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineMetric(String label, String value) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  static String _currentLabel(int current) {
    if (current > 0) return '+$current mA';
    if (current < 0) return '$current mA';
    return '0 mA';
  }

  static String _formatHours(double hours) {
    if (hours <= 0 || hours.isInfinite || hours.isNaN) {
      return 'N/A';
    }
    final int minutes = max(1, (hours * 60).round());
    return '${minutes ~/ 60}h ${minutes % 60}m';
  }
}
