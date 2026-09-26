/// Asks the server about an account's farm: whether it has any sections at
/// all, and what it is called.
///
/// The phone's copy is not enough to decide that. The sync controller saves
/// the farm row and pulls its sections as two steps, so a pull that fails on
/// a bad signal leaves a farm on the phone with no sections under it — and a
/// farmer who has been farming for a year would be sent through "first farm
/// setup", renaming their real farm. Setup only opens on the server's word.
library;

import '../auth/api_auth_service.dart';

/// True when the server says the farm has no sections, false when it has
/// some, and null when it could not be asked — which callers treat as "not
/// confirmed empty", never as empty.
Future<bool?> serverFarmHasNoSections(
  ApiAuthService auth,
  String farmId,
) async {
  try {
    final response = await auth.authorized(
      'GET',
      '/farms/$farmId/sections',
      query: {'limit': '1'},
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return null;
    final data = response.data;
    if (data is! Map || data['items'] is! List) return null;
    return (data['items'] as List).isEmpty;
  } on Object {
    return null;
  }
}

/// What the server calls the account's farm right now, from `GET /farms`, or
/// null when it could not be asked. Never a cached copy.
Future<String?> serverFarmName(ApiAuthService auth, String farmId) async {
  try {
    final response = await auth.authorized('GET', '/farms');
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return null;
    final data = response.data;
    final items = data is Map ? data['items'] : null;
    if (items is! List) return null;
    for (final farm in items) {
      if (farm is Map && farm['id'] == farmId && farm['name'] is String) {
        return farm['name'] as String;
      }
    }
    return null;
  } on Object {
    return null;
  }
}
