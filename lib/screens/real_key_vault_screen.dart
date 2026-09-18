import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/models.dart';
import '../services/contact_vault.dart';
import '../services/theme_manager.dart';
import '../widgets/neu_widgets.dart';
import 'qr_scanner_screen.dart';

class RealKeyVaultScreen extends StatefulWidget {
  const RealKeyVaultScreen({super.key});

  @override
  State<RealKeyVaultScreen> createState() => _RealKeyVaultScreenState();
}

class _RealKeyVaultScreenState extends State<RealKeyVaultScreen> {
  @override
  void initState() {
    super.initState();
    ContactVault.init().then((_) {
      if (mounted) setState(() {});
    });
    ContactVault.updateNotifier.addListener(_onVaultUpdate);
  }

  void _onVaultUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactVault.updateNotifier.removeListener(_onVaultUpdate);
    super.dispose();
  }

  Future<void> _openQrScanner() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (scannedCode == null || scannedCode.trim().isEmpty || !mounted) return;
    _handleScannedKey(scannedCode.trim());
  }

  void _handleScannedKey(String rawScanned) {
    var cleanKey = rawScanned.trim();
    if (!cleanKey.toUpperCase().startsWith('PUB_KEY_')) {
      cleanKey = 'PUB_KEY_${cleanKey.toUpperCase()}';
    } else {
      cleanKey = cleanKey.toUpperCase();
    }

    final targetHash = ContactVault.consistentHash(cleanKey) & 0xFFFF;
    final existingIndex = ContactVault.contacts.indexWhere((c) =>
        c.publicKey.trim().toUpperCase() == cleanKey ||
        (targetHash != 0 && ContactVault.matchesSender(c, targetHash)));
    final existingContact = existingIndex != -1 ? ContactVault.contacts[existingIndex] : null;

    final nameCtrl = TextEditingController(
      text: existingContact != null ? existingContact.name : '',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existingContact != null ? 'Update Contact' : 'Contact QR Scanned'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Key: ${cleanKey.length > 22 ? '${cleanKey.substring(0, 20)}...' : cleanKey}',
                style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Contact Name',
                  hintText: 'e.g. Alice, Bob',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim().isEmpty ? (existingContact?.name ?? 'Friend') : nameCtrl.text.trim();
                await ContactVault.addContact(ContactKey(
                  id: existingContact?.id ?? 'QR_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  phoneNumber: '',
                  publicKey: cleanKey,
                  isAppInstalled: true,
                  lastSynced: DateTime.now(),
                ));
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Contact "$name" added successfully!'),
                      backgroundColor: ThemeManager.accentGreen,
                    ),
                  );
                }
              },
              child: const Text('Save Contact'),
            ),
          ],
        );
      },
    );
  }

  void _showManualSyncOverlay() {
    final myKey = ContactVault.myKeyPair['publicKey'] ?? 'Generating key...';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.transparent,
            child: Center(
              child: GestureDetector(
                onTap: () {}, 
                child: Material(
                  color: Colors.transparent,
                  child: NeuContainer(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Your Public Key',
                          style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isDark ? ThemeManager.darkBorder : ThemeManager.lightBorder),
                          ),
                          child: QrImageView(
                            data: myKey,
                            version: QrVersions.auto,
                            size: 180.0,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: myKey));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Public key copied!')));
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Public Key'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Contacts',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _openQrScanner,
                      icon: const Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text('Scan Contact QR'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: ThemeManager.accentBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showManualSyncOverlay,
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: const Text('Show My QR'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              ValueListenableBuilder<int>(
                valueListenable: ContactVault.updateNotifier,
                builder: (context, _, __) {
                  final contacts = ContactVault.contacts;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Synced Contacts (${contacts.length})',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 20),
                            onPressed: () {
                              final nameCtrl = TextEditingController();
                              final keyCtrl = TextEditingController();

                              showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text('Add Contact Manually'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          controller: nameCtrl,
                                          decoration: const InputDecoration(labelText: 'Contact Name'),
                                        ),
                                        TextField(
                                          controller: keyCtrl,
                                          decoration: const InputDecoration(labelText: 'Public Key'),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          final n = nameCtrl.text.trim();
                                          var k = keyCtrl.text.trim();
                                          if (n.isNotEmpty && k.isNotEmpty) {
                                            if (!k.toUpperCase().startsWith('PUB_KEY_')) {
                                              k = 'PUB_KEY_${k.toUpperCase()}';
                                            } else {
                                              k = k.toUpperCase();
                                            }
                                            await ContactVault.addContact(ContactKey(
                                              id: 'MANUAL_${DateTime.now().millisecondsSinceEpoch}',
                                              name: n,
                                              phoneNumber: '',
                                              publicKey: k,
                                              isAppInstalled: true,
                                              lastSynced: DateTime.now(),
                                            ));
                                            if (mounted) Navigator.pop(context);
                                          }
                                        },
                                        child: const Text('Add'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (contacts.isEmpty)
                        NeuContainer(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.contacts_outlined, size: 36, color: isDark ? Colors.white24 : Colors.black26),
                                const SizedBox(height: 10),
                                Text(
                                  'No Contacts Added Yet',
                                  style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Use Auto-Sync or Manual-Sync to add friends.',
                                  style: TextStyle(fontSize: 11, color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...contacts.map((contact) {
                          final hasApp = contact.isAppInstalled;
                          return NeuContainer(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: (hasApp ? ThemeManager.accentGreen : ThemeManager.accentAmber)
                                        .withValues(alpha: 0.12),
                                  ),
                                  child: Icon(
                                    hasApp ? Icons.lock_outline : Icons.sms_outlined,
                                    color: hasApp ? ThemeManager.accentGreen : ThemeManager.accentAmber,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        contact.name,
                                        style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      if (contact.phoneNumber.isNotEmpty)
                                        Text(
                                          contact.phoneNumber,
                                          style: TextStyle(fontSize: 11, color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                                        ),
                                      Text(
                                        hasApp
                                            ? (contact.publicKey.isNotEmpty ? 'Security Key: ${contact.publicKey}' : 'Private Messaging Enabled')
                                            : 'No App • Gateway SMS Fallback',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: hasApp ? ThemeManager.accentGreen : ThemeManager.accentAmber,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 16),
                                  color: ThemeManager.accentBlue.withValues(alpha: 0.8),
                                  tooltip: 'Copy Public Key',
                                  onPressed: () {
                                    if (contact.publicKey.isNotEmpty) {
                                      Clipboard.setData(ClipboardData(text: contact.publicKey));
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Public key copied!')));
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No public key available for this contact.')));
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  color: ThemeManager.accentRed.withValues(alpha: 0.7),
                                  tooltip: 'Delete Contact',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete Contact?'),
                                        content: Text('Are you sure you want to remove ${contact.name}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            style: TextButton.styleFrom(foregroundColor: ThemeManager.accentRed),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await ContactVault.removeContact(contact.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Flare v38.39 (Build 89)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: (isDark 
                        ? ThemeManager.darkTextMuted 
                        : ThemeManager.lightTextMuted).withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
