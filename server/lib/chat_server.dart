/// A small in-memory chat server for the easy_socket demo.
///
/// Each connection picks the message format the server speaks with
/// `?format=`: `envelope` (`{"type", "payload"}`, the default), `event`
/// (`{"event", "data"}`) or `array` (`["name", data]`). The server reads any of
/// them, and easy_socket on the client detects and mirrors whichever it gets.
///
/// When [ChatServer.token] is set, connections must pass `?token=` with that
/// value or are closed with code 4401.
///
/// Client → server:
/// * `join`    `{name, room}`
/// * `message` `{name, room, text, clientId?}` (joins implicitly, so queued messages
///   sent right after a reconnect are never lost)
/// * `typing`  `{isTyping}`
/// * `ping`    replied to with `pong`
/// * `drop`    the server closes the connection (1001), so it reconnects
/// * `kick`    the server closes with 1008, which tells clients not to retry
///
/// Server → client:
/// * `welcome`     `{rooms}` (sent on every connection)
/// * `joined`      `{room, users, history}`
/// * `presence`    `{room, users}`
/// * `message`     `{id, room, name, text, sentAt, clientId?}`
/// * `typing`      `{room, name, isTyping}`
/// * `error`       `{message, code?}` (`name_taken` when a name is in use)
library;

import 'dart:convert';
import 'dart:io';

import 'package:easy_socket/easy_socket.dart';

/// The message shapes the server can speak.
enum WireFormat {
  envelope,
  event,
  array;

  static WireFormat parse(String? value) =>
      values.firstWhere((f) => f.name == value, orElse: () => envelope);
}

class ChatServer {
  ChatServer({this.historyLimit = 50, this.token, this.maxTextLength = 1000});

  static const rooms = ['general', 'flutter', 'random'];

  final int historyLimit;

  /// Required `?token=` value, or `null` to accept any connection.
  final String? token;

  /// Longer messages are cut to this length.
  final int maxTextLength;
  final _clients = <WebSocket, _Client>{};
  final _history = {for (final r in rooms) r: <Map<String, Object?>>[]};
  HttpServer? _http;
  int _nextId = 1;

  int get port => _http!.port;

