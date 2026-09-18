import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../utils/profile_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/contact_vault.dart';
import '../services/file_saver/file_saver.dart';
import '../services/real_ble_service.dart';
import '../services/theme_manager.dart';
import '../services/wifi_p2p_service.dart';

class ChatMessageItem {
  final String id;
  final String sender;
  final String text;
  final String? fileName;
  final int? fileSizeKb;
  final Uint8List? fileBytes;
  final String? filePath;
  final DateTime time;
  final bool isMe;
  final bool isEncrypted;
  final bool isSos;
  final String? transferSpeed;
  final bool isDelivered;
  final bool isSeen;

  ChatMessageItem({
    required this.id,
    required this.sender,
    required this.text,
    this.fileName,
    this.fileSizeKb,
    this.fileBytes,
    this.filePath,
    required this.time,
    required this.isMe,
    this.isEncrypted = false,
    this.isSos = false,
    this.transferSpeed,
    this.isDelivered = false,
    this.isSeen = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'text': text,
    'fileName': fileName,
    'fileSizeKb': fileSizeKb,
    'time': time.toIso8601String(),
    'isMe': isMe,
    'isEncrypted': isEncrypted,
    'isSos': isSos,
    'transferSpeed': transferSpeed,
    'isDelivered': isDelivered,
    'isSeen': isSeen,
  };

  factory ChatMessageItem.fromJson(Map<String, dynamic> json) => ChatMessageItem(
    id: json['id'],
    sender: json['sender'],
    text: json['text'],
    fileName: json['fileName'],
    fileSizeKb: json['fileSizeKb'],
    time: DateTime.parse(json['time']),
    isMe: json['isMe'],
    isEncrypted: json['isEncrypted'] ?? false,
    isSos: json['isSos'] ?? false,
    transferSpeed: json['transferSpeed'],
    isDelivered: json['isDelivered'] ?? false,
    isSeen: json['isSeen'] ?? true,
  );

  ChatMessageItem copyWith({
    String? id,
    String? sender,
    String? text,
    String? fileName,
    int? fileSizeKb,
    Uint8List? fileBytes,
    String? filePath,
    DateTime? time,
    bool? isMe,
    bool? isEncrypted,
    bool? isSos,
    String? transferSpeed,
    bool? isDelivered,
    bool? isSeen,
  }) => ChatMessageItem(
    id: id ?? this.id,
    sender: sender ?? this.sender,
    text: text ?? this.text,
    fileName: fileName ?? this.fileName,
    fileSizeKb: fileSizeKb ?? this.fileSizeKb,
    fileBytes: fileBytes ?? this.fileBytes,
    filePath: filePath ?? this.filePath,
    time: time ?? this.time,
    isMe: isMe ?? this.isMe,
    isEncrypted: isEncrypted ?? this.isEncrypted,
    isSos: isSos ?? this.isSos,
    transferSpeed: transferSpeed ?? this.transferSpeed,
    isDelivered: isDelivered ?? this.isDelivered,
    isSeen: isSeen ?? this.isSeen,
  );

  bool get isImage {
    if (fileName == null) return false;
    final ext = fileName!.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.gif');
  }
}

class RealChatScreen extends StatefulWidget {
  const RealChatScreen({super.key});

  @override
  State<RealChatScreen> createState() => _RealChatScreenState();
}

class _RealChatScreenState extends State<RealChatScreen> {
  final _ble = RealBleService.instance;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static final Map<String, DateTime> _syncPromptCooldowns = {};
  static final Set<String> _rejectedSyncKeys = {};
  static bool _isSyncDialogShowing = false;

  String _selectedContactId = 'broadcast';
  String? _attachedFileName;
  int? _attachedFileSizeKb;
  Uint8List? _attachedFileBytes;
  String? _attachedFilePath;
  bool _isSending = false;
  String? _pendingWfdMessage;
  String? _pendingWfdSenderId; // Keep track of who sent the pending file

  final List<ChatMessageItem> _messages = [];
  Map<String, String> _lastMessages = {};
  Map<String, int> _unreadCounts = {};

  Timer? _inAppNotifyDebounceTimer;
  int _inAppNotifyTotalCount = 0;
  final Set<String> _inAppNotifySenders = {};
  
  StreamSubscription? _sub;
  StreamSubscription? _transferCompleteSub;
  StreamSubscription? _sentFilesSub;
  StreamSubscription? _historySub;
  StreamSubscription? _peerSub;
  List<String> _unknownPeerIds = [];

  Future<void> _loadLastMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newMap = <String, String>{};
      final newUnreadMap = <String, int>{};
      
      final broadcastSaved = prefs.getStringList('chat_broadcast') ?? [];
      if (broadcastSaved.isNotEmpty) {
        try {
          final list = broadcastSaved.map((e) => ChatMessageItem.fromJson(jsonDecode(e))).toList();
          final lastMsg = list.last;
          final prefix = lastMsg.isMe ? 'You: ' : '${lastMsg.sender}: ';
          final content = lastMsg.text.isNotEmpty ? lastMsg.text : (lastMsg.fileName != null ? '[Attachment]' : '');
          newMap['broadcast'] = '$prefix$content';
          final unread = list.where((m) => !m.isMe && !m.isSeen).length;
          newUnreadMap['broadcast'] = unread;
        } catch (_) {}
      }
      
      for (final c in ContactVault.contacts) {
        final saved = prefs.getStringList('chat_${c.id}') ?? [];
        if (saved.isNotEmpty) {
          try {
            final list = saved.map((e) => ChatMessageItem.fromJson(jsonDecode(e))).toList();
            final lastMsg = list.last;
            final prefix = lastMsg.isMe ? 'You: ' : '${lastMsg.sender}: ';
            final content = lastMsg.text.isNotEmpty ? lastMsg.text : (lastMsg.fileName != null ? '[Attachment]' : '');
            newMap[c.id] = '$prefix$content';
            final unread = list.where((m) => !m.isMe && !m.isSeen).length;
            newUnreadMap[c.id] = unread;
          } catch (_) {}
        }
      }

