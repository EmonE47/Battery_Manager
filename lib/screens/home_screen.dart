import 'package:flutter/material.dart';
import 'package:battery_analyzer/utils/real_battery_service.dart';
import 'package:battery_analyzer/widgets/battery_card.dart';
import 'package:battery_analyzer/widgets/stat_card.dart';
import 'package:battery_analyzer/widgets/status_indicator.dart';
import 'package:battery_analyzer/widgets/history_panel.dart';
import 'package:battery_analyzer/widgets/log_panel.dart';
import '../models/battery_data.dart';
import '../models/battery_history.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final RealBatteryService _batteryService = RealBatteryService();
  bool _isMonitoring = false;
  BatteryData _batteryData = BatteryData.empty();
  List<BatteryHistory> _history = [];
  List<String> _logs = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _setupListeners();
    _addInitialLogs();
  }

  void _setupListeners() {
    _batteryService.batteryDataStream.listen((data) {
      setState(() => _batteryData = data);
    });

    _batteryService.historyStream.listen((history) {
      setState(() => _history = history);
    });

    _batteryService.logStream.listen((logs) {
      setState(() => _logs = logs);
    });
  }

  void _addInitialLogs() {
    // Don't clear data on initialization - this preserves the initial log
    // Future.delayed(Duration.zero, () {
    //   _batteryService.clearData();
    // });
  }

  void _startMonitoring() {
    setState(() => _isMonitoring = true);
    _batteryService.startMonitoring();
  }

  void _stopMonitoring() {
    setState(() => _isMonitoring = false);
    _batteryService.stopMonitoring();
  }

  void _clearData() {
    _batteryService.clearData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _batteryService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Analyzer Pro'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'QUICK CHECK'),
            Tab(icon: Icon(Icons.favorite), text: 'HEALTH'),
            Tab(icon: Icon(Icons.show_chart), text: 'HISTORY'),
            Tab(icon: Icon(Icons.info), text: 'DEBUG'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: _isMonitoring ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                ),
                child: Text(
                  _isMonitoring ? '● MONITORING' : '○ IDLE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isMonitoring ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQuickCheckTab(),
          _buildHealthTab(),
          _buildHistoryTab(),
          _buildDebugTab(),
        ],
      ),
    );
  }

  // ===== QUICK CHECK TAB =====
  Widget _buildQuickCheckTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large Battery Health Status
          _buildHealthStatusCard(),
          const SizedBox(height: 20),

          // Current Battery Level with gauge
          _buildBatteryGaugeCard(),
          const SizedBox(height: 20),

          // Quick Status
          StatusIndicator(
            isCharging: _batteryData.isCharging,
            health: _batteryData.health,
            current: _batteryData.current,
          ),
          const SizedBox(height: 20),

          // Quick Stats Grid
          _buildQuickStatsGrid(),
          const SizedBox(height: 20),

          // Control Buttons
          _buildControlButtons(),
        ],
      ),
    );
  }

  // ===== HEALTH TAB =====
  Widget _buildHealthTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Health Score Card
          _buildDetailedHealthCard(),
          const SizedBox(height: 20),

          // Capacity Analysis
          _buildCapacityAnalysisCard(),
          const SizedBox(height: 20),

          // Temperature Analysis
          _buildTemperatureAnalysisCard(),
          const SizedBox(height: 20),

          // Degradation Info
          _buildDegradationCard(),
          const SizedBox(height: 20),

          // Charge Statistics
          _buildDetailedChargeStatsCard(),
        ],
      ),
    );
  }

  // ===== HISTORY TAB =====
  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BATTERY HISTORY',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          HistoryPanel(history: _history),
          const SizedBox(height: 20),
          // Add simple trend info
          _buildTrendSummary(),
        ],
      ),
    );
  }

  // ===== DEBUG TAB =====
  Widget _buildDebugTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LogPanel(logs: _logs),
        ],
      ),
    );
  }

  // ===== WIDGET BUILDERS =====

  Widget _buildHealthStatusCard() {
    double health = _batteryData.healthPercentage;
    Color healthColor = _getHealthColor(health);
    String healthStatus = _getHealthStatus(health);

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Large health percentage circle
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [healthColor, healthColor.withOpacity(0.5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${health.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'HEALTH',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              healthStatus,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: healthColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getHealthRecommendation(health),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryGaugeCard() {
    int level = _batteryData.level;
    Color levelColor = level > 50 ? Colors.green : (level > 20 ? Colors.orange : Colors.red);

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Level',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  '$level%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: levelColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: level / 100,
                minHeight: 16,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(levelColor),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Status: ${_batteryData.isCharging ? '🔌 Charging' : '⚡ Discharging'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _batteryData.isCharging ? Colors.green : Colors.orange,
                  ),
                ),
                if (_batteryData.isCharging && _batteryData.chargingRate > 0)
                  Text(
                    'Rate: ${_batteryData.chargingRate.toInt()} mA/h',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  )
                else if (!_batteryData.isCharging && _batteryData.dischargingRate > 0)
                  Text(
                    'Rate: ${_batteryData.dischargingRate.toInt()} mA/h',
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK STATS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          childAspectRatio: 1.0,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            StatCard(
              icon: Icons.thermostat,
              title: 'TEMP',
              value: '${_batteryData.temperature.toStringAsFixed(1)}°C',
              color: _getTempColor(_batteryData.temperature),
            ),
            StatCard(
              icon: Icons.bolt,
              title: 'VOLTAGE',
              value: '${_batteryData.voltage.toStringAsFixed(2)}V',
              color: Colors.purple,
            ),
            StatCard(
              icon: Icons.battery_charging_full,
              title: 'CAPACITY',
              value: '${_batteryData.actualCapacity.toInt()}mAh',
              color: Colors.amber,
            ),
            StatCard(
              icon: Icons.repeat,
              title: 'CYCLES',
              value: '${_batteryData.cycleCount}',
              color: Colors.blue,
            ),
            StatCard(
              icon: Icons.science,
              title: 'TECH',
              value: _batteryData.technology,
              color: Colors.pink,
            ),
            StatCard(
              icon: Icons.timer,
              title: 'USAGE',
              value: '${(_batteryData.chargingTime.inHours + _batteryData.dischargingTime.inHours)}h',
              color: Colors.cyan,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailedHealthCard() {
    double health = _batteryData.healthPercentage;
    double degradation = 100 - health;

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Battery Health Analysis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            // Health bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Overall Health', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${health.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getHealthColor(health),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: health / 100,
                    minHeight: 12,
                    backgroundColor: Colors.grey[700],
                    valueColor: AlwaysStoppedAnimation<Color>(_getHealthColor(health)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey[700]),
            const SizedBox(height: 16),
            // Health factors
            _buildHealthFactorRow('Temperature', _batteryData.temperature, '0-45°C', _getTempColor(_batteryData.temperature)),
            const SizedBox(height: 12),
            _buildHealthFactorRow('Voltage', _batteryData.voltage, '3.7-4.2V', _getVoltageColor(_batteryData.voltage)),
            const SizedBox(height: 12),
            _buildHealthFactorRow('Status', _batteryData.health == 'Good' ? 1.0 : 0.7, 'Status OK', _getStatusColor(_batteryData.health)),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthFactorRow(String label, double value, String range, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value is double ? (value / 100).clamp(0, 1) : value.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
        ),
        Text(
          range,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }

  Widget _buildCapacityAnalysisCard() {
    double designCapacity = 4000; // This should be from device
    double actualCapacity = _batteryData.actualCapacity;
    double capacityPercent = (actualCapacity / designCapacity * 100).clamp(0, 100);

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Capacity Analysis',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Design Capacity', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${designCapacity.toInt()} mAh',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Actual Capacity', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${actualCapacity.toInt()} mAh',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getCapacityColor(capacityPercent)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Capacity degradation
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: capacityPercent / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(_getCapacityColor(capacityPercent)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Capacity: ${capacityPercent.toStringAsFixed(1)}% of original',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemperatureAnalysisCard() {
    double temp = _batteryData.temperature;
    String tempStatus = _getTemperatureStatus(temp);

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Temperature Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${temp.toStringAsFixed(1)}°C',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _getTempColor(temp),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Status', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      tempStatus,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _getTempColor(temp),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Temperature range info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTempRangeItem('🟢 Optimal', '10-25°C'),
                  const SizedBox(height: 8),
                  _buildTempRangeItem('🟡 Normal', '25-45°C'),
                  const SizedBox(height: 8),
                  _buildTempRangeItem('🔴 Hot', '>45°C'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTempRangeItem(String label, String range) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(range, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildDegradationCard() {
    double health = _batteryData.healthPercentage;
    double degradation = 100 - health;
    int cycleCount = _batteryData.cycleCount;

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Degradation Report',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Degradation', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${degradation.toStringAsFixed(1)}%',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Cycles', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      cycleCount.toString(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyan),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              _getDegradationForecast(health, cycleCount),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedChargeStatsCard() {
    String timeToFull = 'N/A';
    if (_batteryData.isCharging && _batteryData.chargingRate > 0) {
      int remainingCapacity = _batteryData.actualCapacity.toInt() - 
          (_batteryData.level * _batteryData.actualCapacity.toInt() ~/ 100);
      int minutesToFull = (remainingCapacity / (_batteryData.chargingRate / 60)).toInt();
      timeToFull = '${(minutesToFull / 60).toStringAsFixed(1)}h ${minutesToFull % 60}m';
    }

    String timeToEmpty = 'N/A';
    if (!_batteryData.isCharging && _batteryData.dischargingRate > 0) {
      int capacityRemaining = (_batteryData.level * _batteryData.actualCapacity.toInt()) ~/ 100;
      int minutesToEmpty = (capacityRemaining / (_batteryData.dischargingRate / 60)).toInt();
      timeToEmpty = '${(minutesToEmpty / 60).toStringAsFixed(1)}h ${minutesToEmpty % 60}m';
    }

    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Charge Statistics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _buildStatCardDetailed(
                  'Charge Rate',
                  '${_batteryData.chargingRate.toInt()} mA/h',
                  Colors.green,
                  Icons.electric_bolt,
                ),
                _buildStatCardDetailed(
                  'Discharge Rate',
                  '${_batteryData.dischargingRate.toInt()} mA/h',
                  Colors.red,
                  Icons.power_off,
                ),
                _buildStatCardDetailed(
                  'Time to Full',
                  timeToFull,
                  Colors.blue,
                  Icons.timer,
                ),
                _buildStatCardDetailed(
                  'Time to Empty',
                  timeToEmpty,
                  Colors.orange,
                  Icons.timer_off,
                ),
                _buildStatCardDetailed(
                  'Total Time Charging',
                  '${_batteryData.chargingTime.inHours}h',
                  Colors.cyan,
                  Icons.hourglass_bottom,
                ),
                _buildStatCardDetailed(
                  'Total Time Discharging',
                  '${_batteryData.dischargingTime.inHours}h',
                  Colors.amber,
                  Icons.hourglass_top,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardDetailed(String title, String value, Color color, IconData icon) {
    return Card(
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendSummary() {
    return Card(
      elevation: 8,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trend Summary',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            _buildTrendItem('Average Level', '${(_history.isNotEmpty ? (_history.map((h) => h.level).reduce((a, b) => a + b) ~/ _history.length) : 0)}%'),
            const SizedBox(height: 12),
            _buildTrendItem('Total Records', '${_history.length} entries'),
            const SizedBox(height: 12),
            _buildTrendItem('Charging Times', '${_history.where((h) => h.isCharging).length} records'),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendItem(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isMonitoring ? null : _startMonitoring,
            icon: const Icon(Icons.play_arrow),
            label: const Text('START'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isMonitoring ? _stopMonitoring : null,
            icon: const Icon(Icons.stop),
            label: const Text('STOP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _clearData,
            icon: const Icon(Icons.clear),
            label: const Text('CLEAR'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ===== HELPER METHODS =====

  Color _getHealthColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.orange;
    if (percentage >= 40) return Colors.deepOrange;
    return Colors.red;
  }

  Color _getTempColor(double celsius) {
    if (celsius < 10) return Colors.cyan;
    if (celsius <= 25) return Colors.green;
    if (celsius <= 35) return Colors.lime;
    if (celsius <= 45) return Colors.orange;
    return Colors.red;
  }

  Color _getVoltageColor(double voltage) {
    if (voltage >= 4.0 && voltage <= 4.2) return Colors.green;
    if (voltage >= 3.7 && voltage < 4.0) return Colors.orange;
    return Colors.red;
  }

  Color _getCapacityColor(double capacityPercent) {
    if (capacityPercent >= 85) return Colors.green;
    if (capacityPercent >= 70) return Colors.lime;
    if (capacityPercent >= 50) return Colors.orange;
    return Colors.red;
  }

  Color _getStatusColor(String status) {
    return status == 'Good' ? Colors.green : Colors.orange;
  }

  String _getHealthStatus(double health) {
    if (health >= 90) return '✅ Excellent';
    if (health >= 80) return '✅ Good';
    if (health >= 70) return '⚠️ Fair';
    if (health >= 50) return '⚠️ Poor';
    return '❌ Critical';
  }

  String _getHealthRecommendation(double health) {
    if (health >= 80) {
      return 'Your battery is in excellent condition. Continue normal usage.';
    } else if (health >= 60) {
      return 'Your battery is showing signs of aging. Consider reducing screen time.';
    } else {
      return 'Battery health is degraded. Consider servicing or replacement soon.';
    }
  }

  String _getTemperatureStatus(double celsius) {
    if (celsius < 10) return 'Cold ❄️';
    if (celsius <= 25) return 'Optimal ✅';
    if (celsius <= 35) return 'Warm ⚠️';
    if (celsius <= 45) return 'Hot 🔥';
    return 'Critical 🚨';
  }

  String _getDegradationForecast(double health, int cycles) {
    double estimatedRemainingYears = (health / 100) * 5; // Assume 5-year life at 100%
    return 'Based on current degradation rate and $cycles charge cycles, your battery may last approximately ${estimatedRemainingYears.toStringAsFixed(1)} more years.';
  }
}
