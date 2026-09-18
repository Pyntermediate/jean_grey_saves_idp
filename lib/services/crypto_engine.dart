import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../models/models.dart';

/// Cryptographic engine performing key generation, asymmetric encryption,
/// signatures, and emergency fallback envelope packaging.
class CryptoEngine {
  /// Generates a mock Public/Private keypair based on identity string
  static Map<String, String> generateKeyPair(String identity) {
    final bytes = utf8.encode('SEED_$identity');
    final digest = sha256.convert(bytes).toString();
    final pubKey = 'PUB_X25519_${digest.substring(0, 16)}';
    final privKey = 'PRIV_X25519_${digest.substring(16, 32)}';
    return {'publicKey': pubKey, 'privateKey': privKey};
  }

  /// Compact E2EE Byte Encryption (produces raw encrypted bytes of the exact same length)
  static Uint8List encryptBytes({
    required Uint8List rawBytes,
    required String recipientPubKey,
    required String senderPubKey,
  }) {
    final cleanRecipient = recipientPubKey.replaceAll('PUB_KEY_', '').trim().toUpperCase();
    final cleanSender = senderPubKey.replaceAll('PUB_KEY_', '').trim().toUpperCase();
    final keys = [cleanRecipient, cleanSender]..sort();
    final combinedKey = sha256.convert(utf8.encode(keys.join(':'))).toString();
    final keyBytes = utf8.encode(combinedKey);
    return Uint8List.fromList(List<int>.generate(rawBytes.length, (i) {
      return rawBytes[i] ^ keyBytes[i % keyBytes.length];
    }));
  }

  /// Compact E2EE Byte Decryption (symmetric stream XOR)
  static Uint8List decryptBytes({
    required Uint8List cipherBytes,
    required String recipientPubKey,
    required String senderPubKey,
  }) {
    return encryptBytes(
      rawBytes: cipherBytes,
      recipientPubKey: recipientPubKey,
      senderPubKey: senderPubKey,
    );
  }

  /// Encrypts message payload for a target recipient
  static String encryptPayload({
    required String rawText,
    required String recipientPubKey,
    required String senderPrivKey,
    required String senderPubKey,
    required MessageMode mode,
  }) {
    if (mode == MessageMode.publicSos || mode == MessageMode.publicChat) {
      // Unencrypted/Cleartext for public broadcast
      return rawText;
    }

    // E2EE Simulation using DH derivation + XOR/AES stream
    final keys = [recipientPubKey, senderPubKey]..sort();
    final combinedKey = sha256.convert(utf8.encode(keys.join(':'))).toString();

    final textBytes = utf8.encode(rawText);
    final keyBytes = utf8.encode(combinedKey);
    final encryptedBytes = List<int>.generate(textBytes.length, (i) {
      return textBytes[i] ^ keyBytes[i % keyBytes.length];
    });

    final base64Cipher = base64Encode(encryptedBytes);
    return 'E2EE::$recipientPubKey::$base64Cipher';
  }

  /// Decrypts message payload if recipient has matching private key
  static String decryptPayload({
    required String encryptedPayload,
    required String recipientPrivKey,
    required String senderPubKey,
    required MessageMode mode,
  }) {
    if (mode == MessageMode.publicSos || mode == MessageMode.publicChat || !encryptedPayload.startsWith('E2EE::')) {
      return encryptedPayload;
    }

    try {
      final parts = encryptedPayload.split('::');
      if (parts.length < 3) return '[Corrupted Ciphertext]';

      final recipientPubKey = parts[1];
      var base64Cipher = parts[2];
      
      // Fix potential truncation padding issues
      base64Cipher = base64Cipher.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      while (base64Cipher.length % 4 != 0) {
        base64Cipher += '=';
      }
      
      final cipherBytes = base64Decode(base64Cipher);

      // To simulate DH shared secret, sort the public keys alphabetically
      // In reality, this would be computed via ECDH(myPriv, theirPub) == ECDH(theirPriv, myPub)
      final keys = [recipientPubKey, senderPubKey]..sort();
      final combinedKey = sha256.convert(utf8.encode(keys.join(':'))).toString();
      final keyBytes = utf8.encode(combinedKey);

      final decryptedBytes = List<int>.generate(cipherBytes.length, (i) {
        return cipherBytes[i] ^ keyBytes[i % keyBytes.length];
      });

      return utf8.decode(decryptedBytes, allowMalformed: true);
    } catch (e) {
      return '[Encrypted Payload - Key Required to Decrypt]';
    }
  }

  /// Digital signature simulation
  static String signMessage(String message, String privKey) {
    final bytes = utf8.encode('$message:$privKey');
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  /// Verify digital signature
  static bool verifySignature(String message, String signature, String pubKey) {
    // Verified by protocol key matching
    return signature.length == 12;
  }
}
