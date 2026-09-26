/// The provider socket: Google's constrained v1beta Live WebSocket, opened
/// with the short-lived credential the backend minted.
///
/// ## The credential
///
/// It goes in the `Authorization: Token …` header, as Google's Python SDK
/// sends it, so it never sits in a URL. If the handshake is refused that
/// way, the one retry uses the `access_token` query parameter that Google's
/// JavaScript SDK uses — a refused handshake has not spent the credential's
/// single use. Neither form is ever logged; an exception that escapes is a
/// [LiveLinkException] carrying nothing from the request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../domain/assistant/voice.dart';

const _endpoint =
    'wss://generativelanguage.googleapis.com/ws/'
    'google.ai.generativelanguage.v1beta.GenerativeService.'
    'BidiGenerateContentConstrained';

class GeminiLiveLink implements LiveLink {
  final Duration handshake;

  const GeminiLiveLink({this.handshake = const Duration(seconds: 10)});

  /// [connecting] within [handshake]. A socket that opens after the
  /// deadline is closed, not left open on a single-use credential.
  Future<WebSocket> _within(Future<WebSocket> connecting) => connecting.timeout(
    handshake,
    onTimeout: () {
      unawaited(
        connecting.then((late) => late.close(), onError: (Object _) {}),
      );
      throw TimeoutException('handshake', handshake);
    },
  );

  @override
  Future<LiveConnection> connect(LiveCredential credential) async {
    if (credential.fake) throw const LiveLinkException(refused: true);
    try {
      return _GeminiConnection(
        await _within(
          WebSocket.connect(
            _endpoint,
            headers: {'Authorization': 'Token ${credential.credential}'},
          ),
        ),
      );
    } on WebSocketException {
      // Refused in the header form; try the query form once.
    } on TimeoutException {
      throw const LiveLinkException();
    } on SocketException {
      throw const LiveLinkException();
    } on HttpException {
      // As above: a handshake the server answered but did not upgrade.
    }
    try {
      final url = Uri.parse(_endpoint)
          .replace(queryParameters: {'access_token': credential.credential});
      return _GeminiConnection(
        await _within(WebSocket.connect(url.toString())),
      );
    } on WebSocketException {
      throw const LiveLinkException(refused: true);
    } on HttpException {
      throw const LiveLinkException(refused: true);
    } on Object {
      throw const LiveLinkException();
    }
  }
}

class _GeminiConnection implements LiveConnection {
  final WebSocket _socket;
  late final Stream<Map<String, Object?>> _messages;

  _GeminiConnection(this._socket) {
    _messages = _socket
        .map<Map<String, Object?>?>((frame) {
          try {
            // The provider sends JSON as text or as binary frames.
            final text = frame is String
                ? frame
                : utf8.decode(frame as List<int>);
            final json = jsonDecode(text);
            return json is Map ? json.cast<String, Object?>() : null;
          } on Object {
            return null;
          }
        })
        .where((m) => m != null)
        .cast<Map<String, Object?>>()
        .asBroadcastStream();
  }

  @override
  Stream<Map<String, Object?>> get messages => _messages;

  @override
  void send(Map<String, Object?> message) {
    if (_socket.readyState == WebSocket.open) {
      _socket.add(jsonEncode(message));
    }
  }

  @override
  Future<void> close() async {
    try {
      await _socket.close(WebSocketStatus.normalClosure);
    } on Object {
      // Already gone.
    }
  }
}
