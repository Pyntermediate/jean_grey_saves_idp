import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Exact Stitch Aurora Atmosphere Background (#0b1015 in Dark, #f8fafc in Light)
/// Features multiple independently drifting atmospheric components (Cyan, Emerald, Azure, and Neon Teal)
/// that glide relative to each other in a living, multi-layered aurora. Isolated in RepaintBoundary.
class AuroraBackground extends StatefulWidget {
  final Widget child;

  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final p = _controller.value;

        // Several independent moving components with distinct frequencies, paths & phase angles
        // Component 1: Primary Stitch Cyan Aurora Bloom (Top-Left, period ~6.6s)
        final t1 = p * 2 * math.pi * 6.0;
        final alignCyan = Alignment(
          -0.60 + 0.18 * math.sin(t1),
          -0.65 + 0.14 * math.cos(t1 * 0.8),
        );
        final radiusCyan = 1.18 + 0.15 * math.sin(t1 * 0.5);

        // Component 2: Emerald Ambient Drift (Bottom-Right, period ~9.0s)
        final t2 = p * 2 * math.pi * 4.444 + 1.8;
        final alignEmerald = Alignment(
          0.65 + 0.16 * math.cos(t2),
          0.55 + 0.18 * math.sin(t2 * 0.9),
        );
        final radiusEmerald = 0.98 + 0.12 * math.cos(t2 * 0.6);

        // Component 3: Electric Sapphire / Azure Core (Mid-Screen Lateral Drift, period ~5.3s)
        final t3 = p * 2 * math.pi * 7.5 + 3.4;
        final alignAzure = Alignment(
          0.05 + 0.26 * math.sin(t3),
          -0.10 + 0.20 * math.cos(t3 * 0.7),
        );
        final radiusAzure = 1.08 + 0.16 * math.sin(t3 * 0.6);

        // Component 4: Neon Teal Horizon Veil (Top-Right, period ~7.6s)
        final t4 = p * 2 * math.pi * 5.217 + 4.9;
        final alignTeal = Alignment(
          0.52 + 0.16 * math.cos(t4),
          -0.70 + 0.12 * math.sin(t4 * 0.8),
        );
        final radiusTeal = 0.92 + 0.10 * math.cos(t4 * 0.5);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background Layer isolated in RepaintBoundary to avoid repainting child widgets
            RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Base Canvas: #0B1015 (Dark OLED) or #F8FAFC (Light Slate)
                  ColoredBox(
                    color: isDark ? const Color(0xFF0B1015) : const Color(0xFFF8FAFC),
                  ),

                  // 1. Primary Cyan Bloom (Stitch Spec)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: alignCyan,
                          radius: radiusCyan,
                          colors: isDark
                              ? const [
                                  Color(0x2206B6D4), // rgba(6, 182, 212, 0.13)
                                  Color(0x0E0E7490), // rgba(14, 116, 144, 0.05)
                                  Colors.transparent,
                                ]
                              : const [
                                  Color(0x1406B6D4),
                                  Color(0x060EA5E9),
                                  Colors.transparent,
                                ],
                          stops: const [0.0, 0.38, 0.70],
                        ),
                      ),
                    ),
                  ),

                  // 2. Mid-Screen Sapphire / Azure Drift
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: alignAzure,
                          radius: radiusAzure,
                          colors: isDark
                              ? const [
                                  Color(0x120EA5E9), // rgba(14, 165, 233, 0.07)
                                  Colors.transparent,
                                ]
                              : const [
                                  Color(0x0D0EA5E9),
                                  Colors.transparent,
                                ],
                          stops: const [0.0, 0.55],
                        ),
                      ),
                    ),
                  ),

                  // 3. Top-Right Neon Teal Veil
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: alignTeal,
                          radius: radiusTeal,
                          colors: isDark
                              ? const [
                                  Color(0x1014B8A6), // rgba(20, 184, 166, 0.06)
                                  Colors.transparent,
                                ]
                              : const [
                                  Color(0x0A14B8A6),
                                  Colors.transparent,
                                ],
                          stops: const [0.0, 0.50],
                        ),
                      ),
                    ),
                  ),

                  // 4. Bottom-Right Emerald Ambient Bloom (Stitch Spec)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: alignEmerald,
                          radius: radiusEmerald,
                          colors: isDark
                              ? const [
                                  Color(0x0F10B981), // rgba(16, 185, 129, 0.06)
                                  Colors.transparent,
                                ]
                              : const [
                                  Color(0x0B10B981),
                                  Colors.transparent,
                                ],
                          stops: const [0.0, 0.52],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Foreground UI Content
            widget.child,
          ],
        );
      },
    );
  }
}

/// Clean, Classy Frosted Glass Utility Card Container
/// Uses natural physical shadows that grow slightly when selected to create elegant depth emphasis without odd border glow.
class NeuContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? customColor;
  final Border? border;
  final VoidCallback? onTap;
  final bool isSelected;

  const NeuContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = 16,
    this.customColor,
    this.border,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Background: Clean elevated surface when selected
    final baseColor = customColor ??
        (isSelected
            ? (isDark ? const Color(0xCC182434) : const Color(0xFFFFFFFF))
            : (isDark ? const Color(0x8C121820) : const Color(0xE6FFFFFF)));

    // Border: Subtle, clean, non-glowing outline
    final effectiveBorder = border ??
        Border.all(
          color: isSelected
              ? (isDark ? const Color(0x38FFFFFF) : theme.colorScheme.outline)
              : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0)),
          width: 1.0,
        );

    // Shadows: Grow bigger on selection to create tactile depth and natural emphasis
    final List<BoxShadow> shadows = isSelected
        ? [
            if (isDark) ...[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.60),
                offset: const Offset(0, 4),
                blurRadius: 14,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                offset: const Offset(0, 1),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ] else ...[
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.12),
                offset: const Offset(0, 4),
                blurRadius: 12,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                offset: const Offset(0, 1),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ]
          ]
        : [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.35)
                  : const Color(0xFF64748B).withValues(alpha: 0.06),
              offset: const Offset(0, 2),
              blurRadius: 6,
              spreadRadius: 0,
            ),
          ];

    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: effectiveBorder,
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: box,
      );
    }
    return box;
  }
}
