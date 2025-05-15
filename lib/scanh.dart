import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScanHistoryPage extends StatefulWidget {
  @override
  _ScanHistoryPageState createState() => _ScanHistoryPageState();
}

class _ScanHistoryPageState extends State<ScanHistoryPage> {
  List<Map<String, dynamic>> scanHistory = [];

  @override
  void initState() {
    super.initState();
    _loadScanHistory();
  }

  Future<void> _loadScanHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to view scan history')),
        );
        return;
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('scans')
          .doc(user.uid)
          .collection('scanHistory')
          .orderBy('timestamp', descending: true)
          .get();

      setState(() {
        scanHistory = querySnapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load scan history: $e')),
      );
    }
  }

  Future<void> _clearHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to clear scan history')),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final querySnapshot = await FirebaseFirestore.instance
          .collection('scans')
          .doc(user.uid)
          .collection('scanHistory')
          .get();

      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan history cleared')),
      );
      _loadScanHistory(); // Reload to reflect the cleared state
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear scan history: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan History'),
        backgroundColor: const Color(0xFF001F3F),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadScanHistory,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear History',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History'),
                  content: const Text(
                      'Are you sure you want to clear all scan history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                _clearHistory();
              }
            },
          ),
        ],
      ),
      body: scanHistory.isEmpty
          ? const Center(
              child: Text(
                'No scan history available.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: scanHistory.length,
              itemBuilder: (context, index) {
                final history = scanHistory[index];
                final isThreat =
                    history['result']?.toString().toLowerCase() == 'phishing';
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: ListTile(
                    leading: Icon(
                      isThreat ? Icons.warning : Icons.check_circle,
                      color: isThreat ? Colors.red : Colors.green,
                    ),
                    title: Text(
                      history['url'] ?? 'Unknown URL',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Result: ${history['result'] ?? 'No result'}',
                          style: TextStyle(
                            color: isThreat ? Colors.red : Colors.black87,
                          ),
                        ),
                        Text(
                          'App: ${history['appSource'] ?? 'Unknown App'}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Date: ${history['timestamp'] ?? 'No date'}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Scan Details'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('URL: ${history['url'] ?? 'Unknown'}'),
                              Text(
                                  'Result: ${history['result'] ?? 'No result'}'),
                              Text(
                                  'App: ${history['appSource'] ?? 'Unknown App'}'),
                              Text(
                                  'Date: ${history['timestamp'] ?? 'No date'}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
