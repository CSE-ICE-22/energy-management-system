import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Energy Management System',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
        textTheme: TextTheme(
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey[900]),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.blueGrey[800]),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.blueGrey[700]),
        ),
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
      ),
      home: const ChargeScreen(),
    );
  }
}

class ChargeScreen extends StatefulWidget {
  const ChargeScreen({super.key});

  @override
  _ChargeScreenState createState() => _ChargeScreenState();
}

class _ChargeScreenState extends State<ChargeScreen> {
  final channel = IOWebSocketChannel.connect('ws://192.168.4.1:81');
  List<Map<String, dynamic>> chargeData = [];
  double chargeV = 0.0;
  double chargeCurrent = 0.0;
  double capacity = 3000.0;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    channel.stream.listen(
      (data) {
        final jsonData = jsonDecode(data);
        if (jsonData['mode'] == 'charging') {
          setState(() {
            chargeV = jsonData['charge_V'].toDouble();
            chargeCurrent = jsonData['charge_current_mA'].toDouble();
            capacity = jsonData['capacity_mAh'].toDouble();
            chargeData.add({
              'timestamp': jsonData['timestamp'].toDouble(),
              'capacity': capacity,
              'voltage': chargeV,
            });
            if (chargeData.length > 50) chargeData.removeAt(0);
            isConnected = true;
          });
        }
      },
      onError: (error) {
        print('WebSocket error: $error');
        setState(() {
          isConnected = false;
        });
      },
      onDone: () {
        print('WebSocket closed');
        setState(() {
          isConnected = false;
        });
      },
    );
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContainer(String title, LineChartData chartData, Color chartColor) {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Container(
              height: 200,
              child: LineChart(
                chartData,
                duration: const Duration(milliseconds: 250),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Energy Management System'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.blueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              color: isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Text(
                'Charging Section',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatCard(
              'Charge Voltage',
              '${chargeV.toStringAsFixed(2)} V',
              Icons.battery_charging_full,
              Colors.blue,
            ),
            _buildStatCard(
              'Charge Current',
              '${chargeCurrent.toStringAsFixed(1)} mA',
              Icons.electric_bolt,
              Colors.orange,
            ),
            _buildStatCard(
              'Capacity',
              '${capacity.toStringAsFixed(0)} mAh',
              Icons.battery_std,
              Colors.green,
            ),
            const SizedBox(height: 16),
            _buildChartContainer(
              'Capacity vs Time',
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()} mAh',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()} s',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
                minX: chargeData.isNotEmpty ? chargeData.length > 50 ? chargeData.length - 50 : 0 : 0,
                maxY: 5000, // Adjust based on battery capacity
                lineBarsData: [
                  LineChartBarData(
                    spots: chargeData
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value['capacity']))
                        .toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
              Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildChartContainer(
              'Voltage vs Capacity',
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toStringAsFixed(1)} V',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()} mAh',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
                minY: 0,
                maxY: 5, // Adjust based on expected voltage range
                lineBarsData: [
                  LineChartBarData(
                    spots: chargeData
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.value['capacity'], e.value['voltage']))
                        .toList(),
                    isCurved: true,
                    color: Colors.red,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.red.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
              Colors.red,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}