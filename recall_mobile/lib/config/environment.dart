import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Environment configuration for API connectivity.
///
/// For beginners:
/// - This file manages the API base URL based on the environment (development vs production)
/// - During development, your phone needs to connect to your laptop's local server over WiFi
/// - In production, it will connect to a real API server on the internet
///
/// How WiFi connectivity works:
/// - Your phone and laptop must be on the same WiFi network
/// - Instead of "localhost" (which means "this device"), we use your laptop's WiFi IP address
/// - Example: If your laptop's WiFi IP is 192.168.1.100, the phone will connect to that
class Environment {
  /// IMPORTANT: Update this with your laptop's WiFi IP address!
  ///
  /// How to find your WiFi IP:
  /// - Windows: Open Command Prompt, run: ipconfig
  ///   Look for "Wireless LAN adapter Wi-Fi" → "IPv4 Address"
  ///   Example: 192.168.1.100
  ///
  /// - Mac: Open Terminal, run: ifconfig | grep "inet "
  ///   Look for an address like 192.168.x.x (not 127.0.0.1)
  ///
  /// - Linux: Open Terminal, run: ip addr show
  ///   Look for your WiFi adapter's inet address
  static const String _laptopWifiIp = ''; // Set to your laptop's WiFi IP for local dev

  /// Development API URL (uses your laptop's WiFi IP)
  /// Port 8000 is where the FastAPI backend runs
  static const String _developmentUrl = 'https://YOUR_BACKEND_DOMAIN/api';

  /// Production API URL (deployed backend on Render)
  /// This will be used when you deploy the app to production
  static const String _productionUrl = 'https://YOUR_BACKEND_DOMAIN/api';

  /// Get the appropriate API base URL based on build mode.
  ///
  /// Priority order:
  /// 1. Custom URL from --dart-define=API_URL=...
  /// 2. Production URL if building in release mode
  /// 3. Development URL (WiFi IP) for debug builds
  ///
  /// Usage:
  /// - Debug build (default): flutter run
  ///   → Uses _developmentUrl (WiFi IP)
  ///
  /// - Debug with custom URL: flutter run --dart-define=API_URL=http://192.168.1.50:8000/api
  ///   → Uses the custom URL you provide
  ///
  /// - Release build: flutter build apk --release
  ///   → Uses _productionUrl
  static String get apiBaseUrl {
    // Check if custom URL provided via dart-define
    // This allows you to override the URL without changing code
    const customUrl = String.fromEnvironment('API_URL');
    if (customUrl.isNotEmpty) {
      return customUrl;
    }

    // Use production URL in release builds
    // dart.vm.product is true only in release builds
    const bool isProduction = bool.fromEnvironment('dart.vm.product');
    if (isProduction) {
      return _productionUrl;
    }

    // Use development URL (WiFi IP) in debug builds
    return _developmentUrl;
  }

  /// Test if backend is reachable.
  ///
  /// Use this to debug connectivity issues.
  /// Call this before making API requests to verify the connection.
  ///
  /// Returns:
  /// - true if backend is reachable and healthy
  /// - false if connection failed
  ///
  /// Usage:
  ///   final isConnected = await Environment.testConnection();
  ///   if (!isConnected) {
  ///     print('Cannot reach backend!');
  ///   }
  static Future<bool> testConnection() async {
    try {
      final dio = Dio();

      // Remove /api suffix to hit the health check endpoint
      final baseUrl = apiBaseUrl.replaceAll('/api', '');

      debugPrint('Testing connection to: $baseUrl/health');

      final response = await dio.get(
        '$baseUrl/health',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      if (response.statusCode == 200) {
        debugPrint('✓ Backend is reachable!');
        debugPrint('Response: ${response.data}');
        return true;
      } else {
        debugPrint('✗ Backend returned status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('✗ Connection test failed: $e');
      debugPrint('\nTroubleshooting:');
      debugPrint('1. Is the backend running? (uvicorn main:app --host 0.0.0.0 --port 8000)');
      debugPrint('2. Are phone and laptop on the same WiFi network?');
      debugPrint('3. Is the _laptopWifiIp correct? (Currently: $_laptopWifiIp)');
      debugPrint('4. Is Windows Firewall blocking Python? (Check firewall settings)');
      return false;
    }
  }

  /// Get a user-friendly description of the current configuration.
  ///
  /// Useful for debugging and showing in a debug/settings screen.
  static String get configInfo {
    const customUrl = String.fromEnvironment('API_URL');
    const isProduction = bool.fromEnvironment('dart.vm.product');

    if (customUrl.isNotEmpty) {
      return 'Custom: $customUrl';
    } else if (isProduction) {
      return 'Production: $_productionUrl';
    } else {
      return 'Development: $_developmentUrl';
    }
  }
}
