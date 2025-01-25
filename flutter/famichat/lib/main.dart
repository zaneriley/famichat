import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const FamichatApp());
}

class FamichatApp extends StatefulWidget {
  const FamichatApp({super.key});

  @override
  State<FamichatApp> createState() => _FamichatAppState();
}

class _FamichatAppState extends State<FamichatApp> {
  String appTitle = 'Loading...';
  String apiUrl = 'http://127.0.0.1:4000/api/placeholder';

  @override
  void initState() {
    super.initState();
    _printAssetManifest();
    _loadConfig();
  }

  Future<void> _printAssetManifest() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      print('AssetManifest.json contents:\n$manifestContent');
    } catch (e) {
      print('Error loading AssetManifest.json: $e');
    }
  }

  Future<void> _loadConfig() async {
    final jsonString = await rootBundle.loadString('config/app_settings.json');
    final config = json.decode(jsonString);

    setState(() {
      appTitle = config['appTitle'] as String? ?? 'Famichat';
      apiUrl = config['apiUrl'] as String? ?? 'http://127.0.0.1:8001/api/v1/hello';
      print('API URL loaded from config: $apiUrl');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HelloScreen(apiUrl: apiUrl, title: appTitle),
    );
  }
}

class HelloScreen extends StatefulWidget {
  final String apiUrl;
  final String title;

  const HelloScreen({super.key, required this.apiUrl, required this.title});

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
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8001/api/v1/hello'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        setState(() {
          message = jsonResponse['message'] ?? 'No message received';
        });
      } else {
        setState(() {
          message = 'Error: ${response.statusCode}';
        });
      }
    } catch (e, stackTrace) {
      print('Network error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        message = 'Network error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchGreeting,
          ),
        ],
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