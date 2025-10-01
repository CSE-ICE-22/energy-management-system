import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
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
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        ),
      ),
      home: DischargeScreen(),
    );
  }
}

class DischargeScreen extends StatefulWidget {
  @override
  _DischargeScreenState createState() => _DischargeScreenState();
}

class _DischargeScreenState extends State<DischargeScreen> {
  final channel = IOWebSocketChannel.connect('ws://192.168.4.1:81');
  List<Map<String, dynamic>> dischargeData = [];
  double batteryV = 0.0;
  double loadCurrent = 0.0;
  double capacity = 3000.0;

  @override
  void initState() {
    super.initState();
    channel.stream.listen(
      (data) {
        final jsonData = jsonDecode(data);
        if (jsonData['mode'] == 'discharging') {
          setState(() {
            batteryV = jsonData['battery_V'].toDouble();
            loadCurrent = jsonData['load_current_mA'].toDouble();
            capacity = jsonData['capacity_mAh'].toDouble();
            dischargeData.add({
              'timestamp': jsonData['timestamp'].toDouble(),
              'capacity': capacity,
              'voltage': batteryV,
            });
            if (dischargeData.length > 50) dischargeData.removeAt(0);
          });
        }
      },
      onError: (error) => print('WebSocket error: $error'),
      onDone: () => print('WebSocket closed'),
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
        padding: EdgeInsets.all(16),
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
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                SizedBox(height: 4),
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
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 16),
            Container(
              height: 200,
              child: LineChart(
                chartData,
                duration: Duration(milliseconds: 250),
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
        title: Text('Energy Management System'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.blueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Text(
                'Discharging Section',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            SizedBox(height: 16),
            _buildStatCard(
              'Battery Voltage',
              '${batteryV.toStringAsFixed(2)} V',
              Icons.battery_charging_full,
              Colors.blue,
            ),
            _buildStatCard(
              'Load Current',
              '${loadCurrent.toStringAsFixed(1)} mA',
              Icons.electric_bolt,
              Colors.orange,
            ),
            _buildStatCard(
              'Capacity',
              '${capacity.toStringAsFixed(0)} mAh',
              Icons.battery_std,
              Colors.green,
            ),
            SizedBox(height: 16),
            _buildChartContainer(
              'Capacity vs Time',
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()} mAh', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()} s', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
                lineBarsData: [
                  LineChartBarData(
                    spots: dischargeData
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value['capacity']))
                        .toList(),
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
              Colors.blue,
            ),
            SizedBox(height: 16),
            _buildChartContainer(
              'Voltage vs Capacity',
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)} V', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()} mAh', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey[300]!)),
                lineBarsData: [
                  LineChartBarData(
                    spots: dischargeData
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.value['capacity'], e.value['voltage']))
                        .toList(),
                    isCurved: true,
                    color: Colors.red,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.red.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
              Colors.red,
            ),
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}