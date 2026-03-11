import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/group.dart';
import 'crypto_service.dart';
import 'nfc_service.dart';
import 'treekem_service.dart';

enum MeshMessageType {
  chat,
  leaderChange,
  memberList,
  keyExchange,
  keyUpdate,
}

class MeshMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final MeshMessageType type;

  MeshMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.type = MeshMessageType.chat,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'text': text,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'type': type.index,
  };

  factory MeshMessage.fromJson(Map<String, dynamic> json) => MeshMessage(
    id: json['id'],
    senderId: json['senderId'],
    senderName: json['senderName'],
    text: json['text'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    type: json['type'] != null 
      ? MeshMessageType.values[json['type']] 
      : MeshMessageType.chat,
  );
}


class MeshService {
  static const String serviceId = "com.touch.mesh";
  
  final Strategy strategy = Strategy.P2P_CLUSTER;
  
  String _userName = "User";
  String _uniqueId = "";
  
  Group? _currentGroup;
  
  bool _isLeader = false;
  
  String? _leaderEndpointId;
  
  final Map<String, String> _connectedEndpoints = {};
  
  final Map<String, Group> _discoveredGroups = {};
  
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  final TreeKEMState _treeKEM = TreeKEMState();
  SimpleKeyPair? _myKeyPair;
  SecretKey? _groupKey;
  final NfcService _nfcService = NfcService();
  bool _encryptionReady = false;
  
  final Map<String, String> _endpointToMemberId = {};
  

  final _peersController = StreamController<List<String>>.broadcast();
  final _messageController = StreamController<MeshMessage>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _groupsController = StreamController<List<Group>>.broadcast();
  final _leaderChangeController = StreamController<bool>.broadcast();
  
  final Set<String> _seenMessageIds = {};
  

  Completer<bool>? _joinCompleter;
  String? _pendingJoinEndpointId;
  

  Stream<List<String>> get peersStream => _peersController.stream;
  Stream<MeshMessage> get messageStream => _messageController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<List<Group>> get discoveredGroupsStream => _groupsController.stream;
  Stream<bool> get leaderChangeStream => _leaderChangeController.stream;
  

  List<String> get connectedPeers => _connectedEndpoints.values.toList();
  int get peerCount => _connectedEndpoints.length;
  String get uniqueId => _uniqueId;
  Group? get currentGroup => _currentGroup;
  List<Group> get discoveredGroups => _discoveredGroups.values.toList();
  bool get isLeader => _isLeader;
  bool get isEncryptionReady => _encryptionReady;
  NfcService get nfcService => _nfcService;
  TreeKEMState get treeKEM => _treeKEM;