  /// Listens on [port] (0 picks a free one). Pass [InternetAddress.anyIPv4]
  /// as [address] to accept connections from other machines.
  Future<void> start({
    int port = 8080,
    bool log = false,
    InternetAddress? address,
  }) async {
    _http = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _http!.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        // Also the health check for hosting and uptime monitors.
        request.response
          ..statusCode = HttpStatus.ok
          ..write('easy_chat server is running. ${_clients.length} connected.')
          ..close();
        return;
      }
      final query = request.uri.queryParameters;
      final ws = await WebSocketTransformer.upgrade(request);
      if (token != null && query['token'] != token) {
        await ws.close(4401, 'Invalid token');
        return;
      }
      final format = WireFormat.parse(query['format']);
      final client = _clients[ws] = _Client(ws, format, log);
      client.send('welcome', {'rooms': rooms});
      ws.listen(
        (frame) => _onFrame(client, frame),
        onDone: () => _onLeave(client),
        onError: (_) => _onLeave(client),
      );
    });
  }

  Future<void> stop() async {
    for (final ws in _clients.keys.toList()) {
      await ws.close();
    }
    await _http?.close(force: true);
  }

  void _onFrame(_Client client, Object? frame) {
    // easy_socket's codec reads any of the formats.
    final event = frame is String ? client.codec.decode(frame) : null;
    if (event == null || !_isNamed(event)) {
      return client.send('error', {'message': 'Expected a named event.'});
    }
    final payload = event.data;
    final data = payload is Map<String, dynamic>
        ? payload
        : <String, dynamic>{};
    client.log('← ${event.name} $data');

    switch (event.name) {
      case 'ping':
        client.send('pong', null);
      case 'drop':
        client.ws.close(1001, 'Dropped on request');
      case 'kick':
        client.ws.close(1008, 'Kicked on request');
      case 'join':
        _join(client, data['name'], data['room']);
      case 'message':
        if (client.room != data['room'] || client.name == null) {
          if (!_join(client, data['name'], data['room'])) return;
        }
        var text = (data['text'] as String? ?? '').trim();
        if (text.isEmpty) return;
        if (text.length > maxTextLength) {
          text = text.substring(0, maxTextLength);
        }
        _setTyping(client, false);
        final message = {
          'id': _nextId++,
          'room': client.room,
          'name': client.name,
          'text': text,
          'sentAt': DateTime.now().toUtc().toIso8601String(),
          if (data['clientId'] case final String clientId) 'clientId': clientId,
        };
        final history = _history[client.room]!..add(message);
        if (history.length > historyLimit) history.removeAt(0);
        _broadcast(client.room!, 'message', message);
      case 'typing':
        _setTyping(client, data['isTyping'] == true);
      default:
        client.send('error', {'message': 'Unknown event: ${event.name}'});
    }
  }

  /// Unnamed frames decode as [SocketEvent.fallbackName], which is also the
  /// name of a chat message, so check that the name was really sent.
  bool _isNamed(SocketEvent event) {
    if (event.name != SocketEvent.fallbackName) return true;
    final Object? value;
    try {
      value = jsonDecode(event.raw as String);
    } on FormatException {
      return false;
    }
    return switch (value) {
      [final String name, _] => name == event.name,
      final Map<String, dynamic> map => AutoCodec.nameKeys.any(
        (k) => map[k] == event.name,
      ),
      _ => false,
    };
  }

  bool _join(_Client client, Object? name, Object? room) {
    if (name is! String || name.trim().isEmpty || name.trim().length > 24) {
      client.send('error', {
        'message': 'A name of 1 to 24 characters is required.',
      });
      return false;
    }
    if (room is! String || !rooms.contains(room)) {
      client.send('error', {'message': 'Unknown room: $room'});
      return false;
    }
    final taken = _clients.values.any(
      (c) => c != client && c.name?.toLowerCase() == name.trim().toLowerCase(),
    );
    if (taken) {
      client.send('error', {
        'code': 'name_taken',
        'message': 'The name "${name.trim()}" is already in use.',
      });
      return false;
    }
    final previous = client.room;
    _setTyping(client, false);
    client
      ..name = name.trim()
      ..room = room;
    if (previous != null && previous != room) _sendPresence(previous);
    client.send('joined', {
      'room': room,
      'users': _usersIn(room),
      'history': _history[room],
    });
    _sendPresence(room);
    return true;
  }

  void _onLeave(_Client client) {
    _clients.remove(client.ws);
    final room = client.room;
    if (room == null) return;
    _setTyping(client, false);
    _sendPresence(room);
  }

  void _setTyping(_Client client, bool isTyping) {
    final room = client.room;
    if (room == null || client.isTyping == isTyping) return;
    client.isTyping = isTyping;
    _broadcast(room, 'typing', {
      'room': room,
      'name': client.name,
      'isTyping': isTyping,
    }, except: client);
  }

  void _sendPresence(String room) =>
      _broadcast(room, 'presence', {'room': room, 'users': _usersIn(room)});

  List<String> _usersIn(String room) => {
    for (final c in _clients.values)
      if (c.room == room && c.name != null) c.name!,
  }.toList()..sort();

  void _broadcast(
    String room,
    String type,
    Object? payload, {
    _Client? except,
  }) {
    for (final c in _clients.values) {
      if (c.room == room && c != except) c.send(type, payload);
    }
  }
}

class _Client {
  _Client(this.ws, this.format, this._log);
  final WebSocket ws;
  final WireFormat format;
  final codec = AutoCodec();
  final bool _log;
  String? name;
  String? room;
  bool isTyping = false;

  void send(String type, Object? payload) {
    if (ws.closeCode != null) return;
    log('→ $type');
    try {
      ws.add(
        jsonEncode(switch (format) {
          WireFormat.envelope => {'type': type, 'payload': payload},
          WireFormat.event => {'event': type, 'data': payload},
          WireFormat.array => [type, payload],
        }),
      );
    } on StateError {
      // The socket closed between the check and the write.
    }
  }

  void log(String message) {
    if (_log) print('[${name ?? 'anon'}] $message');
  }
}
