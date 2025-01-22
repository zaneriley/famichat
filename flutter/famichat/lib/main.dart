import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FamichatApp());
}

class FamichatApp extends StatelessWidget {
  const FamichatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Famichat Hello World',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HelloScreen(),
    );
  }
}

class HelloScreen extends StatefulWidget {
  const HelloScreen({Key? key}) : super(key: key);

  @override
  State<HelloScreen> createState() => _HelloScreenState();
}

class _HelloScreenState extends State<HelloScreen> {
  String message = 'Loading...';

  @override
  void initState() {
    super.initState();
    fetchGreeting();
  }

  Future<void> fetchGreeting() async {
    // Change this to your local IP if needed, e.g.: http://192.168.0.10:4000
    final url = Uri.parse('http://127.0.0.1:4000');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          message = response.body;
        });
      } else {
        setState(() {
          message = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        message = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Famichat Hello World'),
      ),
      body: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }
} 