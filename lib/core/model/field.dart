import 'protected_value.dart';

/// A single key/value field on an [Entry]. KeePass standard fields are
/// `Title`, `UserName`, `Password`, `URL`, `Notes`; anything else is a custom
/// field. Secret fields wrap their value in a [ProtectedValue].
class Field {
  Field({required this.key, required this.value});

  /// Standard KeePass field keys.
  static const String title = 'Title';
  static const String userName = 'UserName';
  static const String password = 'Password';
  static const String url = 'URL';
  static const String notes = 'Notes';

  /// Whether [key] is one of the five standard KeePass fields.
  static bool isStandardKey(String key) =>
      key == title ||
      key == userName ||
      key == password ||
      key == url ||
      key == notes;

  final String key;
  final ProtectedValue value;

  bool get isCustom => !isStandardKey(key);
  bool get isProtected => value.isProtected;
}
