class Group {
  final String id;
  final String name;
  final String agenda;
  final String hostId;
  final String hostName;
  final DateTime createdAt;
  final bool isEncrypted;

  Group({
    required this.id,
    required this.name,
    required this.agenda,
    required this.hostId,
    required this.hostName,
    required this.createdAt,
    this.isEncrypted = true,
  });

  String toAdvertisingString() {
    final safeName = name.replaceAll('|', '-');
    final safeAgenda = agenda.replaceAll('|', '-');
    final safeHostName = hostName.replaceAll('|', '-');
    final encFlag = isEncrypted ? '1' : '0';
    return 'GROUP|$safeName|$safeAgenda|$safeHostName|$encFlag';
  }

  static Group? fromAdvertisingString(String data, String endpointId) {
    try {
      final parts = data.split('|');
      if (parts.length >= 4 && parts[0] == 'GROUP') {
        final encrypted = parts.length >= 5 ? parts[4] == '1' : true;
        return Group(
          id: endpointId,
          name: parts[1],
          agenda: parts[2],
          hostId: endpointId,
          hostName: parts[3],
          createdAt: DateTime.now(),
          isEncrypted: encrypted,
        );
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'agenda': agenda,
        'hostId': hostId,
        'hostName': hostName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'isEncrypted': isEncrypted,
      };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'],
        name: json['name'],
        agenda: json['agenda'],
        hostId: json['hostId'],
        hostName: json['hostName'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt']),
        isEncrypted: json['isEncrypted'] ?? true,
      );

  @override
  String toString() =>
      'Group($name, agenda: $agenda, host: $hostName, encrypted: $isEncrypted)';
}
