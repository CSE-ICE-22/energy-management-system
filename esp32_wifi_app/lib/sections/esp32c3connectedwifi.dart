import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

void main() {
  runApp(const EnergyManagementApp());
}

class EnergyManagementApp extends StatelessWidget {
  const EnergyManagementApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Energy Management System',
      theme: ThemeData(
        primaryColor: const Color(0xFF0288D1),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blue,
          accentColor: const Color(0xFFFFA726),
        ).copyWith(secondary: const Color(0xFFFFA726)),
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme,
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0288D1),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: const EnergyHomePage(),
    );
  }
}

class EnergyHomePage extends StatefulWidget {
  const EnergyHomePage({Key? key}) : super(key: key);

  @override
  _EnergyHomePageState createState() => _EnergyHomePageState();
}

class _EnergyHomePageState extends State<EnergyHomePage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> dataPoints = [];
  bool isConnected = false;
  String connectionStatus = 'Disconnected';
  TabController? _tabController;
  Timer? _timer;
  final String esp32Ip = '192.168.4.1'; // ESP32-C3 AP IP

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _requestPermissions();
    _startFetchingData();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.nearbyWifiDevices, // Required for Wi-Fi on newer Android versions
    ].request();
    if (statuses[Permission.nearbyWifiDevices]!.isDenied) {
      setState(() {
        connectionStatus = 'Wi-Fi permission denied. Please grant it.';
      });
    }
  }

  Future<void> _fetchData() async {
    try {
      final response = await http.get(Uri.parse('http://$esp32Ip/')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          isConnected = true;
          connectionStatus = 'Connected to ESP32-C3 WiFi';
          dataPoints.add(data);
          if (dataPoints.length > 50) dataPoints.removeAt(0);
        });
      } else {
        setState(() {
          isConnected = false;
          connectionStatus = 'Failed to fetch data: HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isConnected = false;
        connectionStatus = 'Connection error: $e';
      });
    }
  }

  void _startFetchingData() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchData();
    });
  }

  void _stopFetchingData() {
    _timer?.cancel();
    setState(() {
      isConnected = false;
      connectionStatus = 'Disconnected';
      dataPoints.clear();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF0288D1), const Color(0xFF4FC3F7).withOpacity(0.8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Text(
                  'Energy Management System',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
                  ),
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: const Color(0xFF0288D1),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFFFFA726),
                  indicatorWeight: 4,
                  labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(icon: Icon(Icons.battery_charging_full_rounded), text: 'Charging'),
                    Tab(icon: Icon(Icons.battery_alert_rounded), text: 'Discharging'),
                    Tab(icon: Icon(Icons.analytics_rounded), text: 'Prediction'),
                  ],
                ),
              ).animate().fadeIn(duration: 800.ms).slideY(begin: -0.1, end: 0),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  connectionStatus,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: isConnected ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ).animate().fadeIn(duration: 1000.ms),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    ChargingTab(dataPoints: dataPoints),
                    DischargingTab(dataPoints: dataPoints),
                    PredictionTab(dataPoints: dataPoints),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isConnected ? _stopFetchingData : _startFetchingData,
        backgroundColor: isConnected ? const Color(0xFFFF5252) : const Color(0xFF0288D1),
        child: Icon(isConnected ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 30),
        elevation: 6,
      ).animate().scale(duration: 600.ms, curve: Curves.easeInOut),
    );
  }
}

class ChargingTab extends StatelessWidget {
  final List<Map<String, dynamic>> dataPoints;
  const ChargingTab({Key? key, required this.dataPoints}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> latestData = dataPoints.isNotEmpty ? dataPoints.last : {};
    final String mode = latestData['mode'] ?? 'Unknown';
    if (mode != 'Charging') {
      return Center(
        child: Text(
          'Switch to Charging Mode',
          style: GoogleFonts.poppins(fontSize: 18, color: Colors.white70),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Charging Details',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
            ),
          ).animate().fadeIn(duration: 600.ms),
          const SizedBox(height: 12),
          _buildDataCard('Current INA Voltage', latestData['battery_V']?.toStringAsFixed(2) ?? 'N/A', 'V', Icons.bolt_rounded, Colors.blue[600]!),
          _buildDataCard('Current Flow', latestData['charge_I_mA']?.toStringAsFixed(2) ?? 'N/A', 'mA', Icons.battery_charging_full_rounded, Colors.blue[600]!),
          _buildDataCard('Capacity', latestData['capacity_mAh']?.toStringAsFixed(0) ?? 'N/A', 'mAh', Icons.battery_full_rounded, Colors.blue[600]!),
          const SizedBox(height: 20),
          Text(
            'Voltage vs Current',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 800.ms),
          _buildLineChart(dataPoints, 'battery_V', 'charge_I_mA', 'Voltage (V)', 'Current (mA)', Colors.green[400]!),
          const SizedBox(height: 20),
          Text(
            'Voltage vs Time',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 1000.ms),
          _buildLineChart(dataPoints, 'battery_V', null, 'Voltage (V)', 'Time (s)', Colors.green[400]!),
          const SizedBox(height: 20),
          Text(
            'Capacity vs Time',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 1200.ms),
          _buildLineChart(dataPoints, 'capacity_mAh', null, 'Capacity (mAh)', 'Time (s)', Colors.green[400]!),
        ],
      ),
    );
  }
}

