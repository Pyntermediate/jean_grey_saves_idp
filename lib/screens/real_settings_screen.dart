import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/theme_manager.dart';
import '../services/notification_service.dart';
import '../services/contact_vault.dart';
import '../widgets/neu_widgets.dart';

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
    if (mounted) {
      setState(() {
        _isMuleEnabled = prefs.getBool('is_mule_enabled') ?? true;
        _profileName = prefs.getString('my_profile_name') ?? 'Not Set';
        _publicKey = ContactVault.myKeyPair['publicKey'] ?? 'Generating...';
        _isBatteryOptimized = !isIgnored;
      });
    }
  }

  Future<void> _toggleMule(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_mule_enabled', value);
    setState(() {
      _isMuleEnabled = value;
    });
    if (value) {
      await NotificationService.instance.startMuleService();
      if (_isBatteryOptimized) {
        await NotificationService.instance.requestIgnoreBatteryOptimization();
        final isIgnored = await NotificationService.instance.isBatteryOptimizationIgnored();
        if (mounted) {
          setState(() {
            _isBatteryOptimized = !isIgnored;
          });
        }
      }
    } else {
      await NotificationService.instance.stopMuleService();
    }
  }

  Future<void> _editProfileName() async {
    final TextEditingController nameController = TextEditingController(text: _profileName == 'Not Set' ? '' : _profileName);
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Profile Name'),
          content: TextField(
            controller: nameController,
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
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.pop(context, nameController.text.trim());
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile name updated!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager.instance,
      builder: (context, _) {
        return AuroraBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
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
                  title: const Text('Enable Relay & 24/7 Sleep Reception'),
                  subtitle: const Text('Silently relays mesh packets and receives broadcasts while screen is locked'),
                  value: _isMuleEnabled,
                  onChanged: _toggleMule,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Dark Theme'),
                  value: ThemeManager.instance.isDarkMode,
                  onChanged: (value) => ThemeManager.instance.toggleTheme(),
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