      final List<String> unknownIds = [];
      final allPeerKeys = prefs.getKeys().where((k) => k.startsWith('chat_peer_')).toList();
      for (final key in allPeerKeys) {
        final peerId = key.substring(5); // e.g. 'peer_1234'
        final pHash = int.tryParse(peerId.substring(5)) ?? 0;
        final alreadyInContacts = ContactVault.contacts.any((c) =>
            ContactVault.matchesSender(c, pHash));
        
        final saved = prefs.getStringList(key) ?? [];
        if (saved.isNotEmpty) {
          if (!alreadyInContacts) {
            unknownIds.add(peerId);
          }
          try {
            final list = saved.map((e) => ChatMessageItem.fromJson(jsonDecode(e))).toList();
            final lastMsg = list.last;
            final prefix = lastMsg.isMe ? 'You: ' : '${lastMsg.sender}: ';
            final content = lastMsg.text.isNotEmpty ? lastMsg.text : (lastMsg.fileName != null ? '[Attachment]' : '');
            newMap[peerId] = '$prefix$content';
            final unread = list.where((m) => !m.isMe && !m.isSeen).length;
            newUnreadMap[peerId] = unread;
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {
          _lastMessages = newMap;
          _unreadCounts = newUnreadMap;
          _unknownPeerIds = unknownIds;
        });
      }
    } catch (_) {}
  }

