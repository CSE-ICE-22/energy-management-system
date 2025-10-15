import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

// Neural Network Inference Logic
class BatteryMLP {
  // Placeholder weights (replace with actual values from your model)
  static const List<List<double>> fc1Weight = [[-0.3270801901817322, -0.09553776681423187]]; // Truncated for brevity
  static const List<double> fc1Bias = [0.0]; // Define actual biases
  static const List<List<double>> fc2Weight = [[]]; // Define actual weights
  static const List<double> fc2Bias = [0.0];
  static const List<List<double>> fc3Weight = [[]];
  static const List<double> fc3Bias = [0.0];
  static const List<List<double>> fc4Weight = [[]];
  static const List<double> fc4Bias = [0.0];
  static const List<double> xMean = [3.7, 0.5]; // Example normalization
  static const List<double> xStd = [0.5, 0.3];
  static const double yLogMean = 0.0;
  static const double yLogStd = 1.0;

  // Matrix multiplication: output = input * weight^T + bias
  static List<double> matmul(List<double> input, List<List<double>> weight, List<double> bias) {
    List<double> output = List.filled(weight.length, 0.0);
    for (int i = 0; i < weight.length; i++) {
      double sum = bias[i];
      for (int j = 0; j < input.length; j++) {
        sum += input[j] * weight[i][j];
      }
      output[i] = sum;
    }
    return output;
  }

  // ReLU activation
  static List<double> relu(List<double> input) {
    return input.map((x) => max(0.0, x)).toList();
  }

  // Forward pass
  static double forward(double voltage, double current) {
    // Normalize input
    List<double> input = [
      (voltage - xMean[0]) / xStd[0],
      (current - xMean[1]) / xStd[1],
    ];

    // Layer 1: fc1 -> ReLU
    List<double> out = matmul(input, fc1Weight, fc1Bias);
    out = relu(out);

    // Layer 2: fc2 -> ReLU
    out = matmul(out, fc2Weight, fc2Bias);
    out = relu(out);

    // Layer 3: fc3 -> ReLU
    out = matmul(out, fc3Weight, fc3Bias);
    out = relu(out);

    // Layer 4: fc4 (output)
    out = matmul(out, fc4Weight, fc4Bias);

    // Denormalize output
    double predLog = out[0];
    double pred = (exp(predLog * yLogStd + yLogMean) - 1);
    return max(pred, 0.0); // Ensure non-negative
  }
}

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

