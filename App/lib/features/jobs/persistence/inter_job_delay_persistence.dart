import 'package:shared_preferences/shared_preferences.dart';

const String interJobDelaySecondsPreferenceKey = 'inter_job_delay_seconds';

int readInterJobDelaySeconds(SharedPreferences prefs) {
  return prefs.getInt(interJobDelaySecondsPreferenceKey) ?? 0;
}

Future<void> saveInterJobDelaySecondsPreference(int value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(interJobDelaySecondsPreferenceKey, value);
}
