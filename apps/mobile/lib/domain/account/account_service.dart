/// The port the Profile screens are written against: account details, privacy
/// choices, export and deletion.
///
/// Like [AuthService], two implementations ship — the real one over the
/// `/account/*` routes (`data/account/api_account_service.dart`) and a local
/// demo (`data/account/demo_account_service.dart`) — chosen by the same
/// `demoAuthProvider`. Every method either returns or throws [AuthException].
library;

import 'account_models.dart';

abstract class AccountService {
  /// What the phone holds, without touching the network. Null when nobody is
  /// signed in or nothing has been saved yet.
  Future<AccountSnapshot?> cached();

  /// Sends any pending edits, then fetches the account fresh.
  ///
  /// With no signal, returns [cached] — pending edits stay pending — rather
  /// than failing: offline is normal here.
  Future<AccountSnapshot?> refresh();

  /// Sends pending edits if there are any, and does nothing — no network at
  /// all — if there are none. What launch calls, so edits made offline reach
  /// the server the next time the app opens with a signal.
  Future<void> syncPending();

  /// Saves the changes on this phone first, then tries to send them. Returns
  /// the snapshot either way; [AccountSnapshot.hasPendingChanges] says which.
  ///
  /// A field left null is unchanged.
  Future<AccountSnapshot> updateDetails({
    String? firstName,
    String? surname,
    AppLanguage? language,
    String? farmName,
  });

  /// Records the farmer's privacy choice on this phone.
  Future<AccountSnapshot> setConsent({required bool externalProcessing});

  /// The copy of the farmer's data on this phone, if one exists and has not
  /// expired. Expired copies are deleted by this call.
  Future<ExportFile?> currentExport();

  /// Fetches the farmer's data and saves it on this phone, replacing any
  /// earlier copy.
  Future<ExportFile> export(ExportFormat format);

  /// Deletes the copy on this phone, before it would expire.
  Future<void> removeExport();

  /// Permanently deletes the account on the server, then wipes this phone.
  ///
  /// [password] is re-entered on purpose: a phone left unlocked is not
  /// consent to deletion. A wrong one is [AuthFailure.invalidCredentials] and
  /// changes nothing anywhere.
  ///
  /// A missing or unreliable reply returns [DeletionOutcome.unconfirmed],
  /// without clearing the phone or automatically replaying the request.
  /// Only a confirmed success permits the local wipe.
  Future<DeletionOutcome> deleteAccount({required String password});

  /// Forgets the account data on this phone — profile, pending edits,
  /// privacy choices, exports. Called on sign-out, so the next person to log
  /// in on this phone never sees the last one's details.
  Future<void> forget();
}
