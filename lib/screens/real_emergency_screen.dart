import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../services/real_ble_service.dart';
import '../services/real_gps_service.dart';
import '../services/contact_vault.dart';
import '../services/theme_manager.dart';
import '../utils/profile_helper.dart';
import '../widgets/neu_widgets.dart';

class RealEmergencyScreen extends StatefulWidget {
  const RealEmergencyScreen({super.key});

  @override
  State<RealEmergencyScreen> createState() => _RealEmergencyScreenState();
}

class _RealEmergencyScreenState extends State<RealEmergencyScreen> {
  final _ble = RealBleService.instance;
  final _gps = RealGpsService.instance;

  MessageMode _selectedMode = MessageMode.publicSos;
  BlePhyMode _selectedPhy = BlePhyMode.standard1M;
  String? _selectedEmergencyContactId;

  final TextEditingController _noteController = TextEditingController();

  double? _currentLat;
  double? _currentLng;
  bool _isLoadingGps = false;
  bool _isStartingBroadcast = false;

  @override
  void initState() {
    super.initState();
    final cached = _gps.lastKnownPosition;
    if (cached != null) {
      _currentLat = cached.latitude;
      _currentLng = cached.longitude;
    }
    _initHardware();
  }

  Future<void> _initHardware() async {
    await _ble.init();
    if (_ble.hardwareCapabilities['isLeCodedPhySupported'] != true) {
      _selectedPhy = BlePhyMode.standard1M;
    }
    _acquireGpsLock();
    if (mounted) setState(() {});
  }

  Future<void> _acquireGpsLock() async {
    setState(() {
      _isLoadingGps = true;
    });

    final pos = await _gps.getCurrentPosition();
    if (mounted) {
      setState(() {
        _isLoadingGps = false;
        final resolved = pos ?? _gps.lastKnownPosition;
        if (resolved != null) {
          _currentLat = resolved.latitude;
          _currentLng = resolved.longitude;
        }
      });
    }
  }

