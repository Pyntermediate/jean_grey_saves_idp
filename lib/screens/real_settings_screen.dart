import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/theme_manager.dart';
import '../services/notification_service.dart';
import '../services/contact_vault.dart';

class RealSettingsScreen extends StatefulWidget {
  const RealSettingsScreen({super.key});

  @override
  State<RealSettingsScreen> createState() => _RealSettingsScreenState();
}

class _RealSettingsScreenState extends State<RealSettingsScreen> {
  bool _isMuleEnabled = true;
  bool _isBatteryOptimized = false;
  String _profileName = '';
  String _publicKey = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isIgnored = await NotificationService.instance.isBatteryOptimizationIgnored();
    setState(() {
      _isMuleEnabled = prefs.getBool('is_mule_enabled') ?? true;
      _profileName = prefs.getString('my_profile_name') ?? 'Not Set';
      _publicKey = ContactVault.myKeyPair['publicKey'] ?? 'Generating...';
      _isBatteryOptimized = !isIgnored;
    });
  }

  Future<void> _requestBatteryExemption() async {
    await NotificationService.instance.requestIgnoreBatteryOptimization();
    await Future.delayed(const Duration(milliseconds: 1000));
    final isIgnored = await NotificationService.instance.isBatteryOptimizationIgnored();
    setState(() {
      _isBatteryOptimized = !isIgnored;
    });
  }

  Future<void> _toggleMule(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_mule_enabled', value);
    setState(() {
      _isMuleEnabled = value;
    });
    if (value) {
      await NotificationService.instance.startMuleService();
    } else {
      await NotificationService.instance.stopMuleService();
    }
  }

  Future<void> _editProfileName() async {
    final TextEditingController _nameController = TextEditingController(text: _profileName == 'Not Set' ? '' : _profileName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Profile Name'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: "Enter new profile name"),
            maxLength: 20,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (_nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, _nameController.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }
    );

    if (result != null && result.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('my_profile_name', result);
      setState(() {
        _profileName = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile name updated!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            title: const Text('Profile - Name'),
            subtitle: Text(_profileName, style: const TextStyle(fontWeight: FontWeight.bold)),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: _editProfileName,
            ),
            onTap: _editProfileName,
          ),
          const Divider(),
          ListTile(
            title: const Text('Public Key - Device ID'),
            subtitle: Text(_publicKey, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _publicKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Public Key copied to clipboard!')),
                );
              },
            ),
            onTap: () {
              Clipboard.setData(ClipboardData(text: _publicKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Public Key copied to clipboard!')),
              );
            },
          ),

          const Divider(),
          SwitchListTile(
            title: const Text('Enable Relay'),
            subtitle: const Text('Silently relays packets while on'),
            value: _isMuleEnabled,
            onChanged: _toggleMule,
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              _isBatteryOptimized ? Icons.battery_alert : Icons.battery_charging_full,
              color: _isBatteryOptimized ? Colors.amber : Colors.green,
            ),
            title: const Text('24/7 Sleep Mode Reception'),
            subtitle: Text(
              _isBatteryOptimized
                  ? 'Battery is restricted by OS. Tap to set Unrestricted so messages arrive while sleeping.'
                  : 'Unrestricted — 24/7 sleep reception active',
              style: TextStyle(
                fontSize: 12,
                color: _isBatteryOptimized ? Colors.amber : Colors.green,
              ),
            ),
            trailing: _isBatteryOptimized
                ? ElevatedButton(
                    onPressed: _requestBatteryExemption,
                    child: const Text('Fix'),
                  )
                : const Icon(Icons.check_circle, color: Colors.green, size: 20),
            onTap: _requestBatteryExemption,
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Dark Theme'),
            subtitle: const Text('Enable pure black mode'),
            value: isDark,
            onChanged: (value) => ThemeManager.instance.toggleTheme(),
            activeThumbColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
