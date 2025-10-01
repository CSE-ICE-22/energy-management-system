import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';

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
        primaryColor: const Color(0xFF1976D2),
        scaffoldBackgroundColor: Colors.white,
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
        // Removed tabBarTheme due to type mismatch error.
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
  // Removed invalid assignment; use FlutterBluePlus directly for static methods.
  BluetoothDevice? device;
  BluetoothCharacteristic? characteristic;
  List<Map<String, dynamic>> dataPoints = [];
  bool isConnected = false;
  TabController? _tabController;
  String connectionStatus = 'Disconnected';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _startBluetoothScan();
  }

  Future<void> _startBluetoothScan() async {
    try {
      // Check Bluetooth status
      final bool isOn = await FlutterBluePlus.isOn;
      if (!isOn) {
        setState(() {
          connectionStatus = 'Bluetooth is off. Please turn it on.';
        });
        print("Bluetooth is off");
        return;
      }

      setState(() {
        connectionStatus = 'Scanning for EnergyMonitor...';
      });

      // Start scanning (Future<void>, no assignment)
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.name == "EnergyMonitor") {
            setState(() {
              device = r.device;
              connectionStatus = 'Found EnergyMonitor. Connecting...';
            });
            FlutterBluePlus.stopScan();
            _connectToDevice();
            break;
          }
        }
      }, onDone: () {
        if (device == null) {
          setState(() {
            connectionStatus = 'Device not found. Retry?';
          });
        }
      });
    } catch (e) {
      setState(() {
        connectionStatus = 'Scan error: $e';
      });
      print("Bluetooth scan error: $e");
    }
  }

  Future<void> _connectToDevice() async {
    if (device == null) return;
    try {
      // Connect to device (Future<void>)
      await device!.connect(timeout: const Duration(seconds: 15));
      setState(() {
        isConnected = true;
        connectionStatus = 'Connected to ${device!.name}';
      });

      // Discover services (returns Future<List<BluetoothService>>)
      final List<BluetoothService> services = await device!.discoverServices();
      for (final BluetoothService service in services) {
        if (service.uuid.toString() == "0000180f-0000-1000-8000-00805f9b34fb") {
          for (final BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid.toString() == "00002a19-0000-1000-8000-00805f9b34fb") {
              characteristic = c;
              // Enable notifications (Future<void>)
              await c.setNotifyValue(true);
              c.value.listen((value) {
                if (value.isNotEmpty) {
                  final String jsonStr = String.fromCharCodes(value);
                  try {
                    final Map<String, dynamic> data = jsonDecode(jsonStr);
                    setState(() {
                      dataPoints.add(data);
                      if (dataPoints.length > 50) dataPoints.removeAt(0); // Keep last 50 points
                    });
                  } catch (e) {
                    print("JSON parse error: $e");
                  }
                }
              });
              break;
            }
          }
          break;
        }
      }
    } catch (e) {
      setState(() {
        isConnected = false;
        connectionStatus = 'Connection error: $e';
      });
      print("BLE connection error: $e");
    }
  }

  Future<void> _disconnect() async {
    if (device != null) {
      await device!.disconnect(); // Future<void>
      setState(() {
        isConnected = false;
        device = null;
        characteristic = null;
        dataPoints.clear();
        connectionStatus = 'Disconnected';
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Energy Management System',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Roboto'),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.battery_charging_full), text: 'Charging'),
            Tab(icon: Icon(Icons.battery_std), text: 'Discharging'),
            Tab(icon: Icon(Icons.analytics), text: 'Prediction'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              connectionStatus,
              style: TextStyle(fontSize: 14, fontFamily: 'Roboto', color: isConnected ? Colors.green : Colors.red),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ChargingTab(dataPoints: dataPoints),
                DischargingTab(dataPoints: dataPoints),
                const PredictionTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isConnected ? _disconnect : _startBluetoothScan,
        backgroundColor: isConnected ? const Color(0xFFF44336) : const Color(0xFF1976D2),
        child: Icon(isConnected ? Icons.bluetooth_disabled : Icons.bluetooth),
      ),
    );
  }
}

