import 'dart:async';
import 'dart:convert';
import 'package:flutter_nfc_hce/flutter_nfc_hce.dart';
import 'package:nfc_manager/nfc_manager.dart';

class NfcService {
  final FlutterNfcHce _hcePlugin = FlutterNfcHce();
  bool _isEmitting = false;

  Future<bool> isAvailable() async {
    try {
      final isNfcAvailable = await NfcManager.instance.isAvailable();
      final isHceSupported = (await _hcePlugin.isNfcHceSupported()) == true;
      return isNfcAvailable && isHceSupported;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isNfcEnabled() async {
    try {
      return (await _hcePlugin.isNfcEnabled()) == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> startEmitting(String data) async {
    try {
      _isEmitting = true;
      final result = await _hcePlugin.startNfcHce(data);
      return result != null;
    } catch (e) {
      _isEmitting = false;
      return false;
    }
  }

  Future<void> stopEmitting() async {
    if (_isEmitting) {
      try {
        await _hcePlugin.stopNfcHce();
      } catch (_) {}
      _isEmitting = false;
    }
  }

  Future<String?> readFromPeer({Duration timeout = const Duration(seconds: 30)}) async {
    final completer = Completer<String?>();
    
    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            if (ndef == null) {
              if (!completer.isCompleted) completer.complete(null);
              return;
            }
            
            final message = await ndef.read();
            if (message.records.isEmpty) {
              if (!completer.isCompleted) completer.complete(null);
              return;
            }
            
            final record = message.records.first;
            String? content;
            
            if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown) {
              final payload = record.payload;
              if (payload.isNotEmpty) {
                final langCodeLength = payload[0];
                content = utf8.decode(payload.sublist(1 + langCodeLength));
              }
            } else if (record.typeNameFormat == NdefTypeNameFormat.media) {
              content = utf8.decode(record.payload);
            }
            
            if (!completer.isCompleted) completer.complete(content);
          } catch (e) {
            if (!completer.isCompleted) completer.complete(null);
          }
          
          await NfcManager.instance.stopSession();
        },
        onError: (error) async {
          if (!completer.isCompleted) completer.complete(null);
          await NfcManager.instance.stopSession();
        },
      );
      
      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          NfcManager.instance.stopSession();
          completer.complete(null);
        }
      });
      
      return await completer.future;
    } catch (e) {
      try { await NfcManager.instance.stopSession(); } catch (_) {}
      return null;
    }
  }

  Future<String?> hostExchange({
    required String hostPublicKey,
    required String treeStateJson,
  }) async {
    final payload = jsonEncode({
      'type': 'touch_key_exchange',
      'publicKey': hostPublicKey,
      'treeState': treeStateJson,
    });
    
    final emitOk = await startEmitting(payload);
    if (!emitOk) return null;
    
    return null;
  }

  Future<String?> readJoinerKey() async {
    await stopEmitting();
    
    final data = await readFromPeer(timeout: const Duration(seconds: 30));
    if (data == null) return null;
    
    try {
      final json = jsonDecode(data);
      if (json['type'] == 'touch_key_response') {
        return json['publicKey'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> joinerExchange({
    required String joinerPublicKey,
  }) async {
    final data = await readFromPeer(timeout: const Duration(seconds: 30));
    if (data == null) return null;
    
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['type'] != 'touch_key_exchange') return null;
      
      final response = jsonEncode({
        'type': 'touch_key_response',
        'publicKey': joinerPublicKey,
      });
      
      await startEmitting(response);
      
      
      return {
        'publicKey': json['publicKey'] as String,
        'treeState': json['treeState'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> stopSession() async {
    await stopEmitting();
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }
}
