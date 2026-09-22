/// The one thing Forgot password has to hand to Reset password.
///
/// Held in a provider rather than passed as a route `extra`, for the reason
/// `router.dart` gives about the whole route table: a screen reached by path
/// must work, and an `extra` is null on a cold open. This way `/auth/reset-
/// password` reached directly finds no request and says so, instead of
/// rendering a form that cannot submit.
///
/// It is not persisted. A reset that was interrupted by the app closing
/// should start again — the code was sent to a device the farmer has in
/// front of them, and asking for a fresh one costs nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/auth/auth_models.dart';
import '../../domain/auth/contact_details.dart';

class ResetRequest {
  final LoginMode mode;
  final DiallingCountry country;

  /// As typed. The international composition happens in the view model, the
  /// same way it does for sign-up and login.
  final String identifier;

  const ResetRequest({
    required this.mode,
    required this.country,
    required this.identifier,
  });

  String get masked => mode == LoginMode.email
      ? maskEmail(identifier.trim())
      : maskPhone(internationalPhone(country, identifier));
}

class ResetFlow extends Notifier<ResetRequest?> {
  @override
  ResetRequest? build() => null;

  void start(ResetRequest request) => state = request;

  void clear() => state = null;
}

final resetFlowProvider = NotifierProvider<ResetFlow, ResetRequest?>(
  ResetFlow.new,
);
