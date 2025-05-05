import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:clipboard/clipboard.dart';
import 'package:flutter/services.dart'; // Import this for Clipboard
import 'settings.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomePage extends StatefulWidget {
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _apiKey = 'AIzaSyDJphM5hy_n8XDBirZLYBeI1fQytZA-V8Y';
  Database? _database;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _initDatabase().then((db) {
      _database = db;
    });
    _scheduleBackgroundScan();
  }

  Future<void> _initializeNotifications() async {
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'phishing_channel',
      'Phishing Alerts',
      description: 'Notifications for phishing threats',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<Database> _initDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/scan_history.db';
    return await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE scans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT,
          result TEXT,
          timestamp TEXT
        )
      ''');
    });
  }

  void _scheduleBackgroundScan() {
    Workmanager().registerPeriodicTask(
      "background-scan",
      "backgroundScanTask",
      frequency: Duration(minutes: 15),
      initialDelay: Duration(seconds: 10),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> performBackgroundScan() async {
    const testUrl = "http://testsafebrowsing.appspot.com/s/phishing.html";
    final result = await scanUrl(testUrl);
    if (result['isPhishing']) {
      await _showEmergencyNotification(testUrl);
      await _saveScanResult(testUrl, 'Phishing Detected');
    }
  }

  static Future<void> _showEmergencyNotification(String url) async {
    const androidDetails = AndroidNotificationDetails(
      'phishing_channel',
      'Phishing Alerts',
      channelDescription: 'Notifications for phishing threats',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      ticker: 'Phishing Alert',
      playSound: true,
      enableVibration: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Emergency Phishing Alert',
      'Critical threat detected: $url',
      notificationDetails,
    );
  }

  static Future<void> _saveScanResult(String url, String result) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/scan_history.db';
    final db = await openDatabase(path);
    await db.insert('scans', {
      'url': url,
      'result': result,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await db.close();
  }

  static Future<Map<String, dynamic>> scanUrl(String url) async {
    final safeBrowsingResult = await scanUrlWithSafeBrowsing(url);
    final checkPhishResult = await scanUrlWithCheckPhish(url);

    bool isPhishing =
        safeBrowsingResult['isPhishing'] || checkPhishResult['isPhishing'];
    String details;
    if (isPhishing) {
      List<String> threats = [];
      if (safeBrowsingResult['isPhishing']) {
        threats.add('${safeBrowsingResult['details']} (Safe Browsing)');
      }
      if (checkPhishResult['isPhishing']) {
        threats.add('${checkPhishResult['details']} (CheckPhish)');
      }
      details = 'Threat Detected: ${threats.join(', ')}';
    } else {
      details = 'Safe';
    }

    return {
      'isPhishing': isPhishing,
      'details': details,
    };
  }

  static Future<Map<String, dynamic>> scanUrlWithSafeBrowsing(
      String url) async {
    final requestBody = {
      "client": {"clientId": "cybersafeapp", "clientVersion": "1.0.0"},
      "threatInfo": {
        "threatTypes": [
          "MALWARE",
          "SOCIAL_ENGINEERING",
          "UNWANTED_SOFTWARE",
          "POTENTIALLY_HARMFUL_APPLICATION"
        ],
        "platformTypes": ["ANY_PLATFORM"],
        "threatEntryTypes": ["URL"],
        "threatEntries": [
          {"url": url}
        ]
      }
    };

    try {
      final response = await http
          .post(
        Uri.parse(
            'https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      )
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Safe Browsing request timed out');
      });

      print('Safe Browsing API Response Status: ${response.statusCode}');
      print('Safe Browsing API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        bool isPhishing =
            data.containsKey('matches') && data['matches'].isNotEmpty;
        String details = isPhishing ? data['matches'][0]['threatType'] : 'Safe';
        return {
          'isPhishing': isPhishing,
          'details': details,
        };
      } else {
        return {
          'isPhishing': false,
          'details': 'Safe Browsing Error: Status Code ${response.statusCode}',
        };
      }
    } catch (e) {
      print('Error during Safe Browsing scan: $e');
      return {
        'isPhishing': false,
        'details': 'Safe Browsing Error: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> scanUrlWithCheckPhish(String url) async {
    const String checkPhishApiKey =
        'cctv5vfjy1guzhpflkn6qbu0mi5ccsqs5k48tfnr49c09pvw78y4z30a1jgy5xwi';
    const String checkPhishUrl = 'https://api.checkphish.ai/v1/scan';

    try {
      final response = await http
          .post(
        Uri.parse(checkPhishUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $checkPhishApiKey',
        },
        body: jsonEncode({
          'url': url,
        }),
      )
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('CheckPhish request timed out');
      });

      print('CheckPhish API Response Status: ${response.statusCode}');
      print('CheckPhish API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        bool isPhishing = data['is_phishing'] ?? false;
        String details =
            isPhishing ? (data['threat_type'] ?? 'Phishing') : 'Safe';
        return {
          'isPhishing': isPhishing,
          'details': details,
        };
      } else {
        return {
          'isPhishing': false,
          'details': 'CheckPhish Error: Status Code ${response.statusCode}',
        };
      }
    } catch (e) {
      print('Error during CheckPhish scan: $e');
      return {
        'isPhishing': false,
        'details': 'CheckPhish Error: ${e.toString()}',
      };
    }
  }

  static Future<void> launchGmail(BuildContext context, String message) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: '',
      queryParameters: {
        'subject': 'CyberSafe Alert',
        'body': message,
      },
    );
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gmail or email app not installed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching Gmail: $e')),
      );
    }
  }

  static Future<void> launchOutlook(
      BuildContext context, String message) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: '',
      queryParameters: {
        'subject': 'CyberSafe Alert',
        'body': message,
      },
    );
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Outlook or email app not installed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching Outlook: $e')),
      );
    }
  }

  static Future<void> launchMessagingApp(
      BuildContext context, String message) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: '',
      queryParameters: {'body': message},
    );
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Messaging app not installed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching messaging app: $e')),
      );
    }
  }

  static Future<void> launchWhatsApp(BuildContext context, String message,
      {String? phoneNumber}) async {
    String whatsAppUrl;
    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      phoneNumber = phoneNumber.replaceAll(RegExp(r'\D'), '');
      whatsAppUrl =
          'whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}';
    } else {
      whatsAppUrl = 'whatsapp://send?text=${Uri.encodeComponent(message)}';
    }
    try {
      if (await canLaunchUrl(Uri.parse(whatsAppUrl))) {
        await launchUrl(Uri.parse(whatsAppUrl),
            mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp not installed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching WhatsApp: $e')),
      );
    }
  }

  static Future<void> launchFacebookMessenger(
      BuildContext context, String message) async {
    const String messengerUrl = 'fb-messenger://share?text=';
    try {
      if (await canLaunchUrl(
          Uri.parse(messengerUrl + Uri.encodeComponent(message)))) {
        await launchUrl(Uri.parse(messengerUrl + Uri.encodeComponent(message)),
            mode: LaunchMode.externalApplication);
      } else {
        final Uri facebookUri = Uri.parse(
            'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(facebookUri)) {
          await launchUrl(facebookUri, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Facebook Messenger or Facebook not installed')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error launching Facebook Messenger: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 40,
                errorBuilder: (context, error, stackTrace) {
              return Icon(Icons.security, size: 40);
            }),
            const SizedBox(width: 10),
            const Text("CyberSafe"),
          ],
        ),
        backgroundColor: const Color(0xFF001F3F),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AccountSettingsPage()),
              );
            },
          ),
        ],
      ),
      body: HomeContentPage(),
    );
  }
}

class HomeContentPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (user != null)
            Text(
              'Hello, ${user.email}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF001F3F),
              ),
            ),
          const SizedBox(height: 20),
          QuickScanCard(),
          const SizedBox(height: 20),
          AppScanCard(),
          const SizedBox(height: 20),
          SecuritySnapshot(),
          const SizedBox(height: 20),
          Placeholder(
            fallbackHeight: 100,
            fallbackWidth: double.infinity,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}

class QuickScanCard extends StatefulWidget {
  @override
  _QuickScanCardState createState() => _QuickScanCardState();
}

class _QuickScanCardState extends State<QuickScanCard> {
  final TextEditingController _urlController = TextEditingController();
  String _scanReport = '';
  String _indicator = '';
  bool _isScanning = false;

  Future<void> _performQuickScan(BuildContext context) async {
    if (_urlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL to scan')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanReport = 'Scanning...';
      _indicator = 'In Progress';
    });

    final url = _urlController.text.trim();
    final result = await HomePageState.scanUrl(url);

    setState(() {
      _scanReport = result['isPhishing']
          ? 'Threat Detected: ${result['details']}'
          : 'No threats found. The link appears safe.';
      _indicator = result['isPhishing'] ? 'Threat' : 'Safe';
      _isScanning = false;
    });

    if (result['isPhishing']) {
      await HomePageState._showEmergencyNotification(url);
      await HomePageState._saveScanResult(url, 'Phishing');
    } else {
      await HomePageState._saveScanResult(url, 'Safe');
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Quick Scan',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Add the link',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'Enter URL (e.g., https://example.com)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              enabled: !_isScanning,
            ),
            const SizedBox(height: 10),
            Center(
              child: ElevatedButton(
                onPressed:
                    _isScanning ? null : () => _performQuickScan(context),
                child: Text(
                  _isScanning ? 'Scanning...' : 'Start Quick Scan',
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Scan Report',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(
                  _scanReport.isEmpty ? 'No scan performed yet.' : _scanReport,
                  style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 10),
            const Text('Indicator',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5)),
              child: Text(
                _indicator.isEmpty ? 'Awaiting scan...' : _indicator,
                style: TextStyle(
                  fontSize: 14,
                  color: _indicator == 'Safe'
                      ? Colors.green
                      : _indicator == 'Threat'
                          ? Colors.red
                          : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppScanCard extends StatefulWidget {
  @override
  _AppScanCardState createState() => _AppScanCardState();
}

class _AppScanCardState extends State<AppScanCard> {
  String _scanReport = '';
  String _indicator = '';
  bool _isScanning = false;
  StreamSubscription? _intentDataStreamSubscription;
  Timer? _clipboardTimer;

  @override
  void initState() {
    super.initState();
    // Listen for shared content
    _intentDataStreamSubscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty && value.first.path != null) {
          _scanSharedContent(value.first.path);
        }
      },
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error receiving shared content: $err')),
          );
        }
      },
    );

    // Check initial shared content
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.path != null) {
        _scanSharedContent(value.first.path);
      }
    });

    // Start clipboard monitoring
    _startClipboardMonitoring();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _clipboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _scanSharedContent(String content) async {
    setState(() {
      _isScanning = true;
      _scanReport = 'Scanning shared content...';
      _indicator = 'In Progress';
    });

    // Extract URLs from content
    final urlRegExp = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    );
    final matches = urlRegExp.allMatches(content);
    String? urlToScan;

    if (matches.isNotEmpty) {
      urlToScan = matches.first.group(0);
    } else {
      setState(() {
        _scanReport = 'No URLs found in shared content.';
        _indicator = 'Safe';
        _isScanning = false;
      });
      return;
    }

    if (urlToScan != null) {
      final result = await HomePageState.scanUrl(urlToScan);

      setState(() {
        _scanReport = result['isPhishing']
            ? 'Threat Detected in shared content: ${result['details']}'
            : 'No threats found in shared content.';
        _indicator = result['isPhishing'] ? 'Threat' : 'Safe';
        _isScanning = false;
      });

      if (result['isPhishing']) {
        await HomePageState._showEmergencyNotification(urlToScan);
        await HomePageState._saveScanResult(urlToScan, 'Phishing');
      } else {
        await HomePageState._saveScanResult(urlToScan, 'Safe');
      }
    }
  }

  Future<void> _startClipboardMonitoring() async {
    _clipboardTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final clipboardData = await Clipboard.getData('text/plain');
        if (clipboardData != null && clipboardData.text != null) {
          final clipboardContent = clipboardData.text!;
          final urlRegExp = RegExp(
            r'https?://[^\s]+',
            caseSensitive: false,
          );
          final matches = urlRegExp.allMatches(clipboardContent);
          if (matches.isNotEmpty) {
            final url = matches.first.group(0)!;
            await _scanSharedContent(url);
          }
        }
      } catch (e) {
        debugPrint('Error reading clipboard: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'App Scan',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Scan content from apps',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            const Text(
              'Share a link or message from Gmail, WhatsApp, etc., to scan for threats.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scan Report',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _scanReport.isEmpty ? 'No content scanned yet.' : _scanReport,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Indicator',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _indicator.isEmpty ? 'Awaiting scan...' : _indicator,
                style: TextStyle(
                  fontSize: 14,
                  color: _indicator == 'Safe'
                      ? Colors.green
                      : _indicator == 'Threat'
                          ? Colors.red
                          : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecuritySnapshot extends StatefulWidget {
  @override
  _SecuritySnapshotState createState() => _SecuritySnapshotState();
}

class _SecuritySnapshotState extends State<SecuritySnapshot> {
  int totalScans = 0;
  int threatsDetected = 0;
  String securityStatus = "Safe";

  Future<void> performScan() async {
    setState(() {
      totalScans++;
    });

    final mockUrls = [
      "http://testsafebrowsing.appspot.com/s/phishing.html",
      "https://example.com",
    ];

    bool threatFound = false;

    for (var url in mockUrls) {
      final result = await HomePageState.scanUrl(url);
      if (result['isPhishing']) {
        threatFound = true;
        threatsDetected++;
        await HomePageState._showEmergencyNotification(url);
        await HomePageState._saveScanResult(url, 'Phishing');
      } else {
        await HomePageState._saveScanResult(url, 'Safe');
      }
    }

    setState(() {
      securityStatus = threatFound ? "At Risk" : "Secure";
    });

    if (threatFound) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threat detected during scan!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Security Snapshot',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Total Scans: $totalScans',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Threats Detected: $threatsDetected',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Security Status: $securityStatus',
              style: TextStyle(
                fontSize: 16,
                color: securityStatus == 'Secure' ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: performScan,
                child: const Text('Run Scan'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
