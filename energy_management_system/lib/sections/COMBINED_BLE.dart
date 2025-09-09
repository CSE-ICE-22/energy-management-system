
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BatteryDataProvider(),
      child: const BatteryMonitorApp(),
    ),
  );
}

class BatteryDataProvider extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _dataCharacteristic;
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

  Future<void> connect() async {
    try {
      // Check Bluetooth status
      if (!(await FlutterBluePlus.isOn)) {
        _connectionStatus = 'Error: Bluetooth is off';
        notifyListeners();
        print('Bluetooth is off');
        return;
      }

      // Request permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      if (!statuses[Permission.bluetoothScan]!.isGranted ||
          !statuses[Permission.bluetoothConnect]!.isGranted ||
          !statuses[Permission.location]!.isGranted) {
        _connectionStatus = 'Error: Permissions denied';
        notifyListeners();
        print('Permissions denied: $statuses');
        return;
      }

      _connectionStatus = 'Scanning...';
      notifyListeners();
      print('Starting BLE scan...');

      // Start scanning
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 15));
      bool deviceFound = false;

      // Listen for scan results
      await for (var results in FlutterBluePlus.scanResults.timeout(
        Duration(seconds: 15),
        onTimeout: (EventSink<List<ScanResult>> sink) {
          _connectionStatus = 'Error: Scan timed out';
          notifyListeners();
          print('Scan timed out');
          sink.close();
        })) {
        for (ScanResult r in results) {
          print('Found device: ${r.device.name}, RSSI: ${r.rssi}');
          if (r.device.name == 'ESP32_BatteryMonitor') {
            deviceFound = true;
            _device = r.device;
            await FlutterBluePlus.stopScan();
            _connectionStatus = 'Connecting...';
            notifyListeners();
            print('Connecting to ${r.device.name}...');

            // Connect with retry logic
            bool connected = false;
            for (int i = 0; i < 3; i++) {
              try {
                await _device!.connect(timeout: Duration(seconds: 10));
                connected = true;
                break;
              } catch (e) {
                print('Connection attempt ${i + 1} failed: $e');
                if (i < 2) await Future.delayed(Duration(seconds: 2));
              }
            }

            if (!connected) {
              _connectionStatus = 'Error: Connection failed after retries';
              notifyListeners();
              print('Connection failed after retries');
              return;
            }

            _connectionStatus = 'Connected';
            notifyListeners();
            print('Connected to ${_device!.name}');

            // Discover services
            List<BluetoothService> services = await _device!.discoverServices();
            for (BluetoothService service in services) {
              if (service.uuid.toString() == '4fafc201-1fb5-459e-8fcc-c5c9c331914b') {
                for (BluetoothCharacteristic characteristic in service.characteristics) {
                  if (characteristic.uuid.toString() == 'beb5483e-36e1-4688-b7f5-ea07361b26a8') {
                    _dataCharacteristic = characteristic;
                    await characteristic.setNotifyValue(true);
                    characteristic.value.listen((data) {
                      try {
                        final jsonStr = String.fromCharCodes(data);
                        print('Received JSON: $jsonStr');
                        final json = jsonDecode(jsonStr);
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
                        _connectionStatus = 'Error: Invalid JSON - $e';
                        notifyListeners();
                        print('JSON parse error: $e');
                      }
                    });
                  }
                }
              }
            }
            break;
          }
        }
        if (deviceFound) break;
      }

      if (!deviceFound) {
        await FlutterBluePlus.stopScan();
        _connectionStatus = 'Error: Device not found';
        notifyListeners();
        print('Device ESP32_BatteryMonitor not found');
      }
    } catch (e) {
      _connectionStatus = 'Error: $e';
      _device = null;
      _dataCharacteristic = null;
      notifyListeners();
      print('Connection error: $e');
    }
  }

  Future<void> disconnect() async {
    try {
      if (_device != null) {
        await _device!.disconnect();
        print('Disconnected from ${_device!.name}');
      }
      _device = null;
      _dataCharacteristic = null;
      _connectionStatus = 'Disconnected';
      notifyListeners();
    } catch (e) {
      _connectionStatus = 'Error: Disconnect failed - $e';
      notifyListeners();
      print('Disconnect error: $e');
    }
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
      length: 3,
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
              Tab(
                icon: Icon(Icons.analytics, color: Colors.purple),
                text: 'Predict',
              ),
            ],
          ),
          actions: [
            Consumer<BatteryDataProvider>(
              builder: (context, provider, child) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          provider.connectionStatus,
                          style: TextStyle(
                            color: provider.connectionStatus == 'Connected'
                                ? Colors.green
                                : Colors.red,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (provider.connectionStatus != 'Connected')
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () => provider.connect(),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4.0),
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
            return TabBarView(
              children: [
                provider.connectionStatus == 'Connected'
                    ? ChargingTab(provider: provider)
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
                            if (provider.connectionStatus.contains('Permissions denied'))
                              ElevatedButton(
                                onPressed: openAppSettings,
                                child: const Text('Open Settings'),
                              ),
                          ],
                        ),
                      ),
                provider.connectionStatus == 'Connected'
                    ? DischargingTab(provider: provider)
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
                            if (provider.connectionStatus.contains('Permissions denied'))
                              ElevatedButton(
                                onPressed: openAppSettings,
                                child: const Text('Open Settings'),
                              ),
                          ],
                        ),
                      ),
                PredictTab(provider: provider),
              ],
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

class PredictTab extends StatefulWidget {
  final BatteryDataProvider provider;

  const PredictTab({super.key, required this.provider});

  @override
  _PredictTabState createState() => _PredictTabState();
}

class _PredictTabState extends State<PredictTab> {
  final TextEditingController _voltageController = TextEditingController();
  final TextEditingController _currentController = TextEditingController();
  double _aiPredictedTimeH = 0.0;
  List<FlSpot> _aiVoltageVsCapacity = [];

  void _predictRemainingTime() {
    setState(() {
      double voltage = double.tryParse(_voltageController.text) ?? 0.0;
      double current = double.tryParse(_currentController.text) ?? 0.0;
      if (voltage > 0 && current > 0) {
        _aiPredictedTimeH = widget.provider.capacitymAh / current;
        _aiVoltageVsCapacity.add(FlSpot(widget.provider.capacitymAh, voltage));
        if (_aiVoltageVsCapacity.length > widget.provider._maxDataPoints) {
          _aiVoltageVsCapacity.removeAt(0);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double systematicVoltage = widget.provider.batteryV * 40;

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
                colors: [Colors.purple[100]!, Colors.purple[300]!],
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
                    Icons.science,
                    size: 40,
                    color: Colors.purple[700],
                    key: ValueKey('systematic'),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Systematic Predict',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text('Voltage (INA219 x 40): ${systematicVoltage.toStringAsFixed(2)} V'),
                    Text('Remaining Time: ${widget.provider.remainingTimeH.toStringAsFixed(1)} h'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal[100]!, Colors.teal[300]!],
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 40,
                      color: Colors.teal[700],
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'AI Predict',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _voltageController,
                  decoration: InputDecoration(
                    labelText: 'Voltage (V)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _currentController,
                  decoration: InputDecoration(
                    labelText: 'Current Draw (mA)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _predictRemainingTime,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Predict'),
                ),
                const SizedBox(height: 10),
                Text('AI Predicted Remaining Time: ${_aiPredictedTimeH.toStringAsFixed(1)} h'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'AI Voltage vs. Capacity',
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
                    spots: _aiVoltageVsCapacity,
                    isCurved: true,
                    color: Colors.teal,
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
