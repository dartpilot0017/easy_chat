/// A chat message, either confirmed by the server or still being sent.
class ChatMessage {
  const ChatMessage({
    this.id,
    this.clientId,
    required this.name,
    required this.text,
    required this.sentAt,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as int?,
    clientId: json['clientId'] as String?,
    name: json['name'] as String? ?? '?',
    text: json['text'] as String? ?? '',
    sentAt:
        DateTime.tryParse(json['sentAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
  );

  /// Server-assigned id. `null` while [pending].
  final int? id;

  /// Id the sender attached so it can match the server's echo.
  final String? clientId;
  final String name;
  final String text;
  final DateTime sentAt;

  /// Sent by us but not yet confirmed (for example while offline).
  final bool pending;
}
