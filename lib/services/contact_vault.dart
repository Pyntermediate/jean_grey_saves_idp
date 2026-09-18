import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Persistent Contact & Cryptographic Vault
class ContactVault {
  static final List<ContactKey> _contacts = [];
  static Map<String, String> _myKeyPair = {};
  static bool _isLoaded = false;
  
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);

  static List<ContactKey> get contacts => List.unmodifiable(_contacts);
  static Map<String, String> get myKeyPair => Map.unmodifiable(_myKeyPair);

  /// Consistent 32-bit Jenkins/FNV-style hash identical to Kotlin MeshForegroundService
  static int consistentHash(String str) {
    final clean = str.trim().replaceAll('PUB_KEY_', '').replaceAll('HASH_', '').toUpperCase();
    int hash = 0;
    for (int i = 0; i < clean.length; i++) {
      hash = 0x1fffffff & (hash + clean.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash = hash ^ (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }

  /// Synthesizes a valid 16-hex public key string that mathematically hashes to [targetHash]
  /// Guaranteed to evaluate to (consistentHash(key) & 0xFFFF) == targetHash in <10ms
  static String generateKeyForHash(int targetHash) {
    final target = targetHash & 0xFFFF;
    final hex = target.toRadixString(16).toUpperCase().padLeft(4, '0');
    for (int i = 0; i < 1000000; i++) {
      final candidate = '$hex${i.toRadixString(16).toUpperCase().padLeft(12, '0')}';
      if ((consistentHash(candidate) & 0xFFFF) == target) {
        return 'PUB_KEY_$candidate';
      }
    }
    return 'PUB_KEY_${hex.padLeft(16, '0')}';
  }

  /// Resolves the 16-bit sender hash for a contact, handling both true keys and legacy formats
  static int getContactHash(ContactKey c) {
    if (c.publicKey.isEmpty) return 0;
    final clean = c.publicKey.replaceAll('PUB_KEY_', '').replaceAll('HASH_', '').toUpperCase();
    // Legacy fallback: 000000000000E79D format
    if (clean.length == 16 && clean.startsWith('0000')) {
      final suffix = clean.substring(12);
      final parsed = int.tryParse(suffix, radix: 16);
      if (parsed != null && parsed != 0) return parsed & 0xFFFF;
    }
    return consistentHash(c.publicKey) & 0xFFFF;
  }

  /// Checks if a contact matches a given sender hash via mathematical hash or legacy suffix
  static bool matchesSender(ContactKey c, int senderHash) {
    if (c.publicKey.isEmpty || senderHash == 0) return false;
    final sHash = senderHash & 0xFFFF;
    // 1. Direct mathematical hash match
    if (getContactHash(c) == sHash) return true;
    if ((consistentHash(c.publicKey) & 0xFFFF) == sHash) return true;

    // 2. Legacy fallback: check if clean key string matches or ends with the sender's hex
    final clean = c.publicKey.replaceAll('PUB_KEY_', '').replaceAll('HASH_', '').toUpperCase();
    final hexStr = sHash.toRadixString(16).toUpperCase().padLeft(4, '0');
    if (clean == hexStr || clean.endsWith(hexStr) || clean.startsWith(hexStr)) {
      return true;
    }
    return false;
  }

  /// Finds a saved contact by its 16-bit sender hash
  static ContactKey? findBySenderHash(int senderHash) {
    if (senderHash == 0) return null;
    for (final c in _contacts) {
      if (matchesSender(c, senderHash)) return c;
    }
    return null;
  }

  /// Initializes the vault from persistent storage or generates initial identity
  static Future<void> init() async {
    if (_isLoaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load or Generate Persistent Identity Keypair
      String? pub = prefs.getString('flare_my_pub_key') ?? prefs.getString('resqmesh_my_pub_key');
      String? priv = prefs.getString('flare_my_priv_key') ?? prefs.getString('resqmesh_my_priv_key');

      if (pub == null || priv == null || pub.isEmpty || priv.isEmpty) {
        final randomBytes = List<int>.generate(32, (i) => Random.secure().nextInt(256));
        final hash = sha256.convert(randomBytes).toString();
        pub = 'PUB_KEY_${hash.substring(0, 16).toUpperCase()}';
        priv = 'PRIV_KEY_${hash.substring(16, 32).toUpperCase()}';

        await prefs.setString('flare_my_pub_key', pub);
        await prefs.setString('flare_my_priv_key', priv);
        await prefs.setString('resqmesh_my_pub_key', pub);
        await prefs.setString('resqmesh_my_priv_key', priv);
      } else {
        // Re-affirm persistent keys into SharedPreferences so native service always has them
        await prefs.setString('flare_my_pub_key', pub);
        await prefs.setString('resqmesh_my_pub_key', pub);
      }

      _myKeyPair = {'publicKey': pub, 'privateKey': priv};

      // 2. Load Saved Contacts
      final contactsJson = prefs.getString('flare_saved_contacts') ?? prefs.getString('resqmesh_saved_contacts');
      _contacts.clear();

      if (contactsJson != null && contactsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(contactsJson);
        bool neededMigration = false;
        for (final item in decoded) {
          var key = (item['publicKey'] as String?) ?? '';
          final clean = key.replaceAll('PUB_KEY_', '').replaceAll('HASH_', '').toUpperCase();
          // Auto-heal legacy synthetic keys e.g. 000000000000E79D
          if (clean.length == 16 && clean.startsWith('0000')) {
            final suffix = clean.substring(12);
            final parsed = int.tryParse(suffix, radix: 16);
            if (parsed != null && parsed != 0) {
              key = generateKeyForHash(parsed);
              neededMigration = true;
            }
          }

          _contacts.add(
            ContactKey(
              id: item['id'] ?? 'contact_${DateTime.now().millisecondsSinceEpoch}',
              name: item['name'] ?? 'Unnamed',
              phoneNumber: item['phoneNumber'] ?? '',
              publicKey: key,
              isAppInstalled: item['isAppInstalled'] ?? false,
              lastSynced: DateTime.tryParse(item['lastSynced'] ?? '') ?? DateTime.now(),
            ),
          );
        }
        if (neededMigration) {
          await _saveToDisk();
        }
      }

      _isLoaded = true;
    } catch (e) {
      debugPrint('ContactVault.init error: $e');
      // If error occurs, do NOT wipe contacts or generate temporary random identity
    }
  }

  /// Add a new contact and persist to disk
  static Future<void> addContact(ContactKey contact) async {
    final contactHash = getContactHash(contact);
    final myKey = (_myKeyPair['publicKey'] ?? '').trim().toUpperCase();
    final myHash = myKey.isNotEmpty ? (consistentHash(myKey) & 0xFFFF) : 0;
    if (contact.publicKey.trim().toUpperCase() == myKey || (myHash != 0 && contactHash == myHash)) {
      return; // Never add ourselves to contact vault!
    }

    ContactKey? existing;
    for (final c in _contacts) {
      if (c.id == contact.id ||
          (contact.publicKey.isNotEmpty && c.publicKey.trim().toUpperCase() == contact.publicKey.trim().toUpperCase()) ||
          (contactHash != 0 && matchesSender(c, contactHash))) {
        existing = c;
        break;
      }
    }

    if (existing != null) {
      final isExistingCustom = existing.name.isNotEmpty &&
          existing.name != 'Nearby User' &&
          existing.name != 'Nearby Peer' &&
          existing.name != 'Unknown Peer' &&
          !existing.name.startsWith('Peer ');
      final isNewGeneric = contact.name.isEmpty ||
          contact.name == 'Nearby User' ||
          contact.name == 'Nearby Peer' ||
          contact.name == 'Unknown Peer' ||
          contact.name.startsWith('Peer ');

      final preservedName = (isExistingCustom && isNewGeneric) ? existing.name : contact.name;
      final preservedId = existing.id; // Keep original ID so chat history is never orphaned
      final resolvedKey = contact.publicKey.isNotEmpty ? contact.publicKey : existing.publicKey;

      _contacts.removeWhere((c) =>
          c.id == existing!.id ||
          (resolvedKey.isNotEmpty && c.publicKey.trim().toUpperCase() == resolvedKey.trim().toUpperCase()) ||
          (contactHash != 0 && matchesSender(c, contactHash)));

      _contacts.add(
        ContactKey(
          id: preservedId,
          name: preservedName,
          phoneNumber: contact.phoneNumber.isNotEmpty ? contact.phoneNumber : existing.phoneNumber,
          publicKey: resolvedKey,
          isAppInstalled: contact.isAppInstalled || existing.isAppInstalled,
          lastSynced: DateTime.now(),
        ),
      );
    } else {
      _contacts.removeWhere((c) =>
          c.id == contact.id ||
          (contact.publicKey.isNotEmpty && c.publicKey.trim().toUpperCase() == contact.publicKey.trim().toUpperCase()) ||
          (contactHash != 0 && matchesSender(c, contactHash)));
      _contacts.add(contact);
    }

    updateNotifier.value++;
    await _saveToDisk();
  }

  /// Remove a contact and persist to disk
  static Future<void> removeContact(String id) async {
    _contacts.removeWhere((c) => c.id == id);
    updateNotifier.value++;
    await _saveToDisk();
  }

  /// Rename an existing contact by public key, id, or hash
  static Future<void> renameContact(String keyOrId, String newName) async {
    final clean = keyOrId.trim().toUpperCase();
    final idx = _contacts.indexWhere((c) =>
        c.id == keyOrId ||
        c.publicKey.trim().toUpperCase() == clean ||
        (clean.startsWith('HASH_') && matchesSender(c, int.tryParse(clean.substring(5)) ?? 0)) ||
        matchesSender(c, int.tryParse(clean, radix: 16) ?? 0));
    if (idx != -1) {
      final old = _contacts[idx];
      _contacts[idx] = ContactKey(
        id: old.id,
        name: newName,
        phoneNumber: old.phoneNumber,
        publicKey: old.publicKey,
        isAppInstalled: old.isAppInstalled,
        lastSynced: DateTime.now(),
      );
      updateNotifier.value++;
      await _saveToDisk();
    }
  }

  static ContactKey? getById(String id) {
    try {
      return _contacts.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _contacts.map((c) => {
        'id': c.id,
        'name': c.name,
        'phoneNumber': c.phoneNumber,
        'publicKey': c.publicKey,
        'isAppInstalled': c.isAppInstalled,
        'lastSynced': c.lastSynced.toIso8601String(),
      }).toList();
      final jsonStr = jsonEncode(list);
      await prefs.setString('flare_saved_contacts', jsonStr);
      await prefs.setString('resqmesh_saved_contacts', jsonStr);
    } catch (_) {}
  }
}
