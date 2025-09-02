import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseAuth.instance.signInWithEmailAndPassword(
    email: "test@ems.com",
    password: "password123",
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Energy Management System',
      theme: ThemeData(primarySwatch: Colors.blue),
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
  final database = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> dischargeData = [];
  double batteryV = 0.0;
  double loadCurrent = 0.0;
  double capacity = 3000.0;

  @override
  void initState() {
    super.initState();
    channel.stream.listen((data) {
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
          database.child('discharging/data/${jsonData['timestamp']}').set(jsonData);
        });
      }
    });
  }

  @override
  void dispose() {
    channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Energy Management System')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Discharging Section', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Battery Voltage: ${batteryV.toStringAsFixed(2)} V'),
            Text('Load Current: ${loadCurrent.toStringAsFixed(1)} mA'),
            Text('Capacity: ${capacity.toStringAsFixed(0)} mAh'),
            SizedBox(height: 16),
            Text('Capacity vs Time', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              child: LineChart(
                LineChartData(
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dischargeData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value['capacity']))
                          .toList(),
                      isCurved: true,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text('Voltage vs Capacity', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              child: LineChart(
                LineChartData(
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: dischargeData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(e.value['capacity'], e.value['voltage']))
                          .toList(),
                      isCurved: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}