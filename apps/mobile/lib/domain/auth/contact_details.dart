/// Phone numbers, email addresses, and the masks used to name them back.
///
/// Kept out of the widgets so the rules can be asserted directly. The country
/// list is short on purpose: South Africa and its neighbours, plus the two
/// codes a returning diaspora number actually uses. A 240-entry picker is a
/// scrolling problem, not a feature, and guide §8 asks only that the country
/// *can* be changed.
library;

/// A dialling country.
class DiallingCountry {
  final String isoCode;
  final String name;

  /// With the plus, because that is how it is shown and how it is stored.
  final String dialCode;

  /// The emoji flag is decoration. It never appears without [dialCode] beside
  /// it, so a device with no flag glyphs still shows a usable control.
  final String flag;

  const DiallingCountry({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.flag,
  });
}

/// Guide §8: South Africa preselected, and first in the list because the
/// list is read top down; the rest are alphabetical.
const DiallingCountry defaultCountry = DiallingCountry(
  isoCode: 'ZA',
  name: 'South Africa',
  dialCode: '+27',
  flag: '\u{1F1FF}\u{1F1E6}',
);

const List<DiallingCountry> diallingCountries = [
  defaultCountry,
  DiallingCountry(
    isoCode: 'BW',
    name: 'Botswana',
    dialCode: '+267',
    flag: '\u{1F1E7}\u{1F1FC}',
  ),
  DiallingCountry(
    isoCode: 'SZ',
    name: 'Eswatini',
    dialCode: '+268',
    flag: '\u{1F1F8}\u{1F1FF}',
  ),
  DiallingCountry(
    isoCode: 'LS',
    name: 'Lesotho',
    dialCode: '+266',
    flag: '\u{1F1F1}\u{1F1F8}',
  ),
  DiallingCountry(
    isoCode: 'MZ',
    name: 'Mozambique',
    dialCode: '+258',
    flag: '\u{1F1F2}\u{1F1FF}',
  ),
  DiallingCountry(
    isoCode: 'NA',
    name: 'Namibia',
    dialCode: '+264',
    flag: '\u{1F1F3}\u{1F1E6}',
  ),
  DiallingCountry(
    isoCode: 'ZW',
    name: 'Zimbabwe',
    dialCode: '+263',
    flag: '\u{1F1FF}\u{1F1FC}',
  ),
  DiallingCountry(
    isoCode: 'GB',
    name: 'United Kingdom',
    dialCode: '+44',
    flag: '\u{1F1EC}\u{1F1E7}',
  ),
  DiallingCountry(
    isoCode: 'US',
    name: 'United States',
    dialCode: '+1',
    flag: '\u{1F1FA}\u{1F1F8}',
  ),
];

/// Digits only, with any leading trunk zero dropped.
///
/// South Africans write their number as `082 555 0123` and say it that way
/// too. Sending `+270825550123` is the classic bug; the zero is a national
/// trunk prefix and does not survive internationalisation.
String nationalDigits(String typed) {
  final digits = typed.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('0') ? digits.substring(1) : digits;
}

/// The full international number, as stored and sent.
String internationalPhone(DiallingCountry country, String typed) =>
    '${country.dialCode}${nationalDigits(typed)}';

/// Long enough to be a real subscriber number, short enough to be one.
///
/// Not a per-country length table: those go stale, and being wrong about
/// Mozambique's numbering plan would block a real farmer from signing up.
/// The range rejects what is obviously a typo and accepts everything else.
bool isPlausiblePhone(String typed) {
  final digits = nationalDigits(typed);
  return digits.length >= 7 && digits.length <= 12;
}

/// Deliberately permissive.
///
/// The only thing a client can honestly check is that there is something, an
/// `@`, and a dotted domain after it. Anything stricter rejects addresses that
/// work — and the code we send is what actually proves the address exists.
bool isPlausibleEmail(String typed) {
  final value = typed.trim();
  if (value.length < 6 || value.contains(' ')) return false;
  return RegExp(r'^[^@]+@[^@.]+\.[^@]+$').hasMatch(value);
}

/// `+27 •• ••• •123` — enough for the farmer to recognise their own number,
/// not enough for someone reading over their shoulder to learn it.
String maskPhone(String international) {
  final plus = international.startsWith('+');
  final digits = international.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return international;

  final tail = digits.substring(digits.length - 3);
  // Longest dial code in the list is three digits; masking from the fourth
  // onwards keeps the country visible without parsing the plan.
  final head = digits.substring(0, digits.length > 11 ? 3 : 2);
  return '${plus ? '+' : ''}$head •• ••• •$tail';
}

/// `s••••@gmail.com` — first letter, then the domain, which is what tells
/// someone which of their addresses this is.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at < 1) return email;
  final local = email.substring(0, at);
  final domain = email.substring(at);
  final hidden = '•' * (local.length - 1).clamp(1, 5);
  return '${local[0]}$hidden$domain';
}