  Future<void> pauseNearbyForNfc() async {
    try { await Nearby().stopDiscovery(); } catch (_) {}
    try { await Nearby().stopAdvertising(); } catch (_) {}
    _isDiscovering = false;
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> resumeNearbyAfterNfc() async {
    if (_currentGroup != null && _isLeader) {
      await startAdvertising();
    }
    await startDiscovery();
  }
  
  void initialize(String userName) {
    _userName = userName;
    _uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    _seenMessageIds.clear();
    _statusController.add("Initialized");
  }
  
  Future<bool> createGroup(String groupName, String agenda, {bool isEncrypted = true}) async {
    _currentGroup = Group(
      id: _uniqueId,
      name: groupName,
      agenda: agenda,
      hostId: _uniqueId,
      hostName: _userName,
      createdAt: DateTime.now(),
      isEncrypted: isEncrypted,
    );
    
    _isLeader = true;
    
    bool advertiseResult = await startAdvertising();
    if (!advertiseResult) {
      await Future.delayed(const Duration(milliseconds: 500));
      advertiseResult = await startAdvertising();
    }
    return advertiseResult;
  }
  
  Future<bool> startAdvertising() async {
    try {
      if (_isAdvertising) {
        try {
          await Nearby().stopAdvertising();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      _statusController.add("Advertising...");
      
      String advertiseName;
      if (_currentGroup != null && _isLeader) {
        advertiseName = _currentGroup!.toAdvertisingString();
      } else {
        advertiseName = _userName;
      }
      
      bool result = await Nearby().startAdvertising(
        advertiseName,
        strategy,
        serviceId: serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      
      _isAdvertising = result;
      if (result) {
        _statusController.add(_currentGroup != null && _isLeader
          ? "Hosting: ${_currentGroup!.name}" 
          : "Advertising as $_userName");
      } else {
        _statusController.add("Advertising returned false");
      }
      return result;
    } catch (e) {
      _statusController.add("Advertising failed: $e");
      return false;
    }
  }
  
  Future<bool> startDiscovery() async {
    try {
      if (_isDiscovering) {
        try {
          await Nearby().stopDiscovery();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      _statusController.add("Discovering...");
      _discoveredGroups.clear();
      
      bool result = await Nearby().startDiscovery(
        _userName,
        strategy,
        serviceId: serviceId,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );
      
      _isDiscovering = result;
      if (result) {
        _statusController.add("Searching for groups...");
      } else {
        _statusController.add("Discovery returned false");
        await Future.delayed(const Duration(milliseconds: 300));
        try {
          result = await Nearby().startDiscovery(
            _userName,
            strategy,
            serviceId: serviceId,
            onEndpointFound: _onEndpointFound,
            onEndpointLost: _onEndpointLost,
          );
          _isDiscovering = result;
          if (result) {
            _statusController.add("Searching for groups (retry succeeded)...");
          }
        } catch (_) {}
      }
      return result;
    } catch (e) {
      _statusController.add("Discovery failed: $e");
      return false;
    }
  }
  
  Future<void> startMesh() async {
    await startAdvertising();
    await startDiscovery();
  }
  
  Future<bool> joinGroup(Group group) async {
    _currentGroup = group;
    _isLeader = false;
    _leaderEndpointId = group.hostId;
    _statusController.add("Joining: ${group.name}");
    
    _joinCompleter?.completeError("Cancelled");
    _joinCompleter = Completer<bool>();
    _pendingJoinEndpointId = group.hostId;
    
    try {
      await Nearby().requestConnection(
        _userName,
        group.hostId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      final errorStr = e.toString();
      

      if (errorStr.contains('8012')) {
        _statusController.add("Stale endpoint, refreshing...");
        _joinCompleter?.complete(false);
        _joinCompleter = null;
        _pendingJoinEndpointId = null;
        
        await refreshDiscovery();
        await Future.delayed(const Duration(milliseconds: 500));
        
        final freshGroup = _discoveredGroups.values.where(
          (g) => g.name == group.name && g.hostName == group.hostName,
        ).firstOrNull;
        
        if (freshGroup != null && freshGroup.hostId != group.hostId) {
          _statusController.add("Found fresh endpoint, retrying...");
          return joinGroup(freshGroup);
        }
        
        _statusController.add("Failed to join: stale endpoint");
        return false;
      }
      
      _statusController.add("Failed to join: $e");
      _joinCompleter?.complete(false);
      _joinCompleter = null;
      _pendingJoinEndpointId = null;
      return false;
    }
    
    try {
      final result = await _joinCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _statusController.add("Join timed out");
          return false;
        },
      );
      _joinCompleter = null;
      _pendingJoinEndpointId = null;
      return result;
    } catch (e) {
      _joinCompleter = null;
      _pendingJoinEndpointId = null;
      return false;
    }
  }
  
  Future<void> refreshDiscovery() async {
    _statusController.add("Refreshing...");
    _discoveredGroups.clear();
    _groupsController.add([]);
    
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    await startDiscovery();
  }
  
  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    _statusController.add("Found: $endpointName");
    
    final group = Group.fromAdvertisingString(endpointName, endpointId);
    if (group != null) {
      _discoveredGroups[endpointId] = group;
      _groupsController.add(discoveredGroups);
      _statusController.add("Found group: ${group.name}");
    }
  }
  
  void _onEndpointLost(String? endpointId) {
    if (endpointId != null) {
      _discoveredGroups.remove(endpointId);
      _groupsController.add(discoveredGroups);
    }
    _statusController.add("Lost endpoint: $endpointId");
  }
  
  void _onConnectionInitiated(String endpointId, ConnectionInfo connectionInfo) async {
    _statusController.add("Connecting to: ${connectionInfo.endpointName}");
    
    try {
      await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: (endpointId, payload) {
          _onPayloadReceived(endpointId, payload);
        },
        onPayloadTransferUpdate: (endpointId, update) {},
      );
    } catch (e) {
      _statusController.add("Failed to accept connection: $e");
      if (_pendingJoinEndpointId == endpointId && _joinCompleter != null && !_joinCompleter!.isCompleted) {
        _joinCompleter!.complete(false);
      }
    }
  }
  
  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpoints[endpointId] = "Peer-${endpointId.substring(0, 4)}";
      _peersController.add(connectedPeers);
      _statusController.add("Connected! (${peerCount} peers)");
      
      if (_isLeader && _encryptionReady) {
        _sendKeyExchangeToNewPeer(endpointId);
      }
      
      if (_pendingJoinEndpointId == endpointId && _joinCompleter != null && !_joinCompleter!.isCompleted) {
        _joinCompleter!.complete(true);
      }
    } else {
      _statusController.add("Connection failed: $status");
      
      if (_pendingJoinEndpointId == endpointId && _joinCompleter != null && !_joinCompleter!.isCompleted) {
        _joinCompleter!.complete(false);
      }
    }
  }
  
  void _onDisconnected(String endpointId) {
    final name = _connectedEndpoints[endpointId] ?? endpointId;
    _connectedEndpoints.remove(endpointId);
    _peersController.add(connectedPeers);
    _statusController.add("$name left (${peerCount} peers)");
    
    final memberId = _endpointToMemberId[endpointId];
    if (memberId != null && _encryptionReady) {
      _handleMemberLeftTreeKEM(memberId, endpointId);
    }
    _endpointToMemberId.remove(endpointId);
    
    if (endpointId == _leaderEndpointId) {
      _handleLeaderLeft();
    }
    
    if (_connectedEndpoints.isEmpty && !_isLeader) {
      _statusController.add("Group ended - all members left");
      _leaderChangeController.add(false);
    }
  }
  
  void _handleLeaderLeft() {
    _statusController.add("Leader left, selecting new leader...");
    
    if (_connectedEndpoints.isEmpty) {
      _becomeLeader();
      return;
    }
    
    final allIds = [..._connectedEndpoints.keys, "SELF:$_uniqueId"];
    allIds.sort();
    
    final winnerId = allIds.first;
    
    if (winnerId.startsWith("SELF:")) {
      _becomeLeader();
    } else {
      _leaderEndpointId = winnerId;
      _statusController.add("New leader: ${_connectedEndpoints[winnerId]}");
    }
  }
  
  Future<void> _becomeLeader() async {
    _isLeader = true;
    _leaderEndpointId = null;
    
    if (_currentGroup != null) {
      _currentGroup = Group(
        id: _currentGroup!.id,
        name: _currentGroup!.name,
        agenda: _currentGroup!.agenda,
        hostId: _uniqueId,
        hostName: _userName,
        createdAt: _currentGroup!.createdAt,
      );
    }
    
    _statusController.add("You are now the group leader");
    _leaderChangeController.add(true);
    
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
    } catch (e) {}

    
    await Future.delayed(const Duration(milliseconds: 300));
    
    await startAdvertising();
    
    await startDiscovery();
    
    _broadcastLeaderChange();
  }
  
