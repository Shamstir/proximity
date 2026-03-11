import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'crypto_service.dart';

class TreeKEMNode {
  final String? memberId;

  SimpleKeyPair? keyPair;

  SimplePublicKey? publicKey;

  SecretKey? secret;

  bool isBlank;

  TreeKEMNode({
    this.memberId,
    this.keyPair,
    this.publicKey,
    this.secret,
    this.isBlank = false,
  });

  bool get isLeaf => memberId != null;

  Future<Map<String, dynamic>> toPublicJson() async {
    return {
      'memberId': memberId,
      'publicKey': publicKey != null
          ? await CryptoService.exportPublicKey(publicKey!)
          : null,
      'isBlank': isBlank,
    };
  }

  static TreeKEMNode fromPublicJson(Map<String, dynamic> json) {
    final pubKeyStr = json['publicKey'] as String?;
    return TreeKEMNode(
      memberId: json['memberId'] as String?,
      publicKey: pubKeyStr != null
          ? CryptoService.importPublicKey(pubKeyStr)
          : null,
      isBlank: json['isBlank'] as bool? ?? false,
    );
  }
}

class TreeKEMState {
  final List<TreeKEMNode> _members = [];

  String? _myMemberId;

  int? _myIndex;

  SecretKey? _cachedGroupKey;

  String? get myMemberId => _myMemberId;

  int get memberCount => _members.where((m) => !m.isBlank).length;

  List<String> get memberIds {
    return _members
        .where((m) => !m.isBlank && m.memberId != null)
        .map((m) => m.memberId!)
        .toList();
  }

  Future<void> initWithSelf(String memberId, SimpleKeyPair keyPair) async {
    _myMemberId = memberId;
    final publicKey = await keyPair.extractPublicKey();

    _members.clear();
    _members.add(TreeKEMNode(
      memberId: memberId,
      keyPair: keyPair,
      publicKey: publicKey,
      isBlank: false,
    ));
    _myIndex = 0;
    _cachedGroupKey = null;
  }

  Future<int> addMember(String memberId, SimplePublicKey publicKey) async {
    _cachedGroupKey = null;

    for (int i = 0; i < _members.length; i++) {
      if (_members[i].isBlank) {
        _members[i] = TreeKEMNode(
          memberId: memberId,
          publicKey: publicKey,
          isBlank: false,
        );
        return i;
      }
    }

    _members.add(TreeKEMNode(
      memberId: memberId,
      publicKey: publicKey,
      isBlank: false,
    ));
    return _members.length - 1;
  }

  Future<void> removeMember(String memberId) async {
    _cachedGroupKey = null;

    for (int i = 0; i < _members.length; i++) {
      if (_members[i].memberId == memberId && !_members[i].isBlank) {
        _members[i] = TreeKEMNode(
          memberId: memberId,
          isBlank: true,
        );

        if (_myIndex != null && _myIndex! < _members.length) {
          final newKeyPair = await CryptoService.generateX25519KeyPair();
          final newPublicKey = await newKeyPair.extractPublicKey();
          _members[_myIndex!] = TreeKEMNode(
            memberId: _myMemberId,
            keyPair: newKeyPair,
            publicKey: newPublicKey,
            isBlank: false,
          );
        }
        break;
      }
    }
  }

  Future<SecretKey> deriveGroupKey() async {
    if (_cachedGroupKey != null) return _cachedGroupKey!;

    final activeMembers = _members.where((m) => !m.isBlank).toList();
    if (activeMembers.isEmpty) {
      throw StateError('No active members in tree');
    }

    SecretKey rootSecret;

    if (activeMembers.length == 1) {
      final member = activeMembers[0];
      if (member.keyPair != null) {
        final privateBytes = await member.keyPair!.extractPrivateKeyBytes();
        rootSecret = SecretKeyData(privateBytes);
      } else if (member.publicKey != null) {
        final pubBytes = member.publicKey!.bytes;
        rootSecret = SecretKeyData(List<int>.from(pubBytes));
      } else {
        throw StateError('Member has no key data');
      }
    } else {
      TreeKEMNode? myNode;
      if (_myIndex != null && _myIndex! < _members.length) {
        myNode = _members[_myIndex!];
      }

      if (myNode != null && myNode.keyPair != null) {
        List<int> combinedBytes = [];
        for (final member in activeMembers) {
          if (member.memberId == _myMemberId) continue;
          if (member.publicKey == null) continue;

          final shared = await CryptoService.x25519SharedSecret(
            myNode.keyPair!,
            member.publicKey!,
          );
          final sharedBytes = await shared.extractBytes();
          combinedBytes.addAll(sharedBytes);
        }

        if (combinedBytes.isEmpty) {
          final privateBytes = await myNode.keyPair!.extractPrivateKeyBytes();
          rootSecret = SecretKeyData(privateBytes);
        } else {
          rootSecret = SecretKeyData(combinedBytes);
        }
      } else {
        List<int> seedBytes = [];
        for (final member in activeMembers) {
          if (member.publicKey != null) {
            seedBytes.addAll(member.publicKey!.bytes);
          }
        }
        rootSecret = SecretKeyData(seedBytes);
      }
    }

    _cachedGroupKey = await CryptoService.deriveKey(
      rootSecret,
      info: 'treekem-chacha20-group-key',
    );
    return _cachedGroupKey!;
  }

  Future<Map<String, dynamic>> exportPublicState() async {
    final nodes = <Map<String, dynamic>>[];
    for (final member in _members) {
      nodes.add(await member.toPublicJson());
    }
    return {
      'members': nodes,
      'version': 2,
    };
  }

  Future<String> exportPublicStateJson() async {
    final state = await exportPublicState();
    return jsonEncode(state);
  }

  Future<void> importPublicState(
    Map<String, dynamic> state,
    String myMemberId,
    SimpleKeyPair myKeyPair,
  ) async {
    _cachedGroupKey = null;
    _myMemberId = myMemberId;

    final nodes = state['members'] as List<dynamic>;
    _members.clear();

    for (final nodeJson in nodes) {
      _members.add(
        TreeKEMNode.fromPublicJson(nodeJson as Map<String, dynamic>),
      );
    }

    final myPublicKey = await myKeyPair.extractPublicKey();
    _myIndex = null;

    for (int i = 0; i < _members.length; i++) {
      if (_members[i].memberId == myMemberId && !_members[i].isBlank) {
        _members[i] = TreeKEMNode(
          memberId: myMemberId,
          keyPair: myKeyPair,
          publicKey: myPublicKey,
          isBlank: false,
        );
        _myIndex = i;
        break;
      }
    }

    if (_myIndex == null) {
      _members.add(TreeKEMNode(
        memberId: myMemberId,
        keyPair: myKeyPair,
        publicKey: myPublicKey,
        isBlank: false,
      ));
      _myIndex = _members.length - 1;
    }
  }

  Future<void> importPublicStateJson(
    String json,
    String myMemberId,
    SimpleKeyPair myKeyPair,
  ) async {
    final state = jsonDecode(json) as Map<String, dynamic>;
    await importPublicState(state, myMemberId, myKeyPair);
  }
}
