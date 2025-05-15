import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:clipboard/clipboard.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'settings.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          return HomePage();
        } else {
          return LoginPage();
        }
      },
    );
  }
}

class LoginPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            // Implement Firebase login (e.g., email/password or Google Sign-In)
          },
          child: Text('Login'),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('scans')
        .add({
      'url': url,
      'result': result,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<Map<String, dynamic>> scanUrl(String url) async {
    final safeBrowsingResult = await scanUrlWithSafeBrowsing(url);
    final checkPhishResult = await scanUrlWithCheckPhish(url);
    final bool isPhishing =
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
    final String apiKey = dotenv.env['SAFE_BROWSING_API_KEY'] ?? '';
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
            'https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$apiKey'),
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
    final String checkPhishApiKey = dotenv.env['CHECK_PHISH_API_KEY'] ?? '';
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
    User? user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 40,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.security, size: 40);
              },
            ),
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
      body: HomeContentPageDuplicate(),
    );
  }
}

class HomeContentPageDuplicate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            user != null ? 'Welcome, ${user.email}' : 'Welcome, Guest',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001F3F),
            ),
          ),
          const SizedBox(height: 20),
          TipCard(),
          const SizedBox(height: 20),
          QuickScanCard(),
          const SizedBox(height: 20),
          AppScanCard(),
          const SizedBox(height: 20),
          SecuritySnapshot(),
        ],
      ),
    );
  }
}

class TipCard extends StatefulWidget {
  @override
  _TipCardState createState() => _TipCardState();
}

class _TipCardState extends State<TipCard> {
  final List<Map<String, dynamic>> _tips = [
    {'text': 'Always verify email addresses', 'icon': Icons.email},
    {'text': 'Don\'t click on suspicious links', 'icon': Icons.link},
    {'text': 'Use two-factor authentication', 'icon': Icons.security},
    {'text': 'Be cautious with personal information', 'icon': Icons.info},
    {
      'text': 'Check for grammar and spelling errors',
      'icon': Icons.text_fields,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Cybersecurity Tip',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 10),
            CarouselSlider(
              options: CarouselOptions(
                height: 100,
                autoPlay: true,
                autoPlayInterval: Duration(seconds: 5),
                enlargeCenterPage: true,
                aspectRatio: 2.0,
                viewportFraction: 0.9,
              ),
              items: _tips.map((tip) {
                return Builder(
                  builder: (BuildContext context) {
                    return Container(
                      width: MediaQuery.of(context).size.width,
                      margin: EdgeInsets.symmetric(horizontal: 5.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tip['icon'],
                            color: Colors.blue,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tip['text'],
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ),
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

    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> value) {
      if (value.isNotEmpty && value.first.path != null) {
        _scanSharedContent(value.first.path);
      }
    });

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
  String securityStatus = "Secure"; // Changed initial value to "Secure"

  Future<void> performScan() async {
    setState(() {
      totalScans++;
    });

    final mockUrls = [
      "http://testsafebrowsing.appspot.com/s/phishing.html", // Known phishing URL
      "https://example.com", // Known safe URL
    ];

    bool threatFound = false;

    for (var url in mockUrls) {
      final result = await HomePageState.scanUrl(url);
      print('Scan result for $url: $result'); // Debug log
      if (result['isPhishing'] == true) {
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
      print('Security Status updated to: $securityStatus'); // Debug log
    });

    if (threatFound) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threat detected during scan!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        'Building SecuritySnapshot with status: $securityStatus'); // Debug log
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
