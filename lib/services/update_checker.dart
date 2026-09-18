import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme_manager.dart';

/// In-app update checker.
class UpdateChecker {
  UpdateChecker._();

  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/version.json';

  /// Call this once from your main navigation shell's initState.
  static Future<void> checkForUpdate(BuildContext context) async {
    // APK update checker is only for native Android/Desktop devices, not Web
    if (kIsWeb) return;

    try {
      // 1. Get the currently installed app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 2. Fetch the remote version.json with a snappy 2-second timeout for offline environments
      final response = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final latestVersion = data['latest_version'] as String? ?? currentVersion;
      final latestBuild = (data['latest_build'] as num?)?.toInt() ?? 0;
      final downloadUrl = data['download_url'] as String? ?? '';
      final releaseNotes = data['release_notes'] as String? ?? '';

      // 3. Compare versions
      final needsUpdate = _isNewer(latestVersion, latestBuild, currentVersion, currentBuild);

      if (!needsUpdate || downloadUrl.isEmpty) return;

      // 4. Show update banner (only if context is still valid)
      if (!context.mounted) return;

      _showUpdateBanner(
        context,
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      // Silently fail — update check is non-critical.
      // App works fully offline; this only runs when internet is available.
    }
  }

  /// Compares semantic version strings (e.g. "1.2.3" vs "1.3.0").
  static bool _isNewer(
    String remoteVersion,
    int remoteBuild,
    String localVersion,
    int localBuild,
  ) {
    final remote = remoteVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final local = localVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    // Pad to 3 segments
    while (remote.length < 3) {
      remote.add(0);
    }
    while (local.length < 3) {
      local.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (remote[i] > local[i]) return true;
      if (remote[i] < local[i]) return false;
    }

    // Same version string — compare build numbers
    return remoteBuild > localBuild;
  }

  /// Shows a subtle bottom sheet with update info and a download button.
  static void _showUpdateBanner(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ThemeManager.accentBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.system_update_outlined, color: ThemeManager.accentBlue, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'v$currentVersion  →  v$latestVersion',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ThemeManager.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Release notes
              if (releaseNotes.isNotEmpty) ...[
                Text(
                  'What\'s New',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  releaseNotes,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.colorScheme.outline),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Later',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? ThemeManager.darkTextMuted : ThemeManager.lightTextMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final uri = Uri.parse(downloadUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        'Download Update',
                        style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeManager.accentBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