  Future<void> _markConversationAsSeen(String contactId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('chat_$contactId') ?? [];
      if (saved.isNotEmpty) {
        bool modified = false;
        final updatedList = <String>[];
        for (final raw in saved) {
          try {
            final item = ChatMessageItem.fromJson(jsonDecode(raw));
            if (!item.isMe && !item.isSeen) {
              updatedList.add(jsonEncode(item.copyWith(isSeen: true).toJson()));
              modified = true;
            } else {
              updatedList.add(raw);
            }
          } catch (_) {
            updatedList.add(raw);
          }
        }
        if (modified) {
          await prefs.setStringList('chat_$contactId', updatedList);
        }
      }
      if (mounted) {
        setState(() {
          _unreadCounts[contactId] = 0;
          if (_selectedContactId == contactId) {
            for (int i = 0; i < _messages.length; i++) {
              if (!_messages[i].isMe && !_messages[i].isSeen) {
                _messages[i] = _messages[i].copyWith(isSeen: true);
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint("Error marking conversation as seen: $e");
    }
  }

  void _triggerDebouncedInAppNotification(String senderName) {
    _inAppNotifyTotalCount++;
    _inAppNotifySenders.add(senderName);

    _inAppNotifyDebounceTimer?.cancel();
    _inAppNotifyDebounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      final count = _inAppNotifyTotalCount;
      final sendersList = _inAppNotifySenders.toList();
      _inAppNotifyTotalCount = 0;
      _inAppNotifySenders.clear();

      if (count == 0) return;

      String notificationText;
      if (sendersList.length == 1) {
        final sender = sendersList.first;
        if (count == 1) {
          notificationText = 'New message from $sender';
        } else {
          notificationText = '$count new messages from $sender';
        }
      } else {
        final senderSummary = sendersList.join(', ');
        notificationText = '$count new messages from $senderSummary';
      }

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(notificationText, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('chat_$_selectedContactId') ?? [];
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(saved.map((e) => ChatMessageItem.fromJson(jsonDecode(e))));
        });
        _scrollToBottom();
      }
      _markConversationAsSeen(_selectedContactId);
    } catch (e) {
      debugPrint("Error loading messages: $e");
    }
  }

  Future<void> _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: Theme.of(ctx).cardColor,
          title: Text('Clear chat history?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ThemeManager.accentRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chat_$_selectedContactId');
    if (mounted) {
      setState(() {
        _messages.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Local chat history cleared for this conversation.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _promptAddUnknownContact(String peerId) async {
    final pHash = int.tryParse(peerId.substring(5)) ?? 0;
    final hexStr = pHash.toRadixString(16).toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    String? pubKey = prefs.getString('unknown_pubkey_$pHash');

    if (pubKey == null || pubKey.isEmpty) {
      pubKey = ContactVault.generateKeyForHash(pHash);
    } else if (!pubKey.startsWith('PUB_KEY_')) {
      pubKey = 'PUB_KEY_$pubKey';
    }
    pubKey = pubKey.toUpperCase();

    String editName = '';
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Save as Contact', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign a name for Peer #$hexStr to save them to your contact vault and establish verified two-way messaging.',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                onChanged: (val) => editName = val,
                decoration: InputDecoration(
                  labelText: 'Contact Name',
                  hintText: 'e.g. Alice, Bob',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final cleanName = editName.trim().isEmpty ? 'Contact #$hexStr' : editName.trim();
                final newContactId = 'CONTACT_${DateTime.now().millisecondsSinceEpoch}';
                final newContact = ContactKey(
                  id: newContactId,
                  name: cleanName,
                  phoneNumber: '',
                  publicKey: pubKey!,
                  isAppInstalled: true,
                  lastSynced: DateTime.now(),
                );

                await ContactVault.addContact(newContact);

                // Migrate messages from chat_peer_$pHash to chat_$newContactId
                final oldKey = 'chat_$peerId';
                final newKey = 'chat_$newContactId';
                final oldMsgs = prefs.getStringList(oldKey) ?? [];
                if (oldMsgs.isNotEmpty) {
                  await prefs.setStringList(newKey, oldMsgs);
                  await prefs.remove(oldKey);
                }

                if (ctx.mounted) Navigator.pop(ctx);

                if (mounted) {
                  setState(() {
                    _selectedContactId = newContactId;
                  });
                  _loadMessages();
                  _loadLastMessages();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Saved "$cleanName" to contacts!'),
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

  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_messages.length > 30) {
        _messages.removeRange(0, _messages.length - 30);
      }
      final toSave = _messages.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList('chat_$_selectedContactId', toSave);
      
      // Update the last message text in memory
      if (_messages.isNotEmpty) {
        final lastMsg = _messages.last;
        final prefix = lastMsg.isMe ? 'You: ' : '${lastMsg.sender}: ';
        final content = lastMsg.text.isNotEmpty ? lastMsg.text : (lastMsg.fileName != null ? '? Attachment' : '');
        _lastMessages[_selectedContactId] = '$prefix$content';
      }
    } catch (_) {}
  }

  void _onContactsChanged() {
    _loadLastMessages();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ble.init();
    WifiP2pService.instance.initialize();
    
    ContactVault.updateNotifier.addListener(_onContactsChanged);
    
    ContactVault.init().then((_) {
      _loadLastMessages();
      if (mounted) setState(() {});
    });

    _loadMessages();

    _historySub = RealBleService.messageHistoryNotifier.stream.listen((_) {
      if (mounted) {
        _loadMessages();
        _loadLastMessages();
      }
    });

    _peerSub = _ble.peerStream.listen((_) {
      if (mounted) setState(() {});
    });

    // Listen for incoming Wi-Fi Direct files
    _transferCompleteSub = WifiP2pService.instance.transferCompleteStream.listen((filePath) async {
      if (!mounted) return;
      try {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final sizeKb = (bytes.length / 1024).round();
        final fileName = filePath.split('/').last;

        final chatItem = ChatMessageItem(
          id: 'WFD_${DateTime.now().millisecondsSinceEpoch}',
          sender: 'Direct Transfer',
          text: _pendingWfdMessage ?? 'Secured File Received',
          fileName: fileName,
          fileSizeKb: sizeKb,
          fileBytes: bytes,
          filePath: filePath,
          time: DateTime.now(),
          isMe: false,
          isEncrypted: true,
          transferSpeed: 'Wi-Fi Direct (High Speed)',
        );
        _pendingWfdMessage = null; // Reset for next file

        final bool isViewingThisChat = _isChatOpen && (_pendingWfdSenderId == _selectedContactId);
        if (isViewingThisChat) {
          setState(() {
            _messages.add(chatItem.copyWith(isSeen: true));
          });
          _saveMessages();
          _scrollToBottom();
        } else {
          // Save to background storage silently
          final prefs = await SharedPreferences.getInstance();
          final targetKey = 'chat_$_pendingWfdSenderId';
          final existingJson = prefs.getStringList(targetKey) ?? [];
          existingJson.add(jsonEncode(chatItem.copyWith(isSeen: false).toJson()));
          if (existingJson.length > 30) {
            existingJson.removeRange(0, existingJson.length - 30);
          }
          await prefs.setStringList(targetKey, existingJson);
          _loadLastMessages();

          if (mounted) {
            _triggerDebouncedInAppNotification('Direct Transfer');
          }
        }
        _pendingWfdSenderId = null; // Reset
        
        // Teardown hotspot locally
        await WifiP2pService.instance.stop();
        if (mounted) {
          setState(() {
            _isSending = false;
          });
        }
      } catch (e) {
        debugPrint("File save error: $e");
      }
    });

    _sentFilesSub = WifiP2pService.instance.sentFilesStream.listen((files) async {
      if (files.isNotEmpty) {
        final lastFile = files.last;
        final receiverIds = lastFile.receiverIds;
        if (receiverIds.isNotEmpty) {
          final progress = lastFile.getProgressPercent(receiverIds.first);
          if (progress >= 100.0) {
            // Stop Wi-Fi Direct Host after file is fully sent
            await WifiP2pService.instance.stop();
            if (mounted) setState(() => _isSending = false);
          }
        }
      }
    });

    // Listen for incoming physical packets
    _sub = _ble.packetStream.listen((packet) async {
      if (!mounted) return;
      String text = packet.decryptedPayload;
      
      // Strip chat / SOS header if present
      if (text.startsWith('CHAT|')) {
        text = text.substring(5);
      }
      if (text.startsWith('SOS|')) {
        text = text.substring(4);
      }
      
      // Ignore packets sent by ourselves (already added to UI manually)
      final myPubKey = ContactVault.myKeyPair['publicKey'];
      if (myPubKey != null) {
        final myHash = (RealBleService.instance.consistentHash(myPubKey) & 0xFFFF);
        if (packet.senderHash == myHash) return;
      }
      
      // Determine the logical channel for this packet
      String? packetContactId;
      String senderName = "Unknown Peer";
      
      // Always attempt to resolve the sender from our Contact Vault (even for broadcasts)
      for (final c in ContactVault.contacts) {
        if (ContactVault.matchesSender(c, packet.senderHash)) {
          packetContactId = c.id;
          senderName = c.name;
          break;
        }
      }

      // If this is a private message from an unknown peer, allocate an ephemeral peer channel
      // and remember the sender's public key if supplied
      if (packetContactId == null && packet.mode == MessageMode.privateE2ee) {
        packetContactId = 'peer_${packet.senderHash}';
        senderName = 'Unknown (#${packet.senderHash.toRadixString(16).toUpperCase()})';
        if (packet.senderPubKey != null && packet.senderPubKey!.isNotEmpty) {
          SharedPreferences.getInstance().then((p) {
            p.setString('unknown_pubkey_${packet.senderHash}', packet.senderPubKey!);
          });
        }
      }

      // Intercept Delivery ACK first before any auto-reply or tab assignment!
      if (text.startsWith("__ACK__:")) {
        final ackIdStr = text.substring(8).trim();
        final ackInt = int.tryParse(ackIdStr);
        final myPubKey = ContactVault.myKeyPair['publicKey'];
        final myHash = myPubKey != null ? (RealBleService.instance.consistentHash(myPubKey) & 0xFFFF) : 0;

        bool matchesAck(String id) {
          if (id == ackIdStr) return true;
          final parts = id.split('_');
          if (parts.length >= 2) {
            if (parts[1] == ackIdStr) return true;
            if (ackInt != null && int.tryParse(parts[1]) == ackInt) return true;
          }
          if (parts.length >= 3 && parts[1] == 'SOS') {
            if (parts[2] == ackIdStr) return true;
            if (ackInt != null && int.tryParse(parts[2]) == ackInt) return true;
          }
          if (id == 'PKT_${ackIdStr}_$myHash' || id == 'PKT_SOS_${ackIdStr}_$myHash') return true;
          return false;
        }

        bool updated = false;
        for (int i = 0; i < _messages.length; i++) {
          if (matchesAck(_messages[i].id)) {
            _messages[i] = _messages[i].copyWith(isDelivered: true);
            updated = true;
          }
        }
        
        if (updated) {
          if (mounted) setState(() {});
          _saveMessages();
        }

        // Also ALWAYS update all chat_* keys in background SharedPreferences storage
        final prefs = await SharedPreferences.getInstance();
        final allKeys = prefs.getKeys().where((k) => k.startsWith('chat_')).toList();
        for (final key in allKeys) {
          final existingJson = prefs.getStringList(key) ?? [];
          bool keyFound = false;
          final updatedJson = existingJson.map((jsonStr) {
            try {
              final map = jsonDecode(jsonStr);
              final id = map['id']?.toString() ?? '';
              if (matchesAck(id) && map['isDelivered'] != true) {
                map['isDelivered'] = true;
                keyFound = true;
                return jsonEncode(map);
              }
            } catch (_) {}
            return jsonStr;
          }).toList();
          if (keyFound) {
            await prefs.setStringList(key, updatedJson);
          }
        }
        return;
      }

      // Check if it belongs to the CURRENT open tab
      // Private goes to the specific contact tab. Broadcast goes to the broadcast tab.
      bool isForCurrentTab = false;
      if (_isChatOpen) {
        if (packet.mode == MessageMode.privateE2ee) {
          isForCurrentTab = (packetContactId == _selectedContactId);
        } else {
          isForCurrentTab = (_selectedContactId == 'broadcast');
        }
      }

      // Auto-reply with an ACK to confirm delivery for both private and broadcast messages!
      final isAck = text.startsWith('__ACK__:');
      if (!isAck) {
        final myPubKey = ContactVault.myKeyPair['publicKey'];
        final myHash = myPubKey != null ? (RealBleService.instance.consistentHash(myPubKey) & 0xFFFF) : 0;

        if (packet.senderHash != myHash) {
          int msgId = 1;
          final parts = packet.packetId.split('_');
          if (parts.length >= 3 && parts[1] == 'SOS') {
            msgId = int.tryParse(parts[2]) ?? 1;
          } else if (parts.length >= 2) {
            msgId = int.tryParse(parts[1]) ?? 1;
          }

          // Piggyback onto periodic heartbeat (redundant backup ACK every 4s)
          _ble.recordLastReceivedMsgId(msgId);
        }
      }

      // Intercept Contact Sync
      if (text.startsWith("CONTACT_SYNC|") || text.startsWith("SYNC|")) {
        final parts = text.split('|');
        if (parts.length >= 3) {
          final peerName = parts[1].trim();
          var peerPubKey = parts[2].trim().replaceAll('\u0000', '');
          
          if (!peerPubKey.startsWith('PUB_KEY_')) {
            peerPubKey = 'PUB_KEY_$peerPubKey';
          }
          
          final cleanPeerKey = peerPubKey.toUpperCase();
          final myKey = (ContactVault.myKeyPair['publicKey'] ?? '').trim().replaceAll('\u0000', '').toUpperCase();
          
          // 1. Strictly ignore our own auto sync request
          if (myKey.isNotEmpty && cleanPeerKey == myKey) return;
          
          // 2. Ignore if user previously rejected this contact
          if (_rejectedSyncKeys.contains(cleanPeerKey)) return;

          // 3. Ignore if contact is already saved with an official custom name (show feedback instead of silence)
          final existing = ContactVault.contacts.where((c) => c.publicKey.trim().toUpperCase() == cleanPeerKey).firstOrNull;
          if (existing != null && existing.name != 'Nearby Peer' && existing.name != 'Nearby User' && existing.name != 'Unknown Peer') {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Contact "${existing.name}" is already synced & connected.'),
                  backgroundColor: ThemeManager.accentGreen,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return;
          }

          // 4. Rate-limit dialog to once per 20 seconds, and do not stack dialogs
          if (_isSyncDialogShowing) return;
          final now = DateTime.now();
          final lastPrompt = _syncPromptCooldowns[cleanPeerKey];
          if (lastPrompt != null && now.difference(lastPrompt).inSeconds < 20) {
            return;
          }
          _syncPromptCooldowns[cleanPeerKey] = now;
          _isSyncDialogShowing = true;

          if (mounted) {
            String editName = peerName.isEmpty ? 'Nearby User' : peerName;
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (ctx) {
                return StatefulBuilder(
                  builder: (context, setDialogState) {
                    return AlertDialog(
                      title: const Text('Incoming Contact Sync'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'A nearby device is sharing their contact card with you.',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            initialValue: editName,
                            onChanged: (val) => editName = val,
                            decoration: InputDecoration(
                              labelText: 'Contact Name:',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            _rejectedSyncKeys.add(cleanPeerKey);
                            Navigator.pop(ctx);
                          }, 
                          child: const Text('Dismiss', style: TextStyle(color: Colors.grey))
                        ),
                        FilledButton(
                          onPressed: () async {
                            final finalName = editName.trim().isEmpty ? 'Nearby User' : editName.trim();
                            final exists = ContactVault.contacts.any((c) => c.publicKey.trim().toUpperCase() == cleanPeerKey);
                            if (exists) {
                              await ContactVault.renameContact(cleanPeerKey, finalName);
                            } else {
                              await ContactVault.addContact(ContactKey(
                                id: 'SYNC_${DateTime.now().millisecondsSinceEpoch}',
                                name: finalName,
                                phoneNumber: '',
                                publicKey: cleanPeerKey,
                                isAppInstalled: true,
                                lastSynced: DateTime.now(),
                              ));
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Saved contact: $finalName'),
                                  backgroundColor: ThemeManager.accentGreen,
                                ),
                              );
                              setState(() {});
                            }
                            if (ctx.mounted) Navigator.pop(ctx);

                            // Send our contact card back so sender also receives our card
                            RealBleService.instance.sendReciprocalSyncCard();
                          },
                          child: const Text('Save Contact'),
                        ),
                      ],
                    );
                  },
                );
              }
            ).whenComplete(() {
              _isSyncDialogShowing = false;
            });
          } else {
            _isSyncDialogShowing = false;
          }
        }
        return;
      }

      // Intercept Wi-Fi Direct Handshake
      if (text.startsWith("WFD|")) {
        final parts = text.split('|');
        if (parts.length >= 3) {
          final ssid = parts[1];
          final psk = parts[2];
          if (parts.length > 3) {
            _pendingWfdMessage = parts.sublist(3).join('|');
          }
          final actualTargetId = (packet.mode == MessageMode.privateE2ee) ? packetContactId : 'broadcast';
          _pendingWfdSenderId = actualTargetId; // Track which channel the file belongs to!
          try {
            await WifiP2pService.instance.connectToHost(ssid, psk);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Connecting to high-speed file transfer...')),
              );
            }
          } catch (e) {
            // Handled inside connectToHost
          }
        }
        return;
      }

      final chatItem = ChatMessageItem(
        id: packet.packetId,
        sender: senderName,
        text: text,
        time: packet.receivedTime,
        isMe: false,
        isEncrypted: packet.mode == MessageMode.privateE2ee,
        isSos: packet.mode == MessageMode.publicSos || packet.mode == MessageMode.hybridSos,
        transferSpeed: '${packet.transmissionSpeedLabel} (${packet.phyMode.name})',
        isDelivered: true,
        isSeen: isForCurrentTab,
      );

      bool isSameMessage(String existingId, String newId) {
        if (existingId == newId) return true;
        if ((existingId.startsWith('PKT_GPS_') && newId.startsWith('PKT_SOS_')) ||
            (existingId.startsWith('PKT_SOS_') && newId.startsWith('PKT_GPS_'))) {
          final p1 = existingId.split('_');
          final p2 = newId.split('_');
          if (p1.length >= 4 && p2.length >= 4) {
            return p1[2] == p2[2] && p1[3] == p2[3];
          }
        }
        return false;
      }

      if (isForCurrentTab) {
        // If message already exists with this packetId or matching msgId, update it (e.g. SOS note replacing short beacon text)
        final existingIdx = _messages.indexWhere((m) => isSameMessage(m.id, packet.packetId));
        if (existingIdx != -1) {
          if (text.length > _messages[existingIdx].text.length) {
            _messages[existingIdx] = _messages[existingIdx].copyWith(text: text, id: packet.packetId);
            setState(() {});
            _saveMessages();
          }
          return;
        }

        setState(() {
          _messages.add(chatItem);
        });
        _saveMessages();
        _scrollToBottom();
      } else {
        // Save to background storage silently
        final prefs = await SharedPreferences.getInstance();
        final actualTargetId = (packet.mode == MessageMode.privateE2ee) ? packetContactId : 'broadcast';
        final targetKey = 'chat_$actualTargetId';
        final existingJson = prefs.getStringList(targetKey) ?? [];

        // Check if message with this id or matching msgId is already in storage
        bool found = false;
        final updatedJson = existingJson.map((jsonStr) {
          try {
            final map = jsonDecode(jsonStr);
            final oldId = map['id']?.toString() ?? '';
            if (isSameMessage(oldId, packet.packetId)) {
              found = true;
              final oldText = map['text']?.toString() ?? '';
              if (text.length > oldText.length) {
                map['text'] = text;
                map['id'] = packet.packetId;
                return jsonEncode(map);
              }
            }
          } catch (_) {}
          return jsonStr;
        }).toList();

        if (found) {
          await prefs.setStringList(targetKey, updatedJson);
          return;
        }

        existingJson.add(jsonEncode(chatItem.toJson()));
        if (existingJson.length > 30) {
          existingJson.removeRange(0, existingJson.length - 30);
        }
        await prefs.setStringList(targetKey, existingJson);
        _loadLastMessages();
        
        // Notify User with debounced consolidation
        if (mounted) {
          final alertSender = (packet.mode == MessageMode.publicSos || (packet.mode == MessageMode.publicChat && packetContactId == null))
              ? 'Broadcast'
              : senderName;
          _triggerDebouncedInAppNotification(alertSender);
        }
      }
    });
  }

  @override
  void dispose() {
    _inAppNotifyDebounceTimer?.cancel();
    ContactVault.updateNotifier.removeListener(_onContactsChanged);
    _msgController.dispose();
    _scrollController.dispose();
    _sub?.cancel();
    _transferCompleteSub?.cancel();
    _sentFilesSub?.cancel();
    _historySub?.cancel();
    _peerSub?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    String text = _msgController.text.trim();
    if (text.isEmpty && _attachedFileName == null) return;

    setState(() => _isSending = true);

    final contact = ContactVault.getById(_selectedContactId);
    final isPrivate = contact?.isAppInstalled ?? false;
    final mode = isPrivate ? MessageMode.privateE2ee : MessageMode.publicChat;

    if (!isPrivate) {
      final hasProfile = await ProfileHelper.ensureProfileName(context);
      if (!hasProfile) {
        setState(() => _isSending = false);
        return;
      }
    }

    final currentFilePath = _attachedFilePath;
    final currentFileName = _attachedFileName;
    final currentFileSizeKb = _attachedFileSizeKb;
    final currentFileBytes = _attachedFileBytes;


    try {
      String? msgId;
      final prefs = await SharedPreferences.getInstance();
      final isWifi = prefs.getBool('prefer_wifi_direct') ?? false;
      final isHost = WifiP2pService.instance.isHostMode;
      final isClient = WifiP2pService.instance.isClientMode;
      final isWifiDirectConnected = isHost || isClient;
      final shouldWifiDirect = currentFilePath != null;

      if (shouldWifiDirect) {
        // 1. Setup Wi-Fi Direct Host for File / Image Transfer
        final handshake = await WifiP2pService.instance.startHosting();
        if (handshake != null && handshake.startsWith("WFD|")) {
          final payload = text.isNotEmpty ? "$handshake|$text" : handshake;
          final result = await _ble.broadcastChatMessage(
            mode: mode,
            text: payload,
            phy: _ble.activePhyMode,
            targetContactId: isPrivate ? _selectedContactId : null,
          );
          
          if (result != null && !result.startsWith('PKT_')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('BLE WFD Broadcast Error: $result'),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                duration: const Duration(seconds: 10),
              ));
              setState(() => _isSending = false);
            }
            await WifiP2pService.instance.stop();
            return;
          }
          if (result != null && result.startsWith('PKT_')) {
            msgId = result;
          }
          
          final handshakeParts = handshake.split('|');
          final targetSsid = handshakeParts.length >= 2 ? handshakeParts[1] : "Wi-Fi Direct";

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Waiting for peer to join $targetSsid...'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              duration: const Duration(seconds: 10),
            ));
          }
          
          try {
            await WifiP2pService.instance.waitForClient();
            // Stage the file on the Wi-Fi local server
            await WifiP2pService.instance.sendFile(File(currentFilePath));
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('File beaming...'),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
              ));
            }
          } catch (e) {
            await WifiP2pService.instance.stop();
            if (mounted) setState(() => _isSending = false);
            return;
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed: ${handshake?.replaceAll("ERROR|", "") ?? "Unknown Error"}'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ));
            setState(() => _isSending = false);
          }
          return;
        }
      } else {
        // Fast & Silent Bluetooth Mesh Text Message
        if (isWifi && isWifiDirectConnected && isPrivate) {
          WifiP2pService.instance.sendText('CHAT|$text');
          msgId = 'PKT_WIFI_${DateTime.now().millisecondsSinceEpoch}';
        } else {
          final result = await _ble.broadcastChatMessage(
            mode: mode,
            text: text,
            phy: _ble.activePhyMode,
            targetContactId: isPrivate ? _selectedContactId : null,
          );
          if (result != null && result.startsWith('PKT_')) {
            msgId = result;
          }
        }
      }


      if (mounted) {
        setState(() {
          _isSending = false;
          _messages.add(
            ChatMessageItem(
              id: msgId ?? 'MSG_${DateTime.now().millisecondsSinceEpoch}',
              sender: 'You',
              text: text,
              fileName: currentFileName,
              fileSizeKb: currentFileSizeKb,
              fileBytes: currentFileBytes,
              filePath: currentFilePath,
              time: DateTime.now(),
              isMe: true,
              isEncrypted: isPrivate,
              transferSpeed: _ble.activePhyMode.speedLabel,
              isDelivered: false,
            ),
          );
          _msgController.clear();
          _attachedFileName = null;
          _attachedFileSizeKb = null;
          _attachedFilePath = null;
          _attachedFileBytes = null;
        });
        _saveMessages();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error sending message: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        ));
      }
    }
  }

  Future<void> _resendMessage(ChatMessageItem msg) async {
    if (_isSending) return;

    int? customMsgId;
    final parts = msg.id.split('_');
    if (parts.length >= 2) {
      customMsgId = int.tryParse(parts[1]);
    }

    final isPrivate = _selectedContactId != 'broadcast';
    final mode = isPrivate ? MessageMode.privateE2ee : MessageMode.hybridSos;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resending message...'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    try {
      await _ble.broadcastChatMessage(
        mode: mode,
        text: msg.text,
        phy: _ble.activePhyMode,
        targetContactId: isPrivate ? _selectedContactId : null,
        customMsgId: customMsgId,
      );
    } catch (e) {
      debugPrint("Error resending message: $e");
    }
  }

  Future<void> _cancelSending() async {
    try {
      await WifiP2pService.instance.stop();
    } catch (_) {}
    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _pickRealFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final sizeInKb = (file.size > 0) ? (file.size / 1024).round() : 1;

        setState(() {
          _attachedFileName = file.name;
          _attachedFileSizeKb = sizeInKb;
          _attachedFileBytes = file.bytes;
          _attachedFilePath = file.path;
        });

      }
    } catch (e) {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );
        if (result != null && result.files.isNotEmpty) {
          final file = result.files.first;
          final sizeInKb = (file.size > 0) ? (file.size / 1024).round() : 1;
          setState(() {
            _attachedFileName = file.name;
            _attachedFileSizeKb = sizeInKb;
            _attachedFileBytes = file.bytes;
            _attachedFilePath = file.path;
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _saveRealFile(ChatMessageItem msg) async {
    if (msg.fileName == null) return;

    final success = await saveFileToDisk(msg.fileName!, msg.fileBytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? ThemeManager.accentGreen : ThemeManager.accentAmber,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              Icon(success ? Icons.check_circle_outline : Icons.file_download, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success
                      ? 'Downloaded "${msg.fileName}" to your device!'
                      : 'Saving "${msg.fileName}" to downloads…',
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _openFileViewer(ChatMessageItem msg) {
    if (msg.fileName == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        return Dialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        msg.fileName!,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Text(
                  'Size: ${msg.fileSizeKb} KB · Transferred Offline via Direct Radio',
                  style: TextStyle(fontSize: 11, color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                ),
                const SizedBox(height: 12),
                if (msg.isImage && msg.fileBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      width: double.infinity,
                      color: isDark ? Colors.black26 : Colors.black12,
                      child: Image.memory(
                        msg.fileBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.insert_drive_file, size: 48, color: ThemeManager.accentBlue),
                        const SizedBox(height: 8),
                        Text(
                          msg.fileName!,
                          style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        Text(
                          '${msg.fileSizeKb} KB',
                          style: TextStyle(fontSize: 11, color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close', style: TextStyle(color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _saveRealFile(msg);
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('Save / Download File'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeManager.accentBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isChatOpen = false;
  String _contactSearchQuery = '';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isChatOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isChatOpen) {
          _markConversationAsSeen(_selectedContactId);
          _loadLastMessages();
          setState(() {
            _isChatOpen = false;
          });
        }
      },
      child: !_isChatOpen ? _buildContactsList() : _buildChatView(),
    );
  }

  Widget _buildContactsList() {
    final theme = Theme.of(context);
    
    final contacts = ContactVault.contacts.where((c) {
      if (_contactSearchQuery.isEmpty) return true;
      return c.name.toLowerCase().contains(_contactSearchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Messages',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (val) {
                      setState(() => _contactSearchQuery = val);
                    },
                    style: GoogleFonts.spaceGrotesk(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search contacts...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (_contactSearchQuery.isEmpty)
                    _buildContactTile(
                      id: 'broadcast',
                      name: 'Broadcast to All Nearby',
                      icon: Icons.cell_tower,
                      color: ThemeManager.accentBlue,
                    ),
                  if (_unknownPeerIds.isNotEmpty && _contactSearchQuery.isEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.help_outline_rounded, size: 14, color: Colors.orange),
                          SizedBox(width: 6),
                          Text(
                            'UNKNOWN CONVERSATIONS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._unknownPeerIds.map((pId) {
                      final pHash = int.tryParse(pId.substring(5)) ?? 0;
                      final hexStr = pHash.toRadixString(16).toUpperCase();
                      return _buildContactTile(
                        id: pId,
                        name: 'Unknown Peer (#$hexStr)',
                        icon: Icons.person_outline_rounded,
                        color: Colors.orange,
                        badgeLabel: 'UNKNOWN',
                        onDelete: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('chat_$pId');
                          await prefs.remove('unknown_pubkey_$pHash');
                          _loadLastMessages();
                        },
                      );
                    }),
                  ],
                  if (_contactSearchQuery.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('CONTACTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ThemeManager.accentSlate)),
                    ),
                  ...contacts.map((c) {
                    return _buildContactTile(
                      id: c.id,
                      name: c.name,
                      icon: Icons.person,
                      color: ThemeManager.accentGreen,
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile({
    required String id,
    required String name,
    required IconData icon,
    required Color color,
    String? badgeLabel,
    VoidCallback? onDelete,
  }) {
    final theme = Theme.of(context);
    final lastMsg = _lastMessages[id] ?? 'Tap to chat';
    final unreadCount = _unreadCounts[id] ?? 0;
    final hasUnread = unreadCount > 0;
    
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          name, 
          style: GoogleFonts.spaceGrotesk(
            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.bold, 
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            lastMsg.replaceAll('\n', ' '), 
            style: TextStyle(
              fontSize: 13, 
              color: hasUnread 
                  ? theme.colorScheme.onSurface 
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeLabel != null)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            if (hasUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ThemeManager.accentBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                tooltip: 'Dismiss conversation',
                onPressed: onDelete,
              ),
          ],
        ),
        onTap: () {
          _markConversationAsSeen(id);
          _ble.startScanning().then((_) {
            if (mounted) setState(() {});
          });
          setState(() {
            _selectedContactId = id;
            _isChatOpen = true;
          });
          _loadMessages();
        },
      ),
    );
  }

  Widget _buildChatView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    String chatTitle = 'Broadcast to All';
    String? presenceSubtitle;
    Color presenceColor = ThemeManager.accentSlate;
    bool isContactOnline = false;

    if (_selectedContactId != 'broadcast') {
      final c = ContactVault.getById(_selectedContactId);
      if (c != null) {
        chatTitle = c.name;
        if (c.publicKey.isNotEmpty) {
          final cHash = ContactVault.getContactHash(c);
          final peer = _ble.discoveredPeers.firstWhere(
            (p) => p.senderHash == cHash || ContactVault.matchesSender(c, p.senderHash),
            orElse: () => RealPeerNode(
              senderHash: 0,
              deviceAddress: '',
              lastRssi: -99,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
              phyMode: BlePhyMode.standard1M,
            ),
          );
          if (peer.senderHash != 0) {
            final diffSec = DateTime.now().difference(peer.lastSeen).inSeconds;
            if (diffSec <= 90) {
              isContactOnline = true;
              final strength = peer.lastRssi >= -65 ? 'Strong' : (peer.lastRssi >= -85 ? 'Moderate' : 'Weak');
              presenceSubtitle = 'Online · $strength (${peer.lastRssi} dBm)';
              presenceColor = ThemeManager.accentGreen;
            } else {
              final agoStr = diffSec >= 3600
                  ? '${diffSec ~/ 3600}h ago'
                  : (diffSec >= 60 ? '${diffSec ~/ 60}m ago' : '${diffSec}s ago');
              presenceSubtitle = 'Offline · Last seen $agoStr';
              presenceColor = isDark ? Colors.white38 : Colors.black38;
            }
          } else {
            presenceSubtitle = 'Offline';
            presenceColor = isDark ? Colors.white38 : Colors.black38;
          }
        }
      } else if (_selectedContactId.startsWith('peer_')) {
        final pHash = int.tryParse(_selectedContactId.substring(5)) ?? 0;
        final hexStr = pHash.toRadixString(16).toUpperCase();
        chatTitle = 'Unknown Peer (#$hexStr)';

        final peer = _ble.discoveredPeers.firstWhere(
          (p) => p.senderHash == pHash,
          orElse: () => RealPeerNode(
            senderHash: 0,
            deviceAddress: '',
            lastRssi: -99,
            lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
            phyMode: BlePhyMode.standard1M,
          ),
        );
        if (peer.senderHash != 0) {
          final diffSec = DateTime.now().difference(peer.lastSeen).inSeconds;
          if (diffSec <= 90) {
            isContactOnline = true;
            final strength = peer.lastRssi >= -65 ? 'Strong' : (peer.lastRssi >= -85 ? 'Moderate' : 'Weak');
            presenceSubtitle = 'Online · $strength (${peer.lastRssi} dBm)';
            presenceColor = ThemeManager.accentGreen;
          } else {
            final agoStr = diffSec >= 3600
                ? '${diffSec ~/ 3600}h ago'
                : (diffSec >= 60 ? '${diffSec ~/ 60}m ago' : '${diffSec}s ago');
            presenceSubtitle = 'Offline · Last seen $agoStr';
            presenceColor = isDark ? Colors.white38 : Colors.black38;
          }
        } else {
          presenceSubtitle = 'Offline';
          presenceColor = isDark ? Colors.white38 : Colors.black38;
        }
      }
    } else {
      presenceSubtitle = 'Mesh Broadcast Channel';
      presenceColor = ThemeManager.accentBlue;
    }

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        body: SafeArea(
        child: Column(
          children: [
            // ── Top Header Bar ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      _markConversationAsSeen(_selectedContactId);
                      _loadLastMessages();
                      setState(() => _isChatOpen = false);
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chatTitle,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (presenceSubtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Row(
                              children: [
                                if (isContactOnline)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      color: ThemeManager.accentGreen,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  presenceSubtitle,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    fontWeight: isContactOnline ? FontWeight.w600 : FontWeight.normal,
                                    color: presenceColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_selectedContactId.startsWith('peer_'))
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
                      color: Colors.orange,
                      tooltip: 'Save to Contacts',
                      onPressed: () => _promptAddUnknownContact(_selectedContactId),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 22),
                    color: ThemeManager.accentRed.withValues(alpha: 0.8),
                    tooltip: 'Clear Chat History',
                    onPressed: _clearChatHistory,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_ble.isScanning ? ThemeManager.accentGreen : ThemeManager.accentSlate)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_ble.isScanning ? ThemeManager.accentGreen : ThemeManager.accentSlate)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bluetooth,
                          size: 13,
                          color: _ble.isScanning ? ThemeManager.accentGreen : ThemeManager.accentSlate,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _ble.isScanning ? 'READY' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _ble.isScanning ? ThemeManager.accentGreen : ThemeManager.accentSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedContactId.startsWith('peer_'))
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unknown Peer · Add to contacts to verify & reply securely',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => _promptAddUnknownContact(_selectedContactId),
                      child: const Text('Add Contact', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),

            // --- WFD Progress Bar ---
            StreamBuilder<String>(
              stream: WifiP2pService.instance.connectionStatusStream,
              builder: (ctx, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final msg = snap.data!;
                if (msg == "Disconnected.") return const SizedBox.shrink();
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: ThemeManager.accentBlue.withValues(alpha: 0.1),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi, size: 16, color: ThemeManager.accentBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(msg, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: ThemeManager.accentBlue)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: ThemeManager.accentBlue),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Dismiss',
                        onPressed: () {
                          WifiP2pService.instance.clearStatus();
                        },
                      ),
                    ],
                  ),
                );
              }
            ),
            StreamBuilder<FileDownloadProgressUpdate>(
              stream: WifiP2pService.instance.transferProgressStream,
              builder: (ctx, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final prog = snap.data!;
                if (prog.progressPercent >= 100) return const SizedBox.shrink();

                final mbps = (prog.bytesDownloaded / 1024 / 1024).toStringAsFixed(1);
                final total = (prog.totalSize / 1024 / 1024).toStringAsFixed(1);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Receiving...', style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                          Text('$mbps MB / $total MB', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: ThemeManager.accentBlue)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: prog.progressPercent / 100,
                        backgroundColor: ThemeManager.accentBlue.withValues(alpha: 0.2),
                        color: ThemeManager.accentBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                );
              }
            ),
            StreamBuilder<List<HostedFileInfo>>(
              stream: WifiP2pService.instance.sentFilesStream,
              builder: (ctx, snap) {
                if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                final file = snap.data!.last;
                if (file.receiverIds.isEmpty) return const SizedBox.shrink();
                
                final recId = file.receiverIds.first;
                final progressPercent = file.getProgressPercent(recId);
                if (progressPercent >= 100 || progressPercent == 0) return const SizedBox.shrink();

                final bytesSent = (file.info.size * (progressPercent / 100)).toInt();
                final mbps = (bytesSent / 1024 / 1024).toStringAsFixed(1);
                final total = (file.info.size / 1024 / 1024).toStringAsFixed(1);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Sending...', style: GoogleFonts.spaceGrotesk(fontSize: 11)),
                          Text('$mbps MB / $total MB', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: ThemeManager.accentBlue)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: progressPercent / 100,
                        backgroundColor: ThemeManager.accentBlue.withValues(alpha: 0.2),
                        color: ThemeManager.accentBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                );
              }
            ),

            // ── Message Stream List ──────────────────────────────────────────
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No Offline Messages Yet',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isNewDay = index == 0 || 
                            _messages[index].time.day != _messages[index - 1].time.day ||
                            _messages[index].time.month != _messages[index - 1].time.month ||
                            _messages[index].time.year != _messages[index - 1].time.year;
                            
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isNewDay) _buildDateHeader(msg.time),
                            _buildMessageBubble(msg),
                          ],
                        );
                      },
                    ),
            ),

            // ── Prominent Selected File Attachment Box ────────────────────────
            if (_attachedFileName != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeManager.accentBlue, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black26 : const Color(0xFF64748B).withValues(alpha: 0.1),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: ThemeManager.accentBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        (_attachedFileName!.toLowerCase().endsWith('.jpg') ||
                                _attachedFileName!.toLowerCase().endsWith('.jpeg') ||
                                _attachedFileName!.toLowerCase().endsWith('.png'))
                            ? Icons.image
                            : Icons.attach_file,
                        color: ThemeManager.accentBlue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _attachedFileName!,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$_attachedFileSizeKb KB · Ready to send offline',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: ThemeManager.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 20),
                      color: ThemeManager.accentRed,
                      tooltip: 'Remove Attachment',
                      onPressed: () => setState(() {
                        _attachedFileName = null;
                        _attachedFileSizeKb = null;
                        _attachedFileBytes = null;
                        _attachedFilePath = null;
                      }),
                    ),
                  ],
                ),
              ),

            // ── Message Input Bar ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Attachment button (Native device file & photo picker)
                  IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
                    tooltip: 'Attach Photo / File',
                    onPressed: _pickRealFile,
                    color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: GoogleFonts.spaceGrotesk(fontSize: 13, color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: 'Type offline message…',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send Button
                  _isSending
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(ThemeManager.accentRed),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: ThemeManager.accentRed, size: 20),
                              onPressed: _cancelSending,
                              tooltip: 'Cancel Transfer',
                            ),
                          ],
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded, color: ThemeManager.accentBlue),
                          onPressed: _sendMessage,
                          tooltip: 'Send Message',
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    String dateString;
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      dateString = 'Today';
    } else if (date.year == now.year && date.month == now.month && date.day == now.day - 1) {
      dateString = 'Yesterday';
    } else {
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dateString = '${months[date.month - 1]} ${date.day}, ${date.year}';
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          dateString,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessageItem msg) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: msg.isMe ? ThemeManager.accentBlue : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(16),
          border: msg.isMe ? null : Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.25) : const Color(0xFF64748B).withValues(alpha: 0.06),
              offset: const Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!msg.isMe && msg.isSos)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: ThemeManager.accentRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: ThemeManager.accentRed.withValues(alpha: 0.5)),
                ),
                child: const Text(
                  'SOS',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: ThemeManager.accentRed,
                  ),
                ),
              ),
            if (msg.fileName != null) ...[
              InkWell(
                onTap: () => _openFileViewer(msg),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (msg.isMe ? Colors.white : Colors.black).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.isImage && msg.fileBytes != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            msg.fileBytes!,
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            msg.isImage ? Icons.image : Icons.insert_drive_file_outlined,
                            size: 16,
                            color: msg.isMe ? Colors.white : ThemeManager.accentBlue,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${msg.fileName} (${msg.fileSizeKb} KB)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: msg.isMe ? Colors.white : theme.colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new,
                            size: 13,
                            color: msg.isMe ? Colors.white70 : ThemeManager.accentBlue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (msg.text.isNotEmpty)
              SelectableText(
                msg.text,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: msg.isMe ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.isMe && msg.isDelivered) ...[
                  const Icon(
                    Icons.done, 
                    size: 14, 
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                ],
                if (msg.isMe && !msg.isDelivered) ...[
                  Tooltip(
                    message: 'Message not yet acknowledged. Tap to resend.',
                    child: InkWell(
                      onTap: () => _resendMessage(msg),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 13,
                              color: Colors.amber.shade200,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Resend',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade200,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 9,
                    color: msg.isMe ? Colors.white70 : (isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}









