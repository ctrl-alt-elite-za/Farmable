import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/auth/auth_challenge.dart';

class AuthChallengeHost extends StatefulWidget {
  final AuthChallenge challenge;
  final Widget child;
  final Widget Function(ChallengeRequest, AuthChallenge)? challengeViewBuilder;
  final BackButtonDispatcher? backButtonDispatcher;

  const AuthChallengeHost({
    super.key,
    required this.challenge,
    required this.child,
    this.challengeViewBuilder,
    this.backButtonDispatcher,
  });

  @override
  State<AuthChallengeHost> createState() => _AuthChallengeHostState();
}

class _AuthChallengeHostState extends State<AuthChallengeHost> {
  ChildBackButtonDispatcher? _back;

  @override
  void initState() {
    super.initState();
    _back = widget.backButtonDispatcher?.createChildBackButtonDispatcher()
      ?..addCallback(_onBack);
    widget.challenge.addListener(_onChallenge);
  }

  void _onChallenge() {
    if (widget.challenge.active != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      _back?.takePriority();
    }
  }

  Future<bool> _onBack() async {
    if (widget.challenge.active == null) return false;
    widget.challenge.cancel();
    return true;
  }

  @override
  void dispose() {
    widget.challenge.removeListener(_onChallenge);
    _back?.removeCallback(_onBack);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.challenge,
    builder: (context, _) {
      final challenge = widget.challenge;
      final request = challenge.active;
      return Stack(
        children: [
          ExcludeFocus(
            excluding: request != null,
            child: ExcludeSemantics(
              excluding: request != null,
              child: widget.child,
            ),
          ),
          if (request != null) ...[
            const ModalBarrier(dismissible: false, color: Colors.black54),
            FocusScope(
              autofocus: true,
              child: Dialog(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: 260,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Verify to continue',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 180,
                            child:
                                widget.challengeViewBuilder?.call(
                                  request,
                                  challenge,
                                ) ??
                                _ChallengeWebView(
                                  key: ValueKey(request.state),
                                  request: request,
                                  challenge: challenge,
                                ),
                          ),
                          TextButton(
                            onPressed: challenge.cancel,
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _ChallengeWebView extends StatefulWidget {
  final ChallengeRequest request;
  final AuthChallenge challenge;
  const _ChallengeWebView({
    super.key,
    required this.request,
    required this.challenge,
  });

  @override
  State<_ChallengeWebView> createState() => _ChallengeWebViewState();
}

class _ChallengeWebViewState extends State<_ChallengeWebView> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _fail() {
    if (mounted && widget.challenge.active?.state == widget.request.state) {
      widget.challenge.cancel();
    }
  }

  Future<void> _load() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'FarmableChallenge',
        onMessageReceived: (message) {
          if (mounted) {
            widget.challenge.receive(widget.request.state, message.message);
          }
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              challengeNavigationAllowed(
                widget.request.url,
                request.url,
                request.isMainFrame,
              )
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _fail();
          },
          onHttpError: (error) {
            if (error.request?.uri == widget.request.url) _fail();
          },
        ),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
      await controller.loadRequest(widget.request.url);
    } catch (_) {
      _fail();
    }
  }

  @override
  void dispose() {
    // Remove the bridge before the native view can finish a stale request.
    final controller = _controller;
    if (controller != null) {
      unawaited(
        controller
            .removeJavaScriptChannel('FarmableChallenge')
            .catchError((Object _) {}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller == null
      ? const Center(child: CircularProgressIndicator())
      : WebViewWidget(controller: _controller!);
}