class DischargingTab extends StatelessWidget {
  final List<Map<String, dynamic>> dataPoints;
  const DischargingTab({Key? key, required this.dataPoints}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> latestData = dataPoints.isNotEmpty ? dataPoints.last : {};
    final String mode = latestData['mode'] ?? 'Unknown';
    if (mode != 'Discharging') {
      return Center(
        child: Text(
          'Switch to Discharging Mode',
          style: GoogleFonts.poppins(fontSize: 18, color: Colors.white70),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Discharging Details',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
            ),
          ).animate().fadeIn(duration: 600.ms),
          const SizedBox(height: 12),
          _buildDataCard('Current INA Voltage', latestData['battery_V']?.toStringAsFixed(2) ?? 'N/A', 'V', Icons.bolt_rounded, Colors.red[600]!),
          _buildDataCard('Current Flow', latestData['load_I_mA']?.toStringAsFixed(2) ?? 'N/A', 'mA', Icons.battery_alert_rounded, Colors.red[600]!),
          _buildDataCard('Capacity', latestData['capacity_mAh']?.toStringAsFixed(0) ?? 'N/A', 'mAh', Icons.battery_full_rounded, Colors.red[600]!),
          _buildDataCard('Remaining Time', latestData['remaining_time_h']?.toStringAsFixed(2) ?? 'N/A', 'h', Icons.timer_rounded, Colors.red[600]!),
          const SizedBox(height: 20),
          Text(
            'Voltage vs Current',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 800.ms),
          _buildLineChart(dataPoints, 'battery_V', 'load_I_mA', 'Voltage (V)', 'Current (mA)', Colors.red[400]!),
          const SizedBox(height: 20),
          Text(
            'Voltage vs Time',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 1000.ms),
          _buildLineChart(dataPoints, 'battery_V', null, 'Voltage (V)', 'Time (s)', Colors.red[400]!),
          const SizedBox(height: 20),
          Text(
            'Capacity vs Time',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 1200.ms),
          _buildLineChart(dataPoints, 'capacity_mAh', null, 'Capacity (mAh)', 'Time (s)', Colors.red[400]!),
        ],
      ),
    );
  }
}

class PredictionTab extends StatefulWidget {
  final List<Map<String, dynamic>> dataPoints;
  const PredictionTab({Key? key, required this.dataPoints}) : super(key: key);

  @override
  _PredictionTabState createState() => _PredictionTabState();
}

class _PredictionTabState extends State<PredictionTab> {
  final _voltageController = TextEditingController();
  final _currentController = TextEditingController();
  final _capacityController = TextEditingController();
  double? remainingTime;
  bool _showSystematicPrediction = false;
  String? errorMessage;