class ChargingTab extends StatelessWidget {
  final List<Map<String, dynamic>> dataPoints;
  const ChargingTab({Key? key, required this.dataPoints}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> latestData = dataPoints.isNotEmpty ? dataPoints.last : {};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Charging Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50), fontFamily: 'Roboto'),
          ),
          const SizedBox(height: 10),
          _buildDataCard('Bus Voltage', latestData['battery_V']?.toStringAsFixed(2) ?? 'N/A', 'V', Icons.bolt),
          _buildDataCard('Shunt Voltage', latestData['charge_shunt_mV']?.toStringAsFixed(2) ?? 'N/A', 'mV', Icons.electrical_services),
          _buildDataCard('Current', latestData['charge_I_mA']?.toStringAsFixed(2) ?? 'N/A', 'mA', Icons.battery_charging_full),
          _buildDataCard('Power', latestData['charge_power_mW']?.toStringAsFixed(2) ?? 'N/A', 'mW', Icons.power),
          _buildDataCard('Capacity', latestData['capacity_mAh']?.toStringAsFixed(0) ?? 'N/A', 'mAh', Icons.battery_full),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs Current',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'battery_V', 'charge_I_mA', 'Voltage (V)', 'Current (mA)', const Color(0xFF4CAF50)),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'battery_V', null, 'Voltage (V)', 'Time (s)', const Color(0xFF4CAF50)),
          const SizedBox(height: 20),
          const Text(
            'Capacity vs Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'capacity_mAh', null, 'Capacity (mAh)', 'Time (s)', const Color(0xFF4CAF50)),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Discharging Details',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFF44336), fontFamily: 'Roboto'),
          ),
          const SizedBox(height: 10),
          _buildDataCard('Bus Voltage', latestData['battery_V']?.toStringAsFixed(2) ?? 'N/A', 'V', Icons.bolt),
          _buildDataCard('Shunt Voltage', latestData['load_shunt_mV']?.toStringAsFixed(2) ?? 'N/A', 'mV', Icons.electrical_services),
          _buildDataCard('Current', latestData['load_I_mA']?.toStringAsFixed(2) ?? 'N/A', 'mA', Icons.battery_std),
          _buildDataCard('Power', latestData['load_power_mW']?.toStringAsFixed(2) ?? 'N/A', 'mW', Icons.power),
          _buildDataCard('Capacity', latestData['capacity_mAh']?.toStringAsFixed(0) ?? 'N/A', 'mAh', Icons.battery_full),
          _buildDataCard('Remaining Time', latestData['remaining_time_h']?.toStringAsFixed(2) ?? 'N/A', 'h', Icons.timer),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs Current',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'battery_V', 'load_I_mA', 'Voltage (V)', 'Current (mA)', const Color(0xFFF44336)),
          const SizedBox(height: 20),
          const Text(
            'Voltage vs Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'battery_V', null, 'Voltage (V)', 'Time (s)', const Color(0xFFF44336)),
          const SizedBox(height: 20),
          const Text(
            'Capacity vs Time',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          _buildLineChart(dataPoints, 'capacity_mAh', null, 'Capacity (mAh)', 'Time (s)', const Color(0xFFF44336)),
        ],
      ),
    );
  }
}

class PredictionTab extends StatefulWidget {
  const PredictionTab({Key? key}) : super(key: key);

  @override
  _PredictionTabState createState() => _PredictionTabState();
}

class _PredictionTabState extends State<PredictionTab> {
  final _voltageController = TextEditingController();
  final _currentController = TextEditingController();
  double? remainingTime;

  void _calculateRemainingTime() {
    final double? voltage = double.tryParse(_voltageController.text);
    final double? current = double.tryParse(_currentController.text);
    if (voltage != null && current != null && current > 0) {
      // Simple linear model: time = capacity / current, adjusted by voltage
      final double capacity = 3000.0 * (voltage / 4.2); // Scale capacity by voltage ratio
      setState(() {
        remainingTime = capacity / current;
      });
    } else {
      setState(() {
        remainingTime = null;
      });
    }
  }

  @override
  void dispose() {
    _voltageController.dispose();
    _currentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prediction',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1976D2), fontFamily: 'Roboto'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _voltageController,
            decoration: const InputDecoration(
              labelText: 'Voltage (V)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.bolt, color: Color(0xFF1976D2)),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _currentController,
            decoration: const InputDecoration(
              labelText: 'Current Draw (mA)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.battery_std, color: Color(0xFF1976D2)),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _calculateRemainingTime,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
            child: const Text(
              'Calculate',
              style: TextStyle(fontSize: 16, color: Colors.white, fontFamily: 'Roboto'),
            ),
          ),
          const SizedBox(height: 20),
          if (remainingTime != null)
            _buildDataCard('Remaining Time', remainingTime!.toStringAsFixed(2), 'h', Icons.timer)
          else
            const Text(
              'Enter valid voltage and current to predict.',
              style: TextStyle(fontSize: 16, color: Color(0xFF757575), fontFamily: 'Roboto'),
            ),
        ],
      ),
    );
  }
}

Widget _buildDataCard(String title, String value, String unit, IconData icon) {
  return Card(
    elevation: 2,
    margin: const EdgeInsets.symmetric(vertical: 5),
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF1976D2)),
      title: Text(
        '$title: $value $unit',
        style: const TextStyle(fontSize: 16, fontFamily: 'Roboto'),
      ),
    ),
  );
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
    height: 200,
    padding: const EdgeInsets.all(10),
    child: LineChart(
      LineChartData(
        gridData: const FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12, fontFamily: 'Roboto'),
              ),
            ),
            axisNameWidget: Text(yLabel, style: const TextStyle(fontSize: 14, fontFamily: 'Roboto')),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 12, fontFamily: 'Roboto'),
              ),
            ),
            axisNameWidget: Text(xLabel, style: const TextStyle(fontSize: 14, fontFamily: 'Roboto')),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: dataPoints.asMap().entries.map((e) {
              final int index = e.key;
              final data = e.value;
              final double x = xKey != null ? (data[xKey]?.toDouble() ?? 0.0) : index.toDouble() * 2.0; // 2s interval
              final double y = data[yKey]?.toDouble() ?? 0.0;
              return FlSpot(x, y);
            }).toList(),
            isCurved: true,
            color: lineColor,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: lineColor.withOpacity(0.3)),
          ),
        ],
      ),
    ),
  );
}