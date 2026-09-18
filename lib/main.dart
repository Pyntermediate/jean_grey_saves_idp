import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/real_chat_screen.dart';
import 'screens/real_emergency_screen.dart';
import 'screens/real_key_vault_screen.dart';
import 'screens/real_peers_screen.dart';
import 'screens/splash_screen.dart';
import 'services/theme_manager.dart';
import 'services/update_checker.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'screens/real_settings_screen.dart';
import 'services/contact_vault.dart';
import 'services/real_ble_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  await ContactVault.init();
  
  final prefs = await SharedPreferences.getInstance();
  final isMuleEnabled = prefs.getBool('is_mule_enabled') ?? true;
  if (isMuleEnabled) {
    NotificationService.instance.startMuleService();
  }
  
  runApp(const FlareApp());
}

class FlareApp extends StatelessWidget {
  const FlareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeManager.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Flare',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeManager.instance.themeMode,
          theme: ThemeManager.lightTheme,
          darkTheme: ThemeManager.darkTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    RealChatScreen(),
    RealEmergencyScreen(),
    RealPeersScreen(),
    RealKeyVaultScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for app updates and battery optimization after the UI has fully rendered
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          UpdateChecker.checkForUpdate(context);
          _checkBatteryOptimization(context);
        }
      });
    }
  }

  Future<void> _checkBatteryOptimization(BuildContext context) async {
    final isIgnored = await NotificationService.instance.isBatteryOptimizationIgnored();
    if (!isIgnored && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.bolt, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Expanded(child: Text('24/7 Offline Reception', style: TextStyle(fontSize: 18))),
            ],
          ),
          content: const Text(
            'To ensure you always receive emergency broadcasts and chat messages when your screen is locked or sleeping, Android requires setting Flare\'s battery usage to "Unrestricted" (Not Optimized).\n\nWould you like to configure this now?',
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                NotificationService.instance.requestIgnoreBatteryOptimization();
              },
              child: const Text('Enable Unrestricted'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RealBleService.instance.wakeUpMesh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        extendBody: true,
      appBar: AppBar(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.asset(
                'assets/flame_symbol.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'flare',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const RealSettingsScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.ease;
                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                    var offsetAnimation = animation.drive(tween);
                    return SlideTransition(position: offsetAnimation, child: child);
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outline,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withValues(alpha: 0.35) : const Color(0xFF64748B).withValues(alpha: 0.08),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Messages',
                activeColor: theme.colorScheme.onSurface,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.warning_amber_rounded,
                label: 'SOS',
                activeColor: ThemeManager.accentRed,
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.hub_outlined,
                label: 'Peers',
                activeColor: theme.colorScheme.onSurface,
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.contacts_outlined,
                label: 'Contacts',
                activeColor: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color activeColor,
  }) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: isDark ? 0.2 : 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : (isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted),
              size: 18,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: activeColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
