import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';

class EnvConfig {
  // Private constructor to prevent instantiation
  EnvConfig._();

  /// Load environment variables from .env file
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: ".env");
      debugPrint("✅ Environment variables loaded successfully");
    } catch (error) {
      debugPrint("🔥 Error loading .env file: $error");
      debugPrint("⚠️ Make sure .env file exists in project root");
    }
  }

  /// Get base API URL
  static String get baseUrl {
    final url = dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:5000/api';
    debugPrint("📡 Using BASE_URL: $url");
    return url;
  }

  /// Get WebSocket URL
  static String get socketUrl {
    final url = dotenv.env['SOCKET_URL'] ?? 'http://10.0.2.2:5000';
    debugPrint("🔌 Using SOCKET_URL: $url");
    return url;
  }

  /// Get API timeout duration
  static Duration get apiTimeout {
    final timeoutSeconds = int.tryParse(dotenv.env['API_TIMEOUT'] ?? '30') ?? 30;
    return Duration(seconds: timeoutSeconds);
  }

  /// Check if debug mode is enabled
  static bool get isDebugMode {
    final debug = dotenv.env['DEBUG_MODE']?.toLowerCase() ?? 'true';
    return debug == 'true';
  }

  /// Print all loaded environment variables (for debugging)
  static void printConfig() {
    if (!isDebugMode) return;

    debugPrint("🔧 ===== ENVIRONMENT CONFIGURATION =====");
    debugPrint("📡 BASE_URL: $baseUrl");
    debugPrint("🔌 SOCKET_URL: $socketUrl");
    debugPrint("⏱️ API_TIMEOUT: ${apiTimeout.inSeconds}s");
    debugPrint("🐛 DEBUG_MODE: $isDebugMode");
    debugPrint("🔧 =====================================");
  }

  /// Validate that required environment variables are set
  static bool validate() {
    final requiredVars = ['BASE_URL'];
    final missingVars = <String>[];

    for (final varName in requiredVars) {
      if (dotenv.env[varName] == null || dotenv.env[varName]!.isEmpty) {
        missingVars.add(varName);
      }
    }

    if (missingVars.isNotEmpty) {
      debugPrint("🔥 Missing required environment variables: ${missingVars.join(', ')}");
      return false;
    }

    debugPrint("✅ All required environment variables are set");
    return true;
  }
}