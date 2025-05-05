import 'package:flutter/material.dart';

class InfoPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const DetectedInfoPage();
  }
}

class DetectedInfoPage extends StatelessWidget {
  const DetectedInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detected Phishing Info'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Emails'),
              Tab(text: 'SMS'),
              Tab(text: 'Social Media'),
              Tab(text: 'Links'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PhishingListPage(category: 'Emails'),
            PhishingListPage(category: 'SMS'),
            PhishingListPage(category: 'Social Media'),
            PhishingListPage(category: 'Links'),
          ],
        ),
      ),
    );
  }
}

class PhishingListPage extends StatelessWidget {
  final String category;

  const PhishingListPage({super.key, required this.category});

  Future<List<PhishingAttempt>> _fetchPhishingAttempts(String category) async {
    // Simulate a network/database call
    await Future.delayed(const Duration(seconds: 2)); // Simulated delay
    return [
      // ...existing code for fetching real phishing attempts...
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PhishingAttempt>>(
      future: _fetchPhishingAttempts(category),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No phishing attempts found.'));
        } else {
          final phishingAttempts = snapshot.data!;
          return ListView.builder(
            itemCount: phishingAttempts.length,
            itemBuilder: (context, index) {
              return PhishingAttemptCard(attempt: phishingAttempts[index]);
            },
          );
        }
      },
    );
  }
}

class PhishingAttemptCard extends StatelessWidget {
  final PhishingAttempt attempt;

  const PhishingAttemptCard({super.key, required this.attempt});

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
            Text('Sender: ${attempt.sender}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Content Preview: ${attempt.contentPreview}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text('Risk Level: ${attempt.riskLevel}',
                style: TextStyle(
                    fontSize: 16, color: _getRiskColor(attempt.riskLevel))),
            const SizedBox(height: 10),
            Text(
                'Phishing Indicators: ${attempt.phishingIndicators.join(', ')}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Mark as Safe',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Report Phishing',
                      style: TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 10),
                const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRiskColor(String riskLevel) {
    if (riskLevel == 'High') {
      return Colors.red;
    } else if (riskLevel == 'Medium') {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}

class PhishingAttempt {
  final String sender;
  final String contentPreview;
  final String riskLevel;
  final List<String> phishingIndicators;
  final String category;

  PhishingAttempt({
    required this.sender,
    required this.contentPreview,
    required this.riskLevel,
    required this.phishingIndicators,
    required this.category,
  });
}
