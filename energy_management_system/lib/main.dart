import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BatteryDataProvider(),
      child: const BatteryMonitorApp(),
    ),
  );
}

class BatteryDataProvider extends ChangeNotifier {
  IOWebSocketChannel? _channel;
  String _connectionStatus = 'Disconnected';
  String _mode = 'unknown';
  double _batteryV = 0.0;
  double _chargeV = 0.0;
  double _chargeCurrentmA = 0.0;
  double _loadCurrentmA = 0.0;
  double _capacitymAh = 0.0;
  double _remainingTimeH = 0.0;
  List<FlSpot> _capacityVsTime = [];
  List<FlSpot> _voltageVsCapacity = [];
  final int _maxDataPoints = 50;

  String get connectionStatus => _connectionStatus;
  String get mode => _mode;
  double get batteryV => _batteryV;
  double get chargeV => _chargeV;
  double get chargeCurrentmA => _chargeCurrentmA;
  double get loadCurrentmA => _loadCurrentmA;
  double get capacitymAh => _capacitymAh;
  double get remainingTimeH => _remainingTimeH;
  List<FlSpot> get capacityVsTime => _capacityVsTime;
  List<FlSpot> get voltageVsCapacity => _voltageVsCapacity;

  void connect() {
    try {
      _channel = IOWebSocketChannel.connect('ws://192.168.4.1:81');
      _connectionStatus = 'Connected';
      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data);
            _mode = json['mode'] ?? 'unknown';
            _batteryV = (json['battery_V'] ?? 0.0).toDouble();
            _chargeV = (json['charge_V'] ?? 0.0).toDouble();
            _chargeCurrentmA = (json['charge_current_mA'] ?? 0.0).toDouble();
            _loadCurrentmA = (json['load_current_mA'] ?? 0.0).toDouble();
            _capacitymAh = (json['capacity_mAh'] ?? 0.0).toDouble();
            _remainingTimeH = (json['remaining_time_h'] ?? 0.0).toDouble();
            double timestamp = (json['timestamp'] ?? 0.0).toDouble();

            // Update charts
            _capacityVsTime.add(FlSpot(timestamp / 3600, _capacitymAh));
            _voltageVsCapacity.add(FlSpot(_capacitymAh, _batteryV));
            if (_capacityVsTime.length > _maxDataPoints) {
              _capacityVsTime.removeAt(0);
              _voltageVsCapacity.removeAt(0);
            }
            notifyListeners();
          } catch (e) {
            _connectionStatus = 'Error: Invalid JSON';
            notifyListeners();
          }
        },
        onError: (error) {
          _connectionStatus = 'Error: $error';
          _channel = null;
          notifyListeners();
        },
        onDone: () {
          _connectionStatus = 'Disconnected';
          _channel = null;
          notifyListeners();
        },
      );
    } catch (e) {
      _connectionStatus = 'Error: $e';
      notifyListeners();
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connectionStatus = 'Disconnected';
    notifyListeners();
  }
}

class BatteryMonitorApp extends StatelessWidget {
  const BatteryMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const BatteryMonitorHome(),
    );
  }
}

class BatteryMonitorHome extends StatefulWidget {
  const BatteryMonitorHome({super.key});

  @override
  _BatteryMonitorHomeState createState() => _BatteryMonitorHomeState();
}

class _BatteryMonitorHomeState extends State<BatteryMonitorHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<BatteryDataProvider>(context, listen: false).connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Battery Monitor'),
          centerTitle: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue, Colors.blueAccent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.battery_charging_full, color: Colors.green),
                text: 'Charging',
              ),
              Tab(
                icon: Icon(Icons.battery_alert, color: Colors.red),
                text: 'Discharging',
              ),
            ],
          ),
          actions: [
            Consumer<BatteryDataProvider>(
              builder: (context, provider, child) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Text(
                        provider.connectionStatus,
                        style: TextStyle(
                          color: provider.connectionStatus == 'Connected'
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (provider.connectionStatus != 'Connected')
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => provider.connect(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        body: Consumer<BatteryDataProvider>(
          builder: (context, provider, child) {
            return provider.connectionStatus == 'Connected'
                ? TabBarView(
                    children: [
                      ChargingTab(provider: provider),
                      DischargingTab(provider: provider),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SpinKitCircle(color: Colors.blue, size: 50.0),
                        const SizedBox(height: 20),
                        Text(
                          provider.connectionStatus,
                          style: const TextStyle(fontSize: 18, color: Colors.red),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => provider.connect(),
                          child: const Text('Retry Connection'),
                        ),
                      ],
                    ),
                  );
          },
        ),
      ),
    );
  }
}

class ChargingTab extends StatelessWidget {
  final BatteryDataProvider provider;

  const ChargingTab({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: provider.mode == 'charging'
                    ? [Colors.green[100]!, Colors.green[300]!]
                    : [Colors.grey[100]!, Colors.grey[300]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 2,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Icon(
                    Icons.battery_charging_full,
                    size: 40,
                    color: provider.mode == 'charging' ? Colors.green : Colors.grey,
                    key: ValueKey(provider.mode),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Charging Status: ${provider.mode == 'charging' ? 'Active' : 'Inactive'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text('Battery Voltage: ${provider.batteryV.toStringAsFixed(2)} V'),
                    Text('Charge Voltage: ${provider.chargeV.toStringAsFixed(2)} V'),
                    Text('Charge Current: ${provider.chargeCurrentmA.toStringAsFixed(1)} mA'),
                    Text('Capacity: ${provider.capacitymAh.toStringAsFixed(0)} mAh'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Capacity vs. Time',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                    axisNameWidget: const Text('Time (h)'),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: provider.capacityVsTime,
                    isCurved: true,
                    color: Colors.green,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs. Capacity',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                    axisNameWidget: const Text('Capacity (mAh)'),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: provider.voltageVsCapacity,
                    isCurved: true,
                    color: Colors.green,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DischargingTab extends StatelessWidget {
  final BatteryDataProvider provider;

  const DischargingTab({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: provider.mode == 'discharging'
                    ? [Colors.red[100]!, Colors.red[300]!]
                    : [Colors.grey[100]!, Colors.grey[300]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.5),
                  spreadRadius: 2,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Icon(
                    Icons.battery_alert,
                    size: 40,
                    color: provider.mode == 'discharging' ? Colors.red : Colors.grey,
                    key: ValueKey(provider.mode),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Discharging Status: ${provider.mode == 'discharging' ? 'Active' : 'Inactive'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text('Battery Voltage: ${provider.batteryV.toStringAsFixed(2)} V'),
                    Text('Load Current: ${provider.loadCurrentmA.toStringAsFixed(1)} mA'),
                    Text('Capacity: ${provider.capacitymAh.toStringAsFixed(0)} mAh'),
                    Text('Remaining Time: ${provider.remainingTimeH.toStringAsFixed(1)} h'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Capacity vs. Time',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                    axisNameWidget: const Text('Time (h)'),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: provider.capacityVsTime,
                    isCurved: true,
                    color: Colors.red,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs. Capacity',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 30),
                    axisNameWidget: const Text('Capacity (mAh)'),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: provider.voltageVsCapacity,
                    isCurved: true,
                    color: Colors.red,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}