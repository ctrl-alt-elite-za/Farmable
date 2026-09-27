import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/utils/ids.dart';
import '../../domain/auth/auth_models.dart';

class ChallengeRequest {
  final String state;
  final Uri url;
  const ChallengeRequest(this.state, this.url);
}

class AuthChallenge extends ChangeNotifier {
  final String baseUrl;
  final bool allowLocalHttp;
  final Duration timeout;
  ChallengeRequest? _active;
  ChallengeRequest? get active => _active;
  Completer<String>? _result;
  Timer? _timer;
  bool _disposed = false;

  AuthChallenge(
    this.baseUrl, {
    this.allowLocalHttp = false,
    this.timeout = const Duration(minutes: 2),
  });

  Future<String> requestToken(String action) async {
    final base = Uri.tryParse(baseUrl);
    final localHttp =
        allowLocalHttp &&
        base?.scheme == 'http' &&
        const {
          'localhost',
          '127.0.0.1',
          '10.0.2.2',
          '::1',
        }.contains(base?.host);
    if (_disposed ||
        _active != null ||
        !const {'sign_up', 'login'}.contains(action) ||
        base == null ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment ||
        (base.scheme != 'https' && !localHttp)) {
      throw const AuthException(AuthFailure.unavailable);
    }
    final state = newUuid();
    final result = Completer<String>();
    _result = result;
    _active = ChallengeRequest(
      state,
      base
          .resolve('/auth/turnstile')
          .replace(queryParameters: {'action': action, 'state': state}),
    );
    _timer = Timer(timeout, cancel);
    notifyListeners();
    return result.future;
  }

  void receive(String state, String message) {
    if (_active?.state != state) return;
    try {
      if (message.length > 4096) return cancel();
      final body = jsonDecode(message);
      if (body is! Map<String, dynamic> || body['state'] is! String) {
        return cancel();
      }
      if (body['state'] != state) return;
      final token = body['token'];
      if (body['status'] != 'success' ||
          token is! String ||
          token.isEmpty ||
          token.length > 2048) {
        return cancel();
      }
      _finish(token);
    } catch (_) {
      cancel();
    }
  }

  void cancel() => _finish(null);

  void _finish(String? token) {
    final result = _result;
    if (result == null) return;
    _timer?.cancel();
    _result = null;
    _active = null;
    if (token == null) {
      result.completeError(const AuthException(AuthFailure.unavailable));
    } else {
      result.complete(token);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

bool challengeNavigationAllowed(Uri page, String target, bool isMainFrame) {
  final uri = Uri.tryParse(target);
  if (isMainFrame) return uri == page;
  return target == 'about:blank' ||
      target == 'about:srcdoc' ||
      (uri?.scheme == 'https' &&
          uri?.host == 'challenges.cloudflare.com' &&
          uri?.userInfo == '' &&
          uri?.port == 443);
}
