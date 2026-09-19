import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/contact_vault.dart';

const _bg      = Color(0xFF0D1117);
const _surface = Color(0xFF161B22);
const _border  = Color(0xFF30363D);
const _text    = Color(0xFFE6EDF3);
const _muted   = Color(0xFF8B949E);
const _blue    = Color(0xFF388BFD);
const _amber   = Color(0xFFD29922);
const _green   = Color(0xFF3FB950);

class KeyVaultScreen extends StatelessWidget {
  const KeyVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myKey = ContactVault.myKeyPair['publicKey']!;
    final contacts = ContactVault.contacts;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('Key Vault',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700, fontSize: 17, color: _text)),
        backgroundColor: _bg,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── My Identity Key ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _blue.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.key_outlined, color: _blue, size: 16),
                      const SizedBox(width: 8),
                      Text('Device Identity Key  ·  X25519',
                          style: GoogleFonts.outfit(
                              color: _blue,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: QrImageView(
                        data: myKey,
                        version: QrVersions.auto,
                        size: 130.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Public Key', style: GoogleFonts.outfit(
                      color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText(
                    myKey,
                    style: GoogleFonts.firaCode(
                        color: _blue, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Contacts Header ────────────────────────────────────────────
            Text('Pre-Synced Contacts',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Keys exchanged before entering the forest. Used for offline E2EE.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
            const SizedBox(height: 14),

            // ── Contact List ───────────────────────────────────────────────
            ...contacts.map((contact) {
              final hasApp = contact.isAppInstalled;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasApp
                        ? _green.withValues(alpha: 0.35)
                        : _amber.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (hasApp ? _green : _amber)
                            .withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        hasApp ? Icons.lock_outline : Icons.sms_outlined,
                        color: hasApp ? _green : _amber,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(contact.name,
                              style: GoogleFonts.outfit(
                                  color: _text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(contact.phoneNumber,
                              style:
                                  GoogleFonts.outfit(color: _muted, fontSize: 11)),
                          const SizedBox(height: 3),
                          Text(
                            hasApp
                                ? 'E2EE key synced  ·  ${contact.publicKey}'
                                : 'No app installed — SMS Gateway fallback',
                            style: GoogleFonts.outfit(
                                color: hasApp ? _green : _amber,
                                fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (hasApp ? _green : _amber).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: (hasApp ? _green : _amber)
                                .withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        hasApp ? 'E2EE' : 'SMS',
                        style: GoogleFonts.outfit(
                            color: hasApp ? _green : _amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