  Future<void> _confirmAndToggleBroadcast() async {
    if (_ble.isEmergencySosBroadcasting) {
      await _toggleBroadcast();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Emergency Broadcast?'),
        content: const Text('This will continuously broadcast your location and note to all nearby devices. Are you sure you want to proceed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: ThemeManager.accentRed),
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _toggleBroadcast();
    }
  }

  Future<void> _toggleBroadcast() async {
    if (_ble.isEmergencySosBroadcasting) {
      await _ble.stopBroadcasting();
      if (mounted) setState(() {});
    } else {
      if (_selectedMode != MessageMode.publicSos && _selectedEmergencyContactId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a target contact first!')),
        );
        return;
      }

      final hasProfile = await ProfileHelper.ensureProfileName(context);
      if (!hasProfile) return;

      final userNote = _noteController.text.trim();

      setState(() {
        _isStartingBroadcast = true;
      });

      final errorString = await _ble.startBroadcastingEmergencySos(
        mode: _selectedMode,
        note: userNote,
        phy: _selectedPhy,
        customLat: _currentLat,
        customLng: _currentLng,
        targetContactId: _selectedEmergencyContactId,
      );

      if (mounted) {
        setState(() {
          _isStartingBroadcast = false;
        });
        final success = errorString != null && errorString.startsWith('PKT_');
        
        if (success) {
          final prefs = await SharedPreferences.getInstance();
          final targetId = (_selectedMode == MessageMode.privateE2ee && _selectedEmergencyContactId != null) 
              ? _selectedEmergencyContactId! 
              : 'broadcast';
          
          final targetKey = 'chat_$targetId';
          final existingJson = prefs.getStringList(targetKey) ?? [];
          
          final locStr = "${_currentLat?.toStringAsFixed(5) ?? '0.00000'}, ${_currentLng?.toStringAsFixed(5) ?? '0.00000'}";
          final noteText = userNote.isNotEmpty ? "$userNote\n$locStr" : locStr;
          final msgJson = {
            'id': errorString,
            'sender': 'Me',
            'text': noteText,
            'fileName': null,
            'fileSizeKb': null,
            'time': DateTime.now().toIso8601String(),
            'isMe': true,
            'isEncrypted': _selectedMode == MessageMode.privateE2ee,
            'isSos': true,
            'transferSpeed': null,
            'isDelivered': false,
          };
          
          existingJson.add(jsonEncode(msgJson));
          if (existingJson.length > 30) {
            existingJson.removeRange(0, existingJson.length - 30);
          }
          await prefs.setStringList(targetKey, existingJson);
          RealBleService.messageHistoryNotifier.add(null);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? ThemeManager.accentRed : ThemeManager.accentSlate,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Row(
              children: [
                Icon(success ? Icons.sensors : Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    success
                        ? 'Broadcasting emergency signal to nearby devices'
                        : 'Failed to start broadcast: $errorString',
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLeCodedSupported = _ble.hardwareCapabilities['isLeCodedPhySupported'] == true;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency SOS',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_ble.isEmergencySosBroadcasting ? ThemeManager.accentRed : ThemeManager.accentSlate)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_ble.isEmergencySosBroadcasting ? ThemeManager.accentRed : ThemeManager.accentSlate)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _ble.isEmergencySosBroadcasting ? Icons.sensors : Icons.sensors_off,
                          size: 13,
                          color: _ble.isEmergencySosBroadcasting ? ThemeManager.accentRed : ThemeManager.accentSlate,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _ble.isEmergencySosBroadcasting ? 'SENDING SIGNAL' : 'IDLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _ble.isEmergencySosBroadcasting ? ThemeManager.accentRed : ThemeManager.accentSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Modes ────────────────────────────────────
              _buildSectionTitle('Modes'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: NeuContainer(
                      padding: const EdgeInsets.all(12),
                      isSelected: _selectedPhy == BlePhyMode.leCodedS8,
                      onTap: isLeCodedSupported ? () {
                        setState(() => _selectedPhy = BlePhyMode.leCodedS8);
                      } : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bluetooth_searching, size: 18, color: ThemeManager.accentBlue),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ThemeManager.accentBlue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Low Strength',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: ThemeManager.accentBlue),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Maximum Range', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeuContainer(
                      padding: const EdgeInsets.all(12),
                      isSelected: _selectedPhy == BlePhyMode.standard1M,
                      onTap: () {
                        setState(() => _selectedPhy = BlePhyMode.standard1M);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bluetooth, size: 18, color: ThemeManager.accentGreen),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ThemeManager.accentGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'High Strength',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: ThemeManager.accentGreen),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Standard Range', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Section 2: Privacy / Mode Selection ────────────────────────
              _buildSectionTitle('2. Who Should Receive This?'),
              const SizedBox(height: 8),
              Column(
                children: const [
                  MessageMode.publicSos,
                  MessageMode.privateE2ee,
                  MessageMode.hybridSos,
                ].map((mode) {
                  final isSelected = _selectedMode == mode;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: NeuContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedMode = mode),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            size: 18,
                            color: isSelected ? ThemeManager.accentBlue : (isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.label,
                                  style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_selectedMode != MessageMode.publicSos) ...[
                const SizedBox(height: 8),
                Text(
                  'Select Target Contact:',
                  style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedEmergencyContactId,
                  hint: const Text('Choose a contact'),
                  items: ContactVault.contacts.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedEmergencyContactId = val),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              const SizedBox(height: 16),

              // ── // -- Section 3: Satellite GPS Coordinates ------------------
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle('3. Current Satellite Location'),
                  IconButton(
                    icon: _isLoadingGps
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 16),
                    onPressed: _acquireGpsLock,
                    tooltip: 'Update Location',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              NeuContainer(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _currentLat != null ? Icons.location_on : Icons.location_off_outlined,
                      color: _currentLat != null ? ThemeManager.accentGreen : ThemeManager.accentAmber,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentLat != null
                                ? '${_currentLat!.toStringAsFixed(5)}, ${_currentLng!.toStringAsFixed(5)}'
                                : (_isLoadingGps ? 'Locking GPS...' : 'Location Not Locked Yet'),
                            style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoadingGps)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: Icon(_currentLat != null ? Icons.refresh : Icons.gps_fixed, size: 18, color: ThemeManager.accentBlue),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Refresh Location',
                        onPressed: _acquireGpsLock,
                      ),
                    if (_currentLat != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: ThemeManager.accentBlue),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Copy Coordinates',
                        onPressed: () {
                          final text = '$_currentLat, $_currentLng';
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coordinates copied')),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Section 4: Distress Message Note ──────────────────────────
              _buildSectionTitle('4. Note (Max 27 characters)'),
              const SizedBox(height: 6),
              NeuContainer(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: TextField(
                  controller: _noteController,
                  maxLines: 2,
                  maxLength: 27,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter status, injuries, or landmarks...',
                    helperText: 'Broadcast along with your satellite GPS location',
                    helperStyle: TextStyle(
                      fontSize: 10,
                      color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                    ),
                    counterStyle: TextStyle(
                      fontSize: 10,
                      color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                    ),
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ── Emergency Broadcast Button ─────────────────────────────────
              InkWell(
                onTap: _isStartingBroadcast ? () {
                  setState(() { _isStartingBroadcast = false; });
                } : _confirmAndToggleBroadcast,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black : Colors.white,
                    border: Border.all(color: ThemeManager.accentRed, width: 3),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isStartingBroadcast)
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: ThemeManager.accentRed),
                            ),
                            Icon(Icons.close_rounded, color: ThemeManager.accentRed, size: 14),
                          ],
                        )
                      else
                        Icon(
                          _ble.isEmergencySosBroadcasting ? Icons.stop_circle_outlined : Icons.warning_amber_rounded,
                          color: ThemeManager.accentRed,
                          size: 22,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isStartingBroadcast
                            ? 'STARTING SIGNAL...'
                            : (_ble.isEmergencySosBroadcasting ? 'STOP EMERGENCY BROADCAST' : 'BROADCAST EMERGENCY SIGNAL'),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: ThemeManager.accentRed,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
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

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}