class _EnergyHomePageState extends State<EnergyHomePage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> dataPoints = [];
  bool isConnected = false;
  String connectionStatus = 'Disconnected';
  TabController? _tabController;
  Timer? _timer;
  final String esp32Ip = '192.168.4.1';
  AnimationController? _animationController;
  Animation<double>? _animation;
  bool _isBlinking = false;
  Color _alertColor = Colors.transparent;
  String _alertMessage = '';
  String? _dismissedAlert; // Track dismissed alert to prevent re-display

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addListener(() {
        setState(() {});
      });
    _animation = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
    );
    _requestPermissions();
    _startFetchingData();
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.nearbyWifiDevices,
    ].request();
    if (statuses[Permission.nearbyWifiDevices]!.isDenied) {
      setState(() {
        connectionStatus = 'Wi-Fi permission denied. Please grant it.';
      });
    }
  }

  Future<void> _fetchData() async {
    try {
      final response = await http.get(Uri.parse('http://$esp32Ip/?t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('Received data: $data'); // Debug: Log raw JSON
        print('Battery Voltage: ${data['battery_V']}'); // Debug: Log battery_V
        // Validate battery_V
        if (data['battery_V'] is num) {
          setState(() {
            isConnected = true;
            connectionStatus = 'Connected to ESP32 WiFi';
            dataPoints.add(data);
            if (dataPoints.length > 50) dataPoints.removeAt(0);
            // Handle alerts (only for Charging or Discharging modes)
            if (data['mode'] != 'Idle' && data['alert'] != null && data['alert'].isNotEmpty) {
              // Only trigger alert if it’s different from the dismissed one
              if (data['alert'] != _dismissedAlert) {
                _alertMessage = data['alert'];
                if (_alertMessage.contains('Low battery')) {
                  _alertColor = Colors.red[700]!;
                  _isBlinking = true;
                  _animationController!.repeat();
                } else if (_alertMessage.contains('High battery')) {
                  _alertColor = Colors.blue[700]!;
                  _isBlinking = true;
                  _animationController!.repeat();
                } else {
                  _stopBlinking();
                }
              }
            } else {
              _stopBlinking();
            }
          });
        } else {
          print('Invalid battery_V: ${data['battery_V']}'); // Debug: Log invalid battery_V
          setState(() {
            isConnected = false;
            connectionStatus = 'Invalid battery voltage data';
            _stopBlinking();
          });
        }
      } else {
        print('HTTP Error: ${response.statusCode}'); // Debug: Log HTTP error
        setState(() {
          isConnected = false;
          connectionStatus = 'Failed to fetch data: HTTP ${response.statusCode}';
          _stopBlinking();
        });
      }
    } catch (e) {
      print('Connection Error: $e'); // Debug: Log connection error
      setState(() {
        isConnected = false;
        connectionStatus = 'Connection error: $e';
        _stopBlinking();
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
      _stopBlinking();
    });
  }

  void _stopBlinking() {
    setState(() {
      _isBlinking = false;
      _alertColor = Colors.transparent;
      _dismissedAlert = _alertMessage; // Store the dismissed alert
      _alertMessage = '';
      _animationController!.stop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController?.dispose();
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _isBlinking ? _alertColor.withOpacity(_animation!.value) : const Color(0xFF0288D1),
              _isBlinking ? _alertColor.withOpacity(_animation!.value * 0.8) : const Color(0xFF4FC3F7).withOpacity(0.8),
            ],
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
              if (_isBlinking)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _alertMessage,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _stopBlinking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _alertColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Stop Alert', style: GoogleFonts.poppins()),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 800.ms),
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
  print('Plotting $yKey values: ${dataPoints.map((data) => data[yKey]).toList()}'); // Debug: Log y values
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
          horizontalInterval: yKey == 'capacity_mAh' ? 500 : 0.2, // Smaller interval for voltage
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
        minY: yKey == 'capacity_mAh' ? 0 : 3.0, // Set for voltage
        maxY: yKey == 'capacity_mAh' ? 5000 : 4.2, // Set for voltage
      ),
    ),
  ).animate().fadeIn(duration: 800.ms).scale();
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
  final TextEditingController _voltageController = TextEditingController();
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  String _aiPredictionResult = 'Enter values to predict remaining time (AI)';
  String? _systematicErrorMessage;
  double? _systematicRemainingTime;
  bool _isAILoading = false;
  bool _isSystematicLoading = false;
  bool _showSystematicPrediction = false;

  void _predictRemainingTimeAI() {
    setState(() {
      _isAILoading = true;
    });

    try {
      double voltage = double.parse(_voltageController.text);
      double current = double.parse(_currentController.text);

      // Validate inputs
      if (voltage < 0 || voltage > 4.2) {
        setState(() {
          _aiPredictionResult = 'Voltage must be between 0 and 4.2 V';
          _isAILoading = false;
        });
        return;
      }
      if (current < 0.001 || current > 10) {
        setState(() {
          _aiPredictionResult = 'Current must be between 0.001 and 10 A';
          _isAILoading = false;
        });
        return;
      }

      // Predict using neural network
      double predictedTimeSeconds = BatteryMLP.forward(voltage, current);
      double predictedTimeHours = predictedTimeSeconds / 3600;

      setState(() {
        _aiPredictionResult = 'AI Predicted remaining time: ${predictedTimeSeconds.toStringAsFixed(0)} seconds '
            '(${predictedTimeHours.toStringAsFixed(1)} hours)';
        _isAILoading = false;
      });
    } catch (e) {
      setState(() {
        _aiPredictionResult = 'Invalid input: Please enter numeric values';
        _isAILoading = false;
      });
    }
  }

  Future<void> _calculateRemainingTimeSystematic() async {
    setState(() {
      _isSystematicLoading = true;
    });

    final double? voltage = double.tryParse(_voltageController.text);
    final double? current = double.tryParse(_currentController.text);
    final double? capacity = double.tryParse(_capacityController.text);
    if (voltage != null && current != null && capacity != null && voltage > 0 && current > 0 && capacity > 0) {
      try {
        final response = await http.post(
          Uri.parse('http://127.0.0.1:5000/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'voltage': voltage, 'current': current / 1000}),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          setState(() {
            _systematicRemainingTime = data['remaining_time'];
            _systematicErrorMessage = null;
            _isSystematicLoading = false;
          });
        } else {
          final data = jsonDecode(response.body);
          setState(() {
            _systematicRemainingTime = null;
            _systematicErrorMessage = data['error'] ?? 'Error fetching prediction';
            _isSystematicLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _systematicRemainingTime = null;
          _systematicErrorMessage = 'Connection error: $e';
          _isSystematicLoading = false;
        });
      }
    } else {
      setState(() {
        _systematicRemainingTime = null;
        _systematicErrorMessage = 'Please enter valid voltage, current, and capacity';
        _isSystematicLoading = false;
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
          ).animate().fadeIn(duration: 1200.ms),
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
          ).animate().fadeIn(duration: 1400.ms),
          const SizedBox(height: 12),
          TextField(
            controller: _currentController,
            decoration: InputDecoration(
              labelText: 'Current Draw (A)',
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
          ).animate().fadeIn(duration: 1600.ms),
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
          ).animate().fadeIn(duration: 1800.ms),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _isAILoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _predictRemainingTimeAI,
                      child: Text('Predict (AI)', style: GoogleFonts.poppins()),
                    ).animate().fadeIn(duration: 2000.ms),
              _isSystematicLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _calculateRemainingTimeSystematic,
                      child: Text('Predict (Server)', style: GoogleFonts.poppins()),
                    ).animate().fadeIn(duration: 2200.ms),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _aiPredictionResult,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: 2400.ms),
          const SizedBox(height: 12),
          if (_systematicErrorMessage != null)
            Text(
              _systematicErrorMessage!,
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.red[700]),
            ).animate().fadeIn(duration: 2600.ms)
          else if (_systematicRemainingTime != null)
            _buildDataCard(
              'Server Predicted Remaining Time',
              _systematicRemainingTime!.toStringAsFixed(2),
              'h',
              Icons.timer_rounded,
              Colors.orange[600]!,
            ).animate().fadeIn(duration: 2600.ms)
          else
            Text(
              'Enter valid values to predict (Server).',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70),
            ).animate().fadeIn(duration: 2600.ms),
          const SizedBox(height: 20),
          Text(
            'Voltage vs Time',
            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ).animate().fadeIn(duration: 2800.ms),
          _buildLineChart(widget.dataPoints, 'battery_V', null, 'Voltage (V)', 'Time (s)', Colors.orange[400]!),
        ],
      ),
    );
  }
}