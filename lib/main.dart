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
import 'widgets/neu_widgets.dart';

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

class _NoOverscrollGlowBehavior extends ScrollBehavior {
  const _NoOverscrollGlowBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _NavItemData {
  final IconData icon;
  final String label;
  final double activeWidth;

  const _NavItemData({
    required this.icon,
    required this.label,
    required this.activeWidth,
  });
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  late final PageController _pageController;

  static const List<_NavItemData> _navItems = [
    _NavItemData(
      icon: Icons.chat_bubble_outline_rounded,
      label: 'Messages',
      activeWidth: 98.0,
    ),
    _NavItemData(
      icon: Icons.warning_amber_rounded,
      label: 'SOS',
      activeWidth: 64.0,
    ),
    _NavItemData(
      icon: Icons.hub_outlined,
      label: 'Peers',
      activeWidth: 74.0,
    ),
    _NavItemData(
      icon: Icons.contacts_outlined,
      label: 'Contacts',
      activeWidth: 94.0,
    ),
  ];

  final List<Widget> _screens = const [
    RepaintBoundary(child: RealChatScreen()),
    RepaintBoundary(child: RealEmergencyScreen()),
    RepaintBoundary(child: RealPeersScreen()),
    RepaintBoundary(child: RealKeyVaultScreen()),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
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
    _pageController.dispose();
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
      canPop: true,
      child: AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
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
                  style: GoogleFonts.outfit(
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
          body: ValueListenableBuilder<bool>(
            valueListenable: RealChatScreen.isChatOpenNotifier,
            builder: (context, isChatOpen, _) {
              return ScrollConfiguration(
                behavior: const _NoOverscrollGlowBehavior(),
                child: PageView(
                  controller: _pageController,
                  physics: (_currentIndex == 0 && isChatOpen)
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  children: _screens,
                ),
              );
            },
          ),
          bottomNavigationBar: RepaintBoundary(
            child: _buildBottomNavigationBar(theme, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(ThemeData theme, bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xF2121820) : const Color(0xF7FFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x80000000) : const Color(0xFF64748B).withValues(alpha: 0.12),
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Precise target centers for each tab:
            // Tab 0 indicator sits with 2px inset on the left. Center = 2.0 + w0 / 2.
            // Tab 3 indicator sits with 2px inset on the right. Center = maxWidth - 2.0 - w3 / 2.
            final double w0 = _navItems[0].activeWidth; // 98.0
            final double w3 = _navItems[3].activeWidth; // 94.0
            final double center0 = 2.0 + (w0 / 2.0);
            final double center3 = constraints.maxWidth - 2.0 - (w3 / 2.0);
            final double span = center3 - center0;
            final double center1 = center0 + (span / 3.0);
            final double center2 = center0 + (2.0 * span / 3.0);
            final centers = [center0, center1, center2, center3];

            return AnimatedBuilder(
              animation: _pageController,
              builder: (context, _) {
                double page = _currentIndex.toDouble();
                if (_pageController.hasClients && _pageController.position.haveDimensions) {
                  page = (_pageController.page ?? _currentIndex.toDouble()).clamp(0.0, 3.0);
                }

                final floorIdx = page.floor().clamp(0, 3);
                final ceilIdx = page.ceil().clamp(0, 3);
                final t = page - floorIdx;

                // Dynamic center position of the indicator interpolated across the exact centers
                final currentCenterX = centers[floorIdx] + (centers[ceilIdx] - centers[floorIdx]) * t;

                // Direct smooth continuous width interpolation between the known tab sizes
                final currentWidth = _navItems[floorIdx].activeWidth +
                    (_navItems[ceilIdx].activeWidth - _navItems[floorIdx].activeWidth) * t;

                final currentLeft = currentCenterX - (currentWidth / 2.0);

                final slotWidth = constraints.maxWidth / 4.0;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Morphing Ellipse-Oval Indicator ────────────────
                    Positioned(
                      left: currentLeft,
                      top: 2,
                      bottom: 2,
                      width: currentWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xCC182434) : const Color(0xFFFFFFFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? const Color(0x38FFFFFF) : theme.colorScheme.outline.withValues(alpha: 0.35),
                            width: 1,
                          ),
                          boxShadow: [
                            if (isDark) ...[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.55),
                                offset: const Offset(0, 3),
                                blurRadius: 10,
                                spreadRadius: 0.5,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                offset: const Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ] else ...[
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.10),
                                offset: const Offset(0, 3),
                                blurRadius: 8,
                                spreadRadius: 0.5,
                              ),
                              BoxShadow(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                                offset: const Offset(0, 1),
                                blurRadius: 3,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // ── 4 Tab Slots (Each centered exactly at its indicator center) ──
                    ...List.generate(4, (index) {
                      final item = _navItems[index];
                      final diff = (page - index).abs();
                      final isVisible = diff < 1.0;
                      final weight = (1.0 - diff).clamp(0.0, 1.0);

                      final iconColor = Color.lerp(
                        isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                        isDark ? Colors.white : theme.colorScheme.onSurface,
                        weight,
                      )!;

                      final slotLeft = centers[index] - (slotWidth / 2.0);

                      return Positioned(
                        left: slotLeft,
                        width: slotWidth,
                        top: 0,
                        bottom: 0,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              if (_currentIndex != index) {
                                setState(() => _currentIndex = index);
                                _pageController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                            },
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    item.icon,
                                    color: iconColor,
                                    size: 18,
                                  ),
                                  if (isVisible) ...[
                                    ClipRect(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: weight,
                                        child: Opacity(
                                          opacity: weight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Text(
                                              item.label,
                                              style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: iconColor,
                                              ),
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.clip,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