  void _broadcastLeaderChange() {
    final message = MeshMessage(
      id: "${_uniqueId}_leader_${DateTime.now().millisecondsSinceEpoch}",
      senderId: _uniqueId,
      senderName: _userName,
      text: "LEADER_CHANGE:$_uniqueId:$_userName",
      timestamp: DateTime.now(),
      type: MeshMessageType.leaderChange,
    );
    
    _seenMessageIds.add(message.id);
    
    final jsonString = jsonEncode(message.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    
    for (final endpointId in _connectedEndpoints.keys) {
      try {
        Nearby().sendBytesPayload(endpointId, bytes);
      } catch (e) {
        print("Failed to send leader change to $endpointId: $e");
      }
    }
  }
  
  Future<void> _onPayloadReceived(String endpointId, Payload payload) async {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      try {
        final jsonString = utf8.decode(payload.bytes!);
        final json = jsonDecode(jsonString);
        final message = MeshMessage.fromJson(json);
        
        if (_seenMessageIds.contains(message.id)) {
          return;
        }
        
        _seenMessageIds.add(message.id);
        
        switch (message.type) {
          case MeshMessageType.leaderChange:
            _handleLeaderChangeMessage(message, endpointId);
            break;
          case MeshMessageType.memberList:
            break;
          case MeshMessageType.keyExchange:
            await _handleKeyExchangeMessage(message, endpointId);
            break;
          case MeshMessageType.keyUpdate:
            await _handleKeyUpdateMessage(message, endpointId);
            break;
          case MeshMessageType.chat:
            _connectedEndpoints[endpointId] = message.senderName;
            _peersController.add(connectedPeers);
            

            MeshMessage displayMessage = message;
            if (_encryptionReady && _groupKey != null) {
              try {
                final decryptedText = await CryptoService.decrypt(
                  message.text, _groupKey!,
                );
                displayMessage = MeshMessage(
                  id: message.id,
                  senderId: message.senderId,
                  senderName: message.senderName,
                  text: decryptedText,
                  timestamp: message.timestamp,
                  type: message.type,
                );
              } catch (e) {
                print("Decryption failed: $e");
              }
            }
            
            _messageController.add(displayMessage);
            
            _forwardMessage(payload.bytes!, excludeEndpoint: endpointId);
            break;
        }
        
      } catch (e) {
        print("Error parsing message: $e");
      }
    }
  }
  
