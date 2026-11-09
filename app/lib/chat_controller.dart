import 'dart:async';

import 'package:easy_socket/easy_socket.dart';
import 'package:flutter/foundation.dart';

import 'chat_message.dart';

/// All chat state, driven by an [EasySocket].
///
/// Note how little websocket code there is: no connect call, no JSON, no
/// reconnect logic. The server speaks whichever [format] was picked and
/// easy_socket detects and mirrors it. Joining happens in `onConnected`, so it
/// runs on every reconnect before any queued message goes out.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.url,
    required this.name,
    this._room = 'general',
    this.format = 'envelope',
    this.token = demoToken,
  }) {
    _socket.onError(_onSocketError);
    _unsubscribe.addAll([
      _socket.on('welcome', _onWelcome),
      _socket.on('joined', _onJoined),
      _socket.on('presence', _onPresence),
      _socket.on('message', _onMessage),
      _socket.on('typing', _onTyping),
      _socket.on('error', (data) {
        final json = data as Map<String, dynamic>;
        final error = ChatError(
          '${json['message']}',
          code: json['code'] as String?,
        );
        if (!_joined.isCompleted) {
          _joined.completeError(error);
        } else {
          _errors.add(error);
        }
      }),
    ]);
    // Nothing may await [joined] (e.g. in tests); don't report it unhandled.
    _joined.future.ignore();
    _stateSub = _socket.onStateChange.listen((state) {
      connection = state;
      if (state == SocketState.connected) rejection = null;
      notifyListeners();
    });
  }

  /// The token the demo server accepts.
  static const demoToken = 'demo';

  final String url;
  final String name;

  /// The message format to ask the server for: `envelope`, `event` or
  /// `array`.
  final String format;

  /// Sent as `?token=`, fetched again on every connection.
  final String token;

  late final EasySocket _socket = EasySocket(
    url,
    queryParameters: () => {'token': token, 'format': format},
    onConnected: (_) => _join(),
    // Works in browsers too, where protocol pings aren't available.
    pingInterval: const Duration(seconds: 20),
    pingMessage: const {'event': 'ping'},
    // Feeds the playground's log. Shows the token as ***.
    debug: true,
    logger: _addLog,
  );

  /// What the socket did, newest last, for the playground.
  final List<LogEntry> log = [];

  /// Set when the server refused the connection (for example a kick), so
  /// easy_socket stopped retrying.
  SocketRejectedException? rejection;

  /// Whether the user chose to go offline.
  bool offline = false;
  final _unsubscribe = <void Function()>[];
  final _errors = StreamController<ChatError>.broadcast();
  final _joined = Completer<void>();

  /// Completes when the server first accepts the join, or fails with a
  /// [ChatError] if it refuses (for example [ChatError.nameTaken]).
  Future<void> get joined => _joined.future;
  late final StreamSubscription<SocketState> _stateSub;
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _disposed = false;
  int _clientCounter = 0;

  String _room;
  String get room => _room;

  SocketState connection = SocketState.connecting;
  List<String> rooms = const ['general'];
  List<String> users = const [];
  final List<ChatMessage> messages = [];
  final Set<String> typing = {};

  /// Errors reported by the server, for showing to the user.
  Stream<ChatError> get errors => _errors.stream;

  // ------------------------------------------------------------- actions

  void send(String text) {
    text = text.trim();
    if (text.isEmpty) return;
    final clientId =
        '$name-${_clientCounter++}-${DateTime.now().microsecondsSinceEpoch}';
    messages.add(
      ChatMessage(
        clientId: clientId,
        name: name,
        text: text,
        sentAt: DateTime.now(),
        pending: true,
      ),
    );
    // Queued by easy_socket if we're offline and sent on reconnect.
    _socket.emit('message', {
      'name': name,
      'room': _room,
      'text': text,
      'clientId': clientId,
    });
    _setTyping(false);
    notifyListeners();
  }

  // ---------------------------------------------------- playground actions

  /// Asks the server to close the connection; easy_socket reconnects.
  void dropConnection() => _socket.emit('drop');

  /// Asks the server to close with 1008, which easy_socket won't retry.
  void getKicked() => _socket.emit('kick');

  /// Closes the socket. Messages sent now wait in easy_socket's queue.
  void goOffline() {
    offline = true;
    _socket.close();
    notifyListeners();
  }

  /// Reopens the socket, skipping any retry delay.
  void goOnline() {
    offline = false;
    _socket.connect().ignore();
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  void switchRoom(String room) {
    if (room == _room) return;
    _setTyping(false);
    _room = room;
    messages.clear();
    users = const [];
    typing.clear();
    _join();
    notifyListeners();
  }

  /// Call on every keystroke; sends typing start/stop with a debounce.
  void onTextChanged(String text) {
    _typingTimer?.cancel();
    if (text.trim().isEmpty) return _setTyping(false);
    _setTyping(true);
    _typingTimer = Timer(const Duration(seconds: 2), () => _setTyping(false));
  }

  // -------------------------------------------------------------- events

  void _join() => _socket.emit('join', {'name': name, 'room': _room});

  void _onWelcome(Object? data) {
    rooms = List<String>.from((data as Map)['rooms'] as List);
    notifyListeners();
  }

  void _onJoined(Object? data) {
    final json = data as Map<String, dynamic>;
    if (json['room'] != _room) return;
    if (!_joined.isCompleted) _joined.complete();
    final pending = messages.where((m) => m.pending).toList();
    messages
      ..clear()
      ..addAll([
        for (final m in json['history'] as List)
          ChatMessage.fromJson(m as Map<String, dynamic>),
      ])
      ..addAll(pending.where((p) => !_confirmed(p.clientId)));
    users = List<String>.from(json['users'] as List);
    typing.clear();
    notifyListeners();
  }

  void _onPresence(Object? data) {
    final json = data as Map<String, dynamic>;
    if (json['room'] != _room) return;
    users = List<String>.from(json['users'] as List);
    typing.removeWhere((n) => !users.contains(n));
    notifyListeners();
  }

  void _onMessage(Object? data) {
    final json = data as Map<String, dynamic>;
    if (json['room'] != _room) return;
    final message = ChatMessage.fromJson(json);
    if (messages.any((m) => m.id != null && m.id == message.id)) return;
    final pendingIndex = messages.indexWhere(
      (m) => m.pending && m.clientId != null && m.clientId == message.clientId,
    );
    if (pendingIndex >= 0) {
      messages[pendingIndex] = message;
    } else {
      messages.add(message);
    }
    typing.remove(message.name);
    notifyListeners();
  }

  void _onTyping(Object? data) {
    final json = data as Map<String, dynamic>;
    if (json['room'] != _room) return;
    final who = json['name'] as String;
    json['isTyping'] == true ? typing.add(who) : typing.remove(who);
    notifyListeners();
  }

  void _onSocketError(Object error) {
    if (error is SocketRejectedException) {
      rejection = error;
      if (!_joined.isCompleted) {
        _joined.completeError(
          ChatError(
            'The server refused the connection (code ${error.code}'
            '${error.reason?.isNotEmpty == true ? ': ${error.reason}' : ''}). '
            "easy_socket won't retry a refused connection.",
            code: ChatError.rejected,
          ),
        );
      }
      notifyListeners();
    }
  }

  void _addLog(String line) {
    final text = line.replaceFirst('[easy_socket] ', '');
    log.add(LogEntry(DateTime.now(), text));
    if (log.length > 300) log.removeRange(0, log.length - 300);
    if (!_disposed) notifyListeners();
  }

  bool _confirmed(String? clientId) =>
      clientId != null &&
      messages.any((m) => !m.pending && m.clientId == clientId);

  void _setTyping(bool value) {
    if (value == _isTyping) return;
    _isTyping = value;
    if (!value) _typingTimer?.cancel();
    if (_socket.isConnected) _socket.emit('typing', {'isTyping': value});
  }

  @override
  void dispose() {
    _disposed = true;
    _typingTimer?.cancel();
    for (final off in _unsubscribe) {
      off();
    }
    _stateSub.cancel();
    _errors.close();
    _socket.dispose();
    super.dispose();
  }
}

/// An error reported by the server.
class ChatError {
  const ChatError(this.message, {this.code});

  final String message;

  /// Machine-readable reason, such as [nameTaken]. `null` for generic errors.
  final String? code;

  static const nameTaken = 'name_taken';

  /// The server closed the connection with a "refused" code.
  static const rejected = 'rejected';
}

/// One line of the playground log.
class LogEntry {
  const LogEntry(this.time, this.text);
  final DateTime time;
  final String text;

  /// `out`, `in`, `state`, `error` or `info`, for colouring.
  String get kind => text.startsWith('→')
      ? 'out'
      : text.startsWith('←')
      ? 'in'
      : text.startsWith('state:')
      ? 'state'
      : text.startsWith('error')
      ? 'error'
      : 'info';
}
