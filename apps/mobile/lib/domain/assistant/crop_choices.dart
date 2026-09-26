/// Catching a crop name that is close to — but not — one the planner knows.
///
/// "'Tatoes" could be tomatoes or potatoes. Sending it as typed leaves the
/// model to guess, and a guessed crop becomes a plan the farmer did not ask
/// for. So before a message is sent, every word is checked against the
/// server planner's fixed crop list (`CropConstraint.crop` in the contract);
/// a near miss stops the send and asks, with one button per possible crop.
///
/// This reads only what the farmer typed and the fixed list. Nothing the
/// model wrote is involved, and the same words always give the same buttons.
library;

import 'assistant_models.dart';

/// A word that looks like a crop name but is not one exactly.
class CropQuestion {
  /// The word as typed, so it can be replaced in the message.
  final String word;

  /// The crops it could mean, closest first, then in list order. One entry
  /// means "did you mean …?"; more means the word is genuinely ambiguous.
  final List<ServerCrop> options;

  /// Where [word] starts in the message it was found in. The word is
  /// replaced there, found by the same pattern that found it — not by a
  /// word boundary, which a digit or underscore next to it would hide.
  final int start;

  const CropQuestion(this.word, this.options, {this.start = -1});
}

/// Every spelling that already means exactly one crop.
const _exact = <String, ServerCrop>{
  'butternut': ServerCrop.butternut,
  'butternuts': ServerCrop.butternut,
  'cabbage': ServerCrop.cabbage,
  'cabbages': ServerCrop.cabbage,
  'carrot': ServerCrop.carrots,
  'carrots': ServerCrop.carrots,
  'bean': ServerCrop.greenBeans,
  'beans': ServerCrop.greenBeans,
  'onion': ServerCrop.onions,
  'onions': ServerCrop.onions,
  'potato': ServerCrop.potatoes,
  'potatoes': ServerCrop.potatoes,
  'spinach': ServerCrop.spinach,
  'tomato': ServerCrop.tomatoes,
  'tomatoes': ServerCrop.tomatoes,
};

/// The spellings a near miss is measured against. Only names of six letters
/// or more: short ones sit one letter away from ordinary words ("beans" from
/// "means", "onion" from "union"), and asking about those would be noise.
final _fuzzyTargets = {
  for (final entry in _exact.entries)
    if (entry.key.length >= 6) entry.key: entry.value,
};

/// The first word in [message] that is close to a crop name without being
/// one, or null when there is nothing to ask.
CropQuestion? cropQuestionFor(String message) {
  for (final match in RegExp(r'[A-Za-z]+').allMatches(message)) {
    final word = match.group(0)!;
    final lower = word.toLowerCase();
    if (lower.length < 5 || _exact.containsKey(lower)) continue;

    final best = <ServerCrop, int>{};
    for (final entry in _fuzzyTargets.entries) {
      final distance = _distance(lower, entry.key);
      // One letter off for ordinary words. Two against the long names
      // (tomatoes, potatoes, cabbages, butternut), where a dropped syllable
      // still leaves plainly the same word; the short names sit too close to
      // everyday words for that.
      final allowed = lower.length >= 6 && entry.key.length >= 8 ? 2 : 1;
      if (distance > allowed) continue;
      final previous = best[entry.value];
      if (previous == null || distance < previous) {
        best[entry.value] = distance;
      }
    }
    if (best.isEmpty) continue;

    final options = best.keys.toList()
      ..sort((a, b) {
        final byDistance = best[a]!.compareTo(best[b]!);
        return byDistance != 0 ? byDistance : a.index.compareTo(b.index);
      });
    return CropQuestion(word, options, start: match.start);
  }
  return null;
}

/// [message] with [question]'s word replaced by the crop the farmer chose.
String resolveCropQuestion(
  String message,
  CropQuestion question,
  ServerCrop crop,
) {
  final word = question.word;
  final start = question.start;
  final at =
      start >= 0 &&
          start + word.length <= message.length &&
          message.startsWith(word, start)
      ? start
      : message.indexOf(word);
  if (at < 0) return message;
  return message.replaceRange(at, at + word.length, crop.label.toLowerCase());
}

/// Levenshtein distance. The words are short; the plain table is fine.
int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return previous[b.length];
}
