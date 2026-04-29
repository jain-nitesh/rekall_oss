import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "com.rekallhq/source_app"
  private let sharedStorageChannelName = "com.rekallhq/shared_storage"
  private let lastBundleKey = "last_source_bundle_id"
  private let lastAppNameKey = "last_source_app_name"
  private let appGroupId = "group.com.rekallhq.rekall"
  private let pendingSharesKey = "flutter.pending_shares"
  private let authTokenKey = "flutter.auth_token"
  private let apiBaseUrlKey = "flutter.api_base_url"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register plugins FIRST — must happen before any Flutter/Dart code runs
    GeneratedPluginRegistrant.register(with: self)

    // Set up method channel for source app detection (optional — only if FlutterViewController is ready)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.binaryMessenger)

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "getLastSourceApp":
          let defaults = UserDefaults.standard
          let bundleId = defaults.string(forKey: self.lastBundleKey)
          let appName = defaults.string(forKey: self.lastAppNameKey)
          result([
            "bundleId": bundleId as Any,
            "appName": appName as Any
          ])
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      // Method channel for syncing auth token + API URL to app group UserDefaults
      // so the Share Extension can read them for background uploads
      let sharedStorageChannel = FlutterMethodChannel(
        name: sharedStorageChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      sharedStorageChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "syncToAppGroup":
          guard let args = call.arguments as? [String: String] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected map of strings", details: nil))
            return
          }
          guard let appGroupDefaults = UserDefaults(suiteName: self.appGroupId) else {
            result(FlutterError(code: "NO_APP_GROUP", message: "Cannot access app group", details: nil))
            return
          }
          if let token = args["auth_token"] {
            appGroupDefaults.set(token, forKey: self.authTokenKey)
          }
          if let apiUrl = args["api_base_url"] {
            appGroupDefaults.set(apiUrl, forKey: self.apiBaseUrlKey)
          }
          appGroupDefaults.synchronize()
          print("[AppDelegate] ✓ Synced auth token + API URL to app group")
          result(nil)
        case "clearFromAppGroup":
          guard let appGroupDefaults = UserDefaults(suiteName: self.appGroupId) else {
            result(FlutterError(code: "NO_APP_GROUP", message: "Cannot access app group", details: nil))
            return
          }
          appGroupDefaults.removeObject(forKey: self.authTokenKey)
          appGroupDefaults.synchronize()
          print("[AppDelegate] ✓ Cleared auth token from app group")
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if let sourceApp = options[.sourceApplication] as? String {
      persistSourceApp(bundleId: sourceApp)
    }
    return super.application(app, open: url, options: options)
  }

  // Copy pending shares from app group UserDefaults to standard UserDefaults
  // so Flutter's SharedPreferences (PendingSharesService) can read them.
  // This bridges the gap between the share extension's sandbox and the main app.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    migratePendingSharesFromAppGroup()
    syncTokenToAppGroup()
  }

  // Handle background URL session completion from Share Extension
  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    print("[AppDelegate] Background URL session completed: \(identifier)")
    completionHandler()
  }

  /// Migrate pending shares from app group UserDefaults (written by Share Extension)
  /// to standard UserDefaults (read by Flutter's SharedPreferences / PendingSharesService).
  /// Merges with any existing pending shares to avoid data loss.
  private func migratePendingSharesFromAppGroup() {
    guard let appGroupDefaults = UserDefaults(suiteName: appGroupId) else { return }
    let standardDefaults = UserDefaults.standard

    // Read from app group (where share extension writes)
    guard let appGroupData = appGroupDefaults.string(forKey: pendingSharesKey),
          !appGroupData.isEmpty else {
      return // Nothing to migrate
    }

    print("[AppDelegate] Found pending shares in app group, migrating to standard UserDefaults...")

    // Parse app group shares
    guard let appGroupJsonData = appGroupData.data(using: .utf8),
          let appGroupShares = try? JSONSerialization.jsonObject(with: appGroupJsonData) as? [[String: Any]] else {
      print("[AppDelegate] Failed to parse app group pending shares")
      return
    }

    // Read existing standard UserDefaults shares (in case there are already some)
    var mergedShares: [[String: Any]] = []
    if let existingData = standardDefaults.string(forKey: pendingSharesKey),
       let existingJsonData = existingData.data(using: .utf8),
       let existingShares = try? JSONSerialization.jsonObject(with: existingJsonData) as? [[String: Any]] {
      mergedShares = existingShares
    }

    // Merge app group shares into standard defaults
    mergedShares.append(contentsOf: appGroupShares)

    // Write merged result to standard UserDefaults
    if let mergedJsonData = try? JSONSerialization.data(withJSONObject: mergedShares),
       let mergedJsonString = String(data: mergedJsonData, encoding: .utf8) {
      standardDefaults.set(mergedJsonString, forKey: pendingSharesKey)
      standardDefaults.synchronize()
      print("[AppDelegate] ✓ Migrated \(appGroupShares.count) share(s) to standard UserDefaults (total: \(mergedShares.count))")
    }

    // Clear app group to prevent re-processing
    appGroupDefaults.removeObject(forKey: pendingSharesKey)
    appGroupDefaults.synchronize()
    print("[AppDelegate] ✓ Cleared app group pending shares")
  }

  /// Copy auth token + API base URL from standard UserDefaults to app group UserDefaults
  /// so the Share Extension can access them for background uploads.
  /// Belt-and-suspenders: also synced via MethodChannel from Dart on login.
  private func syncTokenToAppGroup() {
    guard let appGroupDefaults = UserDefaults(suiteName: appGroupId) else { return }
    let standardDefaults = UserDefaults.standard

    if let token = standardDefaults.string(forKey: authTokenKey), !token.isEmpty {
      appGroupDefaults.set(token, forKey: authTokenKey)
    }
    if let apiUrl = standardDefaults.string(forKey: apiBaseUrlKey), !apiUrl.isEmpty {
      appGroupDefaults.set(apiUrl, forKey: apiBaseUrlKey)
    }
    appGroupDefaults.synchronize()
  }

  private func persistSourceApp(bundleId: String) {
    let defaults = UserDefaults.standard
    defaults.set(bundleId, forKey: lastBundleKey)

    if let appName = resolveAppName(bundleId: bundleId) {
      defaults.set(appName, forKey: lastAppNameKey)
    }
    defaults.synchronize()
  }

  private func resolveAppName(bundleId: String) -> String? {
    guard let app = try? bundleId.asNSBundle() else { return nil }
    return app.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? app.object(forInfoDictionaryKey: "CFBundleName") as? String
  }
}

private extension String {
  func asNSBundle() throws -> Bundle {
    if let bundle = Bundle(identifier: self) {
      return bundle
    }
    throw NSError(domain: "BundleNotFound", code: 0)
  }
}
