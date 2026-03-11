import 'package:intl/intl.dart';

enum MessageType { sent, received }

class ChatMessage {
  final String id;
  final String text;
  final MessageType type;
  final DateTime timestamp;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.text,
    required this.type,
    required this.timestamp,
    this.senderName,
  });

  String get formattedTime => DateFormat('HH:mm').format(timestamp);
}
