/// ISO 3166-1 alpha-2 countries for the player profile, with emoji flags.
library;

class Country {
  const Country(this.code, this.name);
  final String code;
  final String name;

  /// Flag emoji built from the two regional-indicator letters of the code.
  String get flag => flagOf(code);
}

String flagOf(String code) {
  if (code.length != 2) return '🏁';
  final up = code.toUpperCase();
  return String.fromCharCodes([0x1F1E6 + up.codeUnitAt(0) - 65, 0x1F1E6 + up.codeUnitAt(1) - 65]);
}

Country? countryByCode(String? code) {
  if (code == null) return null;
  for (final c in countries) {
    if (c.code == code.toUpperCase()) return c;
  }
  return null;
}

const _raw = 'AF:Afghanistan|AL:Albania|DZ:Algeria|AD:Andorra|AO:Angola|AG:Antigua and Barbuda|AR:Argentina|'
    'AM:Armenia|AU:Australia|AT:Austria|AZ:Azerbaijan|BS:Bahamas|BH:Bahrain|BD:Bangladesh|BB:Barbados|BY:Belarus|'
    'BE:Belgium|BZ:Belize|BJ:Benin|BT:Bhutan|BO:Bolivia|BA:Bosnia and Herzegovina|BW:Botswana|BR:Brazil|BN:Brunei|'
    'BG:Bulgaria|BF:Burkina Faso|BI:Burundi|CV:Cabo Verde|KH:Cambodia|CM:Cameroon|CA:Canada|CF:Central African Republic|'
    'TD:Chad|CL:Chile|CN:China|CO:Colombia|KM:Comoros|CG:Congo|CD:Congo (DRC)|CR:Costa Rica|CI:Côte d’Ivoire|HR:Croatia|'
    'CU:Cuba|CY:Cyprus|CZ:Czechia|DK:Denmark|DJ:Djibouti|DM:Dominica|DO:Dominican Republic|EC:Ecuador|EG:Egypt|'
    'SV:El Salvador|GQ:Equatorial Guinea|ER:Eritrea|EE:Estonia|SZ:Eswatini|ET:Ethiopia|FJ:Fiji|FI:Finland|FR:France|'
    'GA:Gabon|GM:Gambia|GE:Georgia|DE:Germany|GH:Ghana|GR:Greece|GD:Grenada|GT:Guatemala|GN:Guinea|GW:Guinea-Bissau|'
    'GY:Guyana|HT:Haiti|HN:Honduras|HK:Hong Kong|HU:Hungary|IS:Iceland|IN:India|ID:Indonesia|IR:Iran|IQ:Iraq|IE:Ireland|'
    'IT:Italy|JM:Jamaica|JP:Japan|JO:Jordan|KZ:Kazakhstan|KE:Kenya|KI:Kiribati|KW:Kuwait|KG:Kyrgyzstan|LA:Laos|'
    'LV:Latvia|LB:Lebanon|LS:Lesotho|LR:Liberia|LY:Libya|LI:Liechtenstein|LT:Lithuania|LU:Luxembourg|MO:Macao|'
    'MG:Madagascar|MW:Malawi|MY:Malaysia|MV:Maldives|ML:Mali|MT:Malta|MH:Marshall Islands|MR:Mauritania|MU:Mauritius|'
    'MX:Mexico|FM:Micronesia|MD:Moldova|MC:Monaco|MN:Mongolia|ME:Montenegro|MA:Morocco|MZ:Mozambique|MM:Myanmar|'
    'NA:Namibia|NR:Nauru|NP:Nepal|NL:Netherlands|NZ:New Zealand|NI:Nicaragua|NE:Niger|NG:Nigeria|KP:North Korea|'
    'MK:North Macedonia|NO:Norway|OM:Oman|PK:Pakistan|PW:Palau|PS:Palestine|PA:Panama|PG:Papua New Guinea|PY:Paraguay|'
    'PE:Peru|PH:Philippines|PL:Poland|PT:Portugal|PR:Puerto Rico|QA:Qatar|RO:Romania|RU:Russia|RW:Rwanda|'
    'KN:Saint Kitts and Nevis|LC:Saint Lucia|VC:Saint Vincent and the Grenadines|WS:Samoa|SM:San Marino|'
    'ST:São Tomé and Príncipe|SA:Saudi Arabia|SN:Senegal|RS:Serbia|SC:Seychelles|SL:Sierra Leone|SG:Singapore|'
    'SK:Slovakia|SI:Slovenia|SB:Solomon Islands|SO:Somalia|ZA:South Africa|KR:South Korea|SS:South Sudan|ES:Spain|'
    'LK:Sri Lanka|SD:Sudan|SR:Suriname|SE:Sweden|CH:Switzerland|SY:Syria|TW:Taiwan|TJ:Tajikistan|TZ:Tanzania|'
    'TH:Thailand|TL:Timor-Leste|TG:Togo|TO:Tonga|TT:Trinidad and Tobago|TN:Tunisia|TR:Türkiye|TM:Turkmenistan|'
    'TV:Tuvalu|UG:Uganda|UA:Ukraine|AE:United Arab Emirates|GB:United Kingdom|US:United States|UY:Uruguay|'
    'UZ:Uzbekistan|VU:Vanuatu|VA:Vatican City|VE:Venezuela|VN:Vietnam|YE:Yemen|ZM:Zambia|ZW:Zimbabwe';

final List<Country> countries = [
  for (final e in _raw.split('|')) Country(e.substring(0, 2), e.substring(3)),
];

/// Rival racers from around the world (a fresh nine are drawn for every race).
const rivalPool = <(String, String)>[
  ('LUCAS', 'BR'), ('EMMA', 'FR'), ('KENJI', 'JP'), ('SOFIA', 'ES'), ('OLIVER', 'GB'), ('AMARA', 'NG'),
  ('LIAM', 'US'), ('AISHA', 'AE'), ('MATEO', 'AR'), ('HANNA', 'DE'), ('PRIYA', 'IN'), ('CHLOE', 'CA'),
  ('LUCA', 'IT'), ('NOAH', 'AU'), ('MEI', 'CN'), ('YOUSSEF', 'MA'), ('ELIF', 'TR'), ('MAJA', 'SE'),
  ('JIN', 'KR'), ('DIEGO', 'MX'), ('FATIMA', 'EG'), ('AROHA', 'NZ'), ('KOFI', 'GH'), ('INES', 'PT'),
  ('SIPHO', 'ZA'), ('ANA', 'CL'), ('TOMAS', 'CZ'), ('LEILA', 'LB'), ('RAFAEL', 'PH'), ('NORA', 'NO'),
];
