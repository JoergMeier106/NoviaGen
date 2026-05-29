import 'package:shared_preferences/shared_preferences.dart';

const _appDataBackupType = 'noviagen_app_data_backup';
const _legacyAppDataBackupType = 'obscure_app_data_backup';

Map<String, dynamic> buildAppDataBackupPayload(SharedPreferences prefs) {
  final keys = prefs.getKeys().toList()..sort();
  return <String, dynamic>{
    'type': _appDataBackupType,
    'schema_version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'preferences': <String, Object?>{
      for (final key in keys) key: _copyPreferenceValue(prefs.get(key)),
    },
  };
}

Object? _copyPreferenceValue(Object? value) {
  if (value is List<String>) {
    return List<String>.from(value);
  }
  return value;
}

Future<void> restoreAppDataBackupPayload(Map<String, dynamic> payload) async {
  final payloadType = payload['type'];
  if (payloadType != _appDataBackupType &&
      payloadType != _legacyAppDataBackupType) {
    throw const FormatException('Unsupported app backup type.');
  }
  final preferencesPayload = payload['preferences'];
  if (preferencesPayload is! Map<dynamic, dynamic>) {
    throw const FormatException('Invalid app backup payload.');
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final sortedKeys =
      preferencesPayload.keys.map((key) => key.toString()).toList()..sort();
  for (final key in sortedKeys) {
    await _restorePreferenceValue(prefs, key, preferencesPayload[key]);
  }
}

Future<void> _restorePreferenceValue(
  SharedPreferences prefs,
  String key,
  Object? value,
) async {
  if (value == null) {
    return;
  }
  if (value is String) {
    await prefs.setString(key, value);
    return;
  }
  if (value is bool) {
    await prefs.setBool(key, value);
    return;
  }
  if (value is int) {
    await prefs.setInt(key, value);
    return;
  }
  if (value is double) {
    await prefs.setDouble(key, value);
    return;
  }
  if (value is List<dynamic> && value.every((item) => item is String)) {
    await prefs.setStringList(key, List<String>.from(value));
    return;
  }
  throw FormatException('Unsupported app backup value for $key.');
}