  void _handleLeaderChangeMessage(MeshMessage message, String fromEndpoint) {
    final parts = message.text.split(':');
    if (parts.length >= 3 && parts[0] == 'LEADER_CHANGE') {
      final newLeaderId = parts[1];
      final newLeaderName = parts[2];
      
      _leaderEndpointId = fromEndpoint;
      _isLeader = false;
      
      if (_currentGroup != null) {
        _currentGroup = Group(
          id: _currentGroup!.id,
          name: _currentGroup!.name,
          agenda: _currentGroup!.agenda,
          hostId: newLeaderId,
          hostName: newLeaderName,
          createdAt: _currentGroup!.createdAt,
        );
      }
      
      _statusController.add("$newLeaderName is now the leader");
      
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message.toJson())));
      _forwardMessage(bytes, excludeEndpoint: fromEndpoint);
    }
  }
  
  Future<void> sendMessage(String text) async {
    String messageText = text;
    if (_encryptionReady && _groupKey != null) {
      try {
        messageText = await CryptoService.encrypt(text, _groupKey!);
      } catch (e) {
        print("Encryption failed, sending plaintext: $e");
        messageText = text;
      }
    }
    
    final message = MeshMessage(
      id: "${_uniqueId}_${DateTime.now().millisecondsSinceEpoch}",
      senderId: _uniqueId,
      senderName: _userName,
      text: messageText,
      timestamp: DateTime.now(),
      type: MeshMessageType.chat,
    );
    
    _seenMessageIds.add(message.id);
    
    final jsonString = jsonEncode(message.toJson());
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    
    for (final endpointId in _connectedEndpoints.keys) {
      try {
        await Nearby().sendBytesPayload(endpointId, bytes);
      } catch (e) {
        print("Failed to send to $endpointId: $e");
      }
    }
    
    _statusController.add("Sent to ${peerCount} peers");
  }
  
  void _forwardMessage(Uint8List bytes, {required String excludeEndpoint}) {
    for (final endpointId in _connectedEndpoints.keys) {
      if (endpointId != excludeEndpoint) {
        try {
          Nearby().sendBytesPayload(endpointId, bytes);
        } catch (e) {
          print("Failed to forward to $endpointId: $e");
        }
      }
    }
  }
  

  Future<void> leaveGroup() async {
    if (_isLeader && _connectedEndpoints.isNotEmpty) {
      final newLeaderId = _connectedEndpoints.keys.first;
      

      final message = MeshMessage(
        id: "${_uniqueId}_promote_${DateTime.now().millisecondsSinceEpoch}",
        senderId: _uniqueId,
        senderName: _userName,
        text: "PROMOTE_LEADER:$newLeaderId",
        timestamp: DateTime.now(),
        type: MeshMessageType.leaderChange,
      );
      
      final jsonString = jsonEncode(message.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      
      try {
        await Nearby().sendBytesPayload(newLeaderId, bytes);
      } catch (e) {
        print("Failed to send leadership transfer: $e");
      }
      
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    await stopMesh();
  }
  

  Future<void> stopMesh() async {
    try { await Nearby().stopAdvertising(); } catch (_) {}
    try { await Nearby().stopDiscovery(); } catch (_) {}
    try { await Nearby().stopAllEndpoints(); } catch (_) {}
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    _connectedEndpoints.clear();
    _discoveredGroups.clear();
    _seenMessageIds.clear();
    _endpointToMemberId.clear();
    _currentGroup = null;
    _isLeader = false;
    _isAdvertising = false;
    _isDiscovering = false;
    _leaderEndpointId = null;
    _pendingJoinEndpointId = null;
    _groupKey = null;
    _myKeyPair = null;
    _encryptionReady = false;
    if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
      _joinCompleter!.complete(false);
    }
    _joinCompleter = null;
    _peersController.add([]);
    _groupsController.add([]);
    _statusController.add("Disconnected");
    await _nfcService.stopSession();
  }
  

  
  Future<void> initEncryption() async {
    _myKeyPair = await CryptoService.generateX25519KeyPair();
    await _treeKEM.initWithSelf(_uniqueId, _myKeyPair!);
    _groupKey = await _treeKEM.deriveGroupKey();
    _encryptionReady = true;
    _statusController.add("Encryption initialized");
  }
  
  Future<String?> getMyPublicKeyBase64() async {
    if (_myKeyPair == null) return null;
    final publicKey = await _myKeyPair!.extractPublicKey();
    return await CryptoService.exportPublicKey(publicKey);
  }
  
  Future<String> getTreeStateJson() async {
    return await _treeKEM.exportPublicStateJson();
  }
  
  Future<void> initEncryptionAsJoiner(
    String treeStateJson,
    String myMemberId,
  ) async {
    _myKeyPair = await CryptoService.generateX25519KeyPair();
    await _treeKEM.importPublicStateJson(
      treeStateJson,
      myMemberId,
      _myKeyPair!,
    );
    _groupKey = await _treeKEM.deriveGroupKey();
    _encryptionReady = true;
    _statusController.add("Encryption initialized (joiner)");
  }
  
  Future<void> addPeerToTreeKEM(
    String memberId,
    String publicKeyBase64,
    String endpointId,
  ) async {
    final publicKey = CryptoService.importPublicKey(publicKeyBase64);
    await _treeKEM.addMember(memberId, publicKey);
    _groupKey = await _treeKEM.deriveGroupKey();
    _endpointToMemberId[endpointId] = memberId;
    _statusController.add("Member added to encryption tree");
    
    await _broadcastKeyUpdate();
  }
  
  Future<void> _sendKeyExchangeToNewPeer(String endpointId) async {
    try {
      final treeState = await _treeKEM.exportPublicStateJson();
      final message = MeshMessage(
        id: "${_uniqueId}_keyex_${DateTime.now().millisecondsSinceEpoch}",
        senderId: _uniqueId,
        senderName: _userName,
        text: treeState,
        timestamp: DateTime.now(),
        type: MeshMessageType.keyExchange,
      );
      
      final jsonString = jsonEncode(message.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      await Nearby().sendBytesPayload(endpointId, bytes);
      _statusController.add("Sent encryption keys to new peer");
    } catch (e) {
      print("Failed to send key exchange: $e");
    }
  }
  
  Future<void> _handleKeyExchangeMessage(
    MeshMessage message,
    String fromEndpoint,
  ) async {
    try {
      if (_myKeyPair == null) {
        _myKeyPair = await CryptoService.generateX25519KeyPair();
      }
      await _treeKEM.importPublicStateJson(
        message.text,
        _uniqueId,
        _myKeyPair!,
      );
      _groupKey = await _treeKEM.deriveGroupKey();
      _encryptionReady = true;
      _endpointToMemberId[fromEndpoint] = message.senderId;
      _statusController.add("Encryption keys received");
    } catch (e) {
      print("Failed to process key exchange: $e");
    }
  }
  
  Future<void> _handleKeyUpdateMessage(
    MeshMessage message,
    String fromEndpoint,
  ) async {
    try {
      if (_myKeyPair == null) return;
      await _treeKEM.importPublicStateJson(
        message.text,
        _uniqueId,
        _myKeyPair!,
      );
      _groupKey = await _treeKEM.deriveGroupKey();
      _statusController.add("Group key updated");
      
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message.toJson())));
      _forwardMessage(bytes, excludeEndpoint: fromEndpoint);
    } catch (e) {
      print("Failed to process key update: $e");
    }
  }
  
  Future<void> _broadcastKeyUpdate() async {
    try {
      final treeState = await _treeKEM.exportPublicStateJson();
      final message = MeshMessage(
        id: "${_uniqueId}_keyupd_${DateTime.now().millisecondsSinceEpoch}",
        senderId: _uniqueId,
        senderName: _userName,
        text: treeState,
        timestamp: DateTime.now(),
        type: MeshMessageType.keyUpdate,
      );
      
      _seenMessageIds.add(message.id);
      final jsonString = jsonEncode(message.toJson());
      final bytes = Uint8List.fromList(utf8.encode(jsonString));
      
      for (final endpointId in _connectedEndpoints.keys) {
        try {
          await Nearby().sendBytesPayload(endpointId, bytes);
        } catch (e) {
          print("Failed to send key update to $endpointId: $e");
        }
      }
    } catch (e) {
      print("Failed to broadcast key update: $e");
    }
  }
  
  Future<void> _handleMemberLeftTreeKEM(
    String memberId,
    String endpointId,
  ) async {
    try {
      await _treeKEM.removeMember(memberId);
      _groupKey = await _treeKEM.deriveGroupKey();
      _statusController.add("Group key rotated (member left)");
      
      await _broadcastKeyUpdate();
    } catch (e) {
      print("Failed to re-key after member departure: $e");
    }
  }
  
  void dispose() {
    stopMesh();
    _peersController.close();
    _messageController.close();
    _statusController.close();
    _groupsController.close();
    _leaderChangeController.close();
  }
}
