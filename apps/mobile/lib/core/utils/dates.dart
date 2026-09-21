/// Dates, written the way they are said.
///
/// Hand-rolled rather than delegated to `intl`, for two reasons that both
/// matter here. The app ships one locale — South African English — and the
/// phrasing the design uses ("Overdue · was due 16 Sep", "by Friday 26 Sep",
/// "In 7 days") is not a date format any locale package produces; it is a
/// sentence with a date in it. Wiring `intl` would buy a `DateFormat` and
/// still leave every one of these strings to write.
///
/// Day comes before month throughout. `20 September`, never `September 20`.
library;

const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _days = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String monthName(DateTime d) => _months[d.month - 1];

String weekdayName(DateTime d) => _days[d.weekday - 1];

/// `16 Sep`
String shortDate(DateTime d) => '${d.day} ${monthName(d).substring(0, 3)}';

/// `8 August 2026`
String longDate(DateTime d) => '${d.day} ${monthName(d)} ${d.year}';

/// `Sunday, 20 September` — the dashboard's date line.
String greetingDate(DateTime d) =>
    '${weekdayName(d)}, ${d.day} ${monthName(d)}';

/// Whole days from [from] to [to], ignoring the time of day on both.
int daysBetween(DateTime from, DateTime to) => DateTime(
  to.year,
  to.month,
  to.day,
).difference(DateTime(from.year, from.month, from.day)).inDays;

/// How a task's date is spoken relative to today.
///
/// Near dates are named — "today", "tomorrow", "Friday" — because that is how
/// a farmer holds the next week in their head. Further out, the date itself is
/// more use than a day count, so it wins.
String whenPhrase(DateTime due, DateTime today) {
  final days = daysBetween(today, due);

  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  if (days < 0) return 'Overdue · was due ${shortDate(due)}';
  if (days < 7) return '${weekdayName(due)} ${shortDate(due)}';
  if (days < 21) return 'In $days days · ${shortDate(due)}';
  return '${shortDate(due)} · about $days days';
}

/// The short form used under a row: `Cabbage Field · by Friday 26 Sep`.
String dueSuffix(DateTime due, DateTime today) {
  final days = daysBetween(today, due);
  if (days < 0) return 'overdue since ${shortDate(due)}';
  if (days == 0) return 'due today';
  if (days == 1) return 'due tomorrow';
  if (days < 7) return 'by ${weekdayName(due)} ${shortDate(due)}';
  return 'by ${shortDate(due)}';
}

/// `Today, 09:42` · `14 Sep` — how an observation stamps itself.
String observedAt(DateTime at, DateTime today) {
  final days = daysBetween(at, today);
  final time =
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  if (days == 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  return shortDate(at);
}
