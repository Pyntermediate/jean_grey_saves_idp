import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileHelper {
  static Future<bool> ensureProfileName(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    String myName = prefs.getString('my_profile_name') ?? '';
    
    if (myName.trim().isNotEmpty) return true;

    if (!context.mounted) return false;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final ctrl = TextEditingController(text: myName);
        return AlertDialog(
          title: const Text('Profile Setup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your name to use broadcasting and sync features:', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Your Profile Name', hintText: 'e.g. John Doe'),
                autofocus: true,
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save & Continue'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) return false;
    
    await prefs.setString('my_profile_name', result.trim());
    return true;
  }
}