  Future<void> _calculateRemainingTime() async {
    final double? voltage = double.tryParse(_voltageController.text);
    final double? current = double.tryParse(_currentController.text);
    final double? capacity = double.tryParse(_capacityController.text);
    if (voltage != null && current != null && capacity != null && voltage > 0 && current > 0 && capacity > 0) {
      try {
        final response = await http.post(
          Uri.parse('http://127.0.0.1:5000/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'voltage': voltage, 'current': current / 1000}), // Convert mA to A
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            remainingTime = data['remaining_time'];
            errorMessage = null;
          });
        } else {
          final data = jsonDecode(response.body);
          setState(() {
            remainingTime = null;
            errorMessage = data['error'] ?? 'Error fetching prediction';
          });
        }
      } catch (e) {
        setState(() {
          remainingTime = null;
          errorMessage = 'Connection error: $e';
        });
      }
    } else {
      setState(() {
        remainingTime = null;
        errorMessage = 'Please enter valid voltage, current, and capacity';
      });
    }
  }

  void _toggleSystematicPrediction() {
    setState(() {
      _showSystematicPrediction = !_showSystematicPrediction;
    });
  }

  @override
  void dispose() {
    _voltageController.dispose();
    _currentController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> latestData = widget.dataPoints.isNotEmpty ? widget.dataPoints.last : {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Battery Life Prediction',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: const Offset(2, 2))],
            ),
          ).animate().fadeIn(duration: 600.ms),
          const SizedBox(height: 20),
          Text(
            'Systematic Prediction',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ).animate().fadeIn(duration: 800.ms),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _toggleSystematicPrediction,
            child: Text(_showSystematicPrediction ? 'Hide' : 'Use'),
          ).animate().fadeIn(duration: 1000.ms).scale(),
          if (_showSystematicPrediction) ...[
            const SizedBox(height: 12),
            _buildDataCard('Current INA Voltage', latestData['battery_V']?.toStringAsFixed(2) ?? 'N/A', 'V', Icons.bolt_rounded, Colors.orange[600]!),
            _buildDataCard('Current Flow', latestData['load_I_mA']?.toStringAsFixed(2) ?? 'N/A', 'mA', Icons.battery_alert_rounded, Colors.orange[600]!),
            _buildDataCard('Capacity', latestData['capacity_mAh']?.toStringAsFixed(0) ?? 'N/A', 'mAh', Icons.battery_full_rounded, Colors.orange[600]!),
            _buildDataCard('Remaining Time', latestData['remaining_time_h']?.toStringAsFixed(2) ?? 'N/A', 'h', Icons.timer_rounded, Colors.orange[600]!),
          ],
          const SizedBox(height: 20),
          Text(
            'Non-Systematic Prediction (AI)',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ).animate().fadeIn(duration: 2000.ms),
          const SizedBox(height: 12),
          TextField(
            controller: _voltageController,
            decoration: InputDecoration(
              labelText: 'Voltage (V)',
              labelStyle: GoogleFonts.poppins(color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.bolt_rounded, color: Colors.white70),
            ),
            keyboardType: TextInputType.number,
            style: GoogleFonts.poppins(color: Colors.white),
          ).animate().fadeIn(duration: 2200.ms),
          const SizedBox(height: 12),
          TextField(
            controller: _currentController,
            decoration: InputDecoration(
              labelText: 'Current Draw (mA)',
              labelStyle: GoogleFonts.poppins(color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.battery_alert_rounded, color: Colors.white70),
            ),
            keyboardType: TextInputType.number,
            style: GoogleFonts.poppins(color: Colors.white),
          ).animate().fadeIn(duration: 2400.ms),
          const SizedBox(height: 12),
          TextField(
            controller: _capacityController,
            decoration: InputDecoration(
              labelText: 'Battery Capacity (mAh)',
              labelStyle: GoogleFonts.poppins(color: Colors.white70),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.battery_full_rounded, color: Colors.white70),
            ),
            keyboardType: TextInputType.number,
            style: GoogleFonts.poppins(color: Colors.white),
          ).animate().fadeIn(duration: 2600.ms),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _calculateRemainingTime,
            child: const Text('Calculate'),
          ).animate().fadeIn(duration: 2800.ms).scale(),
          const SizedBox(height: 20),
          if (errorMessage != null)
            Text(
              errorMessage!,
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.red[700]),
            ).animate().fadeIn(duration: 3000.ms)
          else if (remainingTime != null)
            _buildDataCard('Remaining Time', remainingTime!.toStringAsFixed(2), 'h', Icons.timer_rounded, Colors.orange[600]!)
                .animate().fadeIn(duration: 3000.ms)
          else
            Text(
              'Enter valid voltage, current, and capacity to predict.',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70),
            ).animate().fadeIn(duration: 3000.ms),
        ],
      ),
    );
  }
}

Widget _buildDataCard(String title, String value, String unit, IconData icon, Color iconColor) {
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, Colors.white.withOpacity(0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 30),
        title: Text(
          '$title: $value $unit',
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    ),
  ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1, end: 0);
}

Widget _buildLineChart(
  List<Map<String, dynamic>> dataPoints,
  String yKey,
  String? xKey,
  String yLabel,
  String xLabel,
  Color lineColor,
) {
  return Container(
    height: 220,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.95),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: yKey == 'capacity_mAh' ? 500 : 1,
          verticalInterval: xKey != null ? 50 : 10,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[300],
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (value) => FlLine(
            color: Colors.grey[300],
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(yKey == 'capacity_mAh' ? 0 : 1),
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
              ),
            ),
            axisNameWidget: Text(yLabel, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.black87),
              ),
            ),
            axisNameWidget: Text(xLabel, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey[300]!, width: 1),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints.asMap().entries.map((e) {
              final int index = e.key;
              final data = e.value;
              final double x = xKey != null ? (data[xKey]?.toDouble() ?? 0.0) : index.toDouble() * 2.0;
              final double y = data[yKey]?.toDouble() ?? 0.0;
              return FlSpot(x, y);
            }).toList(),
            isCurved: true,
            color: lineColor,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 4,
                color: lineColor,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withOpacity(0.2),
            ),
          ),
        ],
        minY: yKey == 'capacity_mAh' ? 0 : null,
        maxY: yKey == 'capacity_mAh' ? 5000 : null,
      ),
    ),
  ).animate().fadeIn(duration: 800.ms).scale();
}
