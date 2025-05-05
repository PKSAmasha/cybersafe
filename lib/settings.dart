import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login.dart';

class AccountSettingsPage extends StatefulWidget {
  @override
  _AccountSettingsPageState createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _notificationsEnabled = true; // State for notification toggle
  bool _darkModeEnabled = false; // State for dark mode toggle

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
        backgroundColor: const Color(0xFF001F3F), // Consistent with app theme
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Account Info Section
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001F3F),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.email, color: Color(0xFF001F3F)),
            title: Text('Email: ${user?.email ?? 'Not signed in'}'),
          ),
          const Divider(),

          // Preferences Section
          const Text(
            'Preferences',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001F3F),
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Enable Notifications'),
            value: _notificationsEnabled,
            activeColor: Colors.blue,
            onChanged: (bool value) {
              setState(() {
                _notificationsEnabled = value;
                // Add logic here to enable/disable notifications if needed
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Notifications ${_notificationsEnabled ? 'enabled' : 'disabled'}',
                    ),
                  ),
                );
              });
            },
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Enable Dark Mode'),
            value: _darkModeEnabled,
            activeColor: Colors.blue,
            onChanged: (bool value) {
              setState(() {
                _darkModeEnabled = value;
                // Update the app's theme dynamically
                final themeMode =
                    _darkModeEnabled ? ThemeMode.dark : ThemeMode.light;
                // Update the app's theme dynamically
                final theme = Theme.of(context).copyWith(
                  brightness:
                      _darkModeEnabled ? Brightness.dark : Brightness.light,
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => MaterialApp(
                      theme: theme,
                      home: AccountSettingsPage(),
                    ),
                  ),
                );
              });
            },
          ),
          const Divider(),

          // Information Section
          const Text(
            'Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001F3F),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.lock, color: Color(0xFF001F3F)),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to Privacy Policy page or show dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy Policy tapped')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: Color(0xFF001F3F)),
            title: const Text('About CyberSafe'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to About page or show dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About CyberSafe tapped')),
              );
            },
          ),
          const Divider(),

          // Sign Out Button
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              FirebaseAuth.instance.signOut().then((_) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out successfully')),
                );
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Sign Out',
              style: TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
