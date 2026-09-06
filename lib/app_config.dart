import 'package:shared_preferences/shared_preferences.dart';

/// Backend Colab / ngrok base URL used by the classroom demo.
class AppConfig {
  AppConfig._();

  static const prefsKey = 'colab_base_url';
  static const defaultBaseUrl = 'https://d4d7-35-192-99-20.ngrok-free.app';

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(prefsKey)?.trim();
    if (saved == null || saved.isEmpty) return defaultBaseUrl;
    return _normalize(saved);
  }

  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, _normalize(url));
  }

  static String _normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Returns null when the URL looks usable; otherwise an error message.
  static String? validateBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Enter a Colab / ngrok URL.';
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Use a full URL, e.g. https://xxxx.ngrok-free.app';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL must start with https://';
    }
    return null;
  }
}
