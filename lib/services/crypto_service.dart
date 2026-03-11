import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final _algorithm = Chacha20.poly1305Aead();

  static Future<String> encrypt(String plaintext, SecretKey groupKey) async {
    final plaintextBytes = utf8.encode(plaintext);

    final secretBox = await _algorithm.encrypt(
      plaintextBytes,
      secretKey: groupKey,
    );

    final combined = secretBox.concatenation();
    return base64Encode(combined);
  }

  static Future<String> decrypt(String encrypted, SecretKey groupKey) async {
    final combined = base64Decode(encrypted);

    if (combined.length < 28) {
      throw ArgumentError('Ciphertext too short');
    }

    final nonce = combined.sublist(0, 12);
    final ciphertext = combined.sublist(12, combined.length - 16);
    final mac = combined.sublist(combined.length - 16);

    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(mac),
    );

    final decrypted = await _algorithm.decrypt(
      secretBox,
      secretKey: groupKey,
    );

    return utf8.decode(decrypted);
  }

  static Future<SecretKey> generateKey() async {
    return await _algorithm.newSecretKey();
  }

  static Future<String> exportKey(SecretKey key) async {
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }

  static SecretKey importKey(String base64Key) {
    final bytes = base64Decode(base64Key);
    return SecretKeyData(bytes);
  }

  static Future<SimpleKeyPair> generateX25519KeyPair() async {
    final algorithm = X25519();
    return await algorithm.newKeyPair();
  }

  static Future<SecretKey> x25519SharedSecret(
    SimpleKeyPair myKeyPair,
    SimplePublicKey theirPublicKey,
  ) async {
    final algorithm = X25519();
    return await algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );
  }

  static Future<SecretKey> deriveKey(
    SecretKey inputKey, {
    String info = 'treekem-group-key',
  }) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    return await hkdf.deriveKey(
      secretKey: inputKey,
      nonce: utf8.encode(info),
    );
  }

  static Future<String> exportPublicKey(SimplePublicKey publicKey) async {
    return base64Encode(publicKey.bytes);
  }

  static SimplePublicKey importPublicKey(String base64Key) {
    final bytes = base64Decode(base64Key);
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  static Future<Map<String, String>> exportKeyPair(SimpleKeyPair keyPair) async {
    final privateKeyData = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return {
      'private': base64Encode(privateKeyData),
      'public': base64Encode(publicKey.bytes),
    };
  }

  static SimpleKeyPair importKeyPair(Map<String, String> data) {
    final privateBytes = base64Decode(data['private']!);
    final publicBytes = base64Decode(data['public']!);
    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }
}
