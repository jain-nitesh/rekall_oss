import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

private let kAppGroupIdKey = "AppGroupId"

/// Silent share extension that matches Android's ShareActivity behavior:
/// - No visible UI (transparent)
/// - Saves shared content to flutter.pending_shares in same JSON format as Android
/// - Dismisses immediately without opening ReCall app
@objc(ShareViewController)
class ShareViewController: UIViewController {

    private var appGroupId = ""
    private var hasCompleted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        loadIds()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        print("[ShareExtension] Share extension appeared")

        // Safety timeout - always dismiss after 5 seconds (increased for media copy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            print("[ShareExtension] Safety timeout - forcing dismiss")
            self?.completeExtension()
        }

        // Process shared content
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments, !attachments.isEmpty else {
            print("[ShareExtension] No items to process")
            completeExtension()
            return
        }

        let urlTypeId = kUTTypeURL as String
        let textTypeId = kUTTypePlainText as String
        let imageTypeId = kUTTypeImage as String
        let movieTypeId = kUTTypeMovie as String
        let totalAttachments = attachments.count
        var processedCount = 0
        // Each item: (type, content) where type is "url"/"text"/"image"/"video"
        var sharedItems: [(type: String, content: String)] = []

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(urlTypeId) {
                attachment.loadItem(forTypeIdentifier: urlTypeId, options: nil) { [weak self] data, error in
                    guard let self = self else { return }
                    if let url = data as? URL {
                        print("[ShareExtension] Received URL: \(url.absoluteString)")
                        sharedItems.append((type: "url", content: url.absoluteString))
                    }
                    processedCount += 1
                    if processedCount >= totalAttachments {
                        self.saveAndDismiss(items: sharedItems)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(imageTypeId) {
                attachment.loadItem(forTypeIdentifier: imageTypeId, options: nil) { [weak self] data, error in
                    guard let self = self else { return }
                    if let savedPath = self.saveMediaAttachment(data: data, type: "image") {
                        print("[ShareExtension] Saved image to app group: \(savedPath)")
                        sharedItems.append((type: "image", content: savedPath))
                    } else {
                        print("[ShareExtension] Failed to save image attachment")
                    }
                    processedCount += 1
                    if processedCount >= totalAttachments {
                        self.saveAndDismiss(items: sharedItems)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(movieTypeId) {
                attachment.loadItem(forTypeIdentifier: movieTypeId, options: nil) { [weak self] data, error in
                    guard let self = self else { return }
                    if let savedPath = self.saveMediaAttachment(data: data, type: "video") {
                        print("[ShareExtension] Saved video to app group: \(savedPath)")
                        sharedItems.append((type: "video", content: savedPath))
                    } else {
                        print("[ShareExtension] Failed to save video attachment")
                    }
                    processedCount += 1
                    if processedCount >= totalAttachments {
                        self.saveAndDismiss(items: sharedItems)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(textTypeId) {
                attachment.loadItem(forTypeIdentifier: textTypeId, options: nil) { [weak self] data, error in
                    guard let self = self else { return }
                    if let text = data as? String {
                        print("[ShareExtension] Received text: \(text)")
                        sharedItems.append((type: "text", content: text))
                    }
                    processedCount += 1
                    if processedCount >= totalAttachments {
                        self.saveAndDismiss(items: sharedItems)
                    }
                }
            } else {
                processedCount += 1
                if processedCount >= totalAttachments {
                    saveAndDismiss(items: sharedItems)
                }
            }
        }
    }

    // MARK: - Media file helpers

    /// Copy a media attachment (image or video) to the App Group shared container.
    /// Returns the saved file path, or nil on failure.
    private func saveMediaAttachment(data: NSSecureCoding?, type: String) -> String? {
        guard let containerUrl = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) else {
            print("[ShareExtension] Could not get app group container URL")
            return nil
        }

        let ext = type == "video" ? "mp4" : "jpg"
        let filename = "shared_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        let destUrl = containerUrl.appendingPathComponent(filename)

        // Case 1: data is a file URL (most common from Photos/Files)
        if let fileUrl = data as? URL {
            do {
                if FileManager.default.fileExists(atPath: destUrl.path) {
                    try FileManager.default.removeItem(at: destUrl)
                }
                try FileManager.default.copyItem(at: fileUrl, to: destUrl)
                return destUrl.path
            } catch {
                print("[ShareExtension] Failed to copy file: \(error)")
                return nil
            }
        }

        // Case 2: data is a UIImage
        if let image = data as? UIImage,
           let jpegData = image.jpegData(compressionQuality: 0.85) {
            do {
                try jpegData.write(to: destUrl)
                return destUrl.path
            } catch {
                print("[ShareExtension] Failed to write UIImage as JPEG: \(error)")
                return nil
            }
        }

        // Case 3: data is raw Data
        if let rawData = data as? Data {
            do {
                try rawData.write(to: destUrl)
                return destUrl.path
            } catch {
                print("[ShareExtension] Failed to write raw data: \(error)")
                return nil
            }
        }

        print("[ShareExtension] Unrecognised data type: \(Swift.type(of: data))")
        return nil
    }

    // MARK: - Private

    private func loadIds() {
        let extensionBundleId = Bundle.main.bundleIdentifier!
        let lastDot = extensionBundleId.lastIndex(of: ".")!
        let hostAppBundleIdentifier = String(extensionBundleId[..<lastDot])

        let customGroupId = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = customGroupId ?? "group.\(hostAppBundleIdentifier)"
        print("[ShareExtension] App group: \(appGroupId)")
    }

    /// Save shared content silently without opening the host app
    /// Matches Android's ShareActivity: save to flutter.pending_shares + dismiss
    /// Also fires a background upload (fire-and-forget) for URL/text content
    private func saveAndDismiss(items: [(type: String, content: String)]) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ShareExtension] Failed to access shared UserDefaults")
            completeExtension()
            return
        }

        // 1. Save in flutter.pending_shares format (same as Android)
        //    PendingSharesService picks it up on app resume
        for item in items {
            savePendingShare(type: item.type, content: item.content, userDefaults: userDefaults)
        }

        userDefaults.synchronize()

        // 2. Fire background upload for URL/text only (media is handled on app open)
        let urlContents = items
            .filter { $0.type == "url" || $0.type == "text" }
            .map { $0.content }
        if !urlContents.isEmpty {
            fireUpload(contents: urlContents, userDefaults: userDefaults)
        }

        // 3. Show brief toast then dismiss immediately
        showToastAndDismiss()
    }

    /// Save to flutter.pending_shares — same JSON format as Android's ShareActivity.
    /// Adds a "type" field for media items so Flutter can route them to uploadMedia().
    private func savePendingShare(type: String, content: String, userDefaults: UserDefaults) {
        print("[ShareExtension] ═══════════════════════════════════════════════════")
        print("[ShareExtension] SAVING SHARED CONTENT TO SHAREDPREFERENCES (type=\(type))")

        // Get existing shares (same key as Android: flutter.pending_shares)
        var sharesArray: [[String: Any]] = []
        if let existingData = userDefaults.string(forKey: "flutter.pending_shares"),
           let data = existingData.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            sharesArray = json
            print("[ShareExtension] Existing shares: \(sharesArray.count) item(s)")
        }

        // Create new share object
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        var shareObject: [String: Any] = [
            "timestamp": timestamp,
            "content": content
        ]
        // Include type for media so Flutter knows to call uploadMedia() instead of ingestContent()
        if type == "image" || type == "video" {
            shareObject["type"] = type
        }

        sharesArray.append(shareObject)

        // Save back as JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: sharesArray),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: "flutter.pending_shares")
            print("[ShareExtension] ✓ Saved \(sharesArray.count) share(s) to flutter.pending_shares")
            let preview = content.count > 100 ? String(content.prefix(100)) + "..." : content
            print("[ShareExtension]   Content: \(preview)")
        } else {
            print("[ShareExtension] ✗ Failed to serialize shares to JSON")
        }

        print("[ShareExtension] ═══════════════════════════════════════════════════")
    }

    /// Show a brief toast notification then dismiss (like Android's Toast)
    private func showToastAndDismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Create toast label
            let toast = UILabel()
            toast.text = "  \u{2713} Saved to ReKall!  "
            toast.textColor = .white
            toast.font = .systemFont(ofSize: 15, weight: .medium)
            toast.backgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.95)
            toast.textAlignment = .center
            toast.layer.cornerRadius = 22
            toast.clipsToBounds = true
            toast.sizeToFit()

            // Size and position at bottom center
            let padding: CGFloat = 24
            let width = toast.frame.width + padding * 2
            let height: CGFloat = 44
            toast.frame = CGRect(
                x: (self.view.bounds.width - width) / 2,
                y: self.view.bounds.height - height - 80,
                width: width,
                height: height
            )
            toast.alpha = 0

            self.view.addSubview(toast)

            // Animate in, hold briefly, then dismiss extension
            UIView.animate(withDuration: 0.2, animations: {
                toast.alpha = 1
            }) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.completeExtension()
                }
            }
        }
    }

    // MARK: - Background Upload (fire-and-forget)

    /// Fire upload requests for shared content to the backend.
    /// Non-blocking: fires URLSession data tasks and returns immediately.
    /// On success, removes the item from pending_shares so the app-open path doesn't re-upload.
    /// If token is missing or upload fails, content stays in pending_shares for app-open fallback.
    private func fireUpload(contents: [String], userDefaults: UserDefaults) {
        // Read auth token from app group (synced by main app via MethodChannel / applicationDidBecomeActive)
        guard let token = userDefaults.string(forKey: "flutter.auth_token"),
              !token.isEmpty else {
            print("[ShareExtension] No auth token in app group - skipping background upload")
            return
        }

        let apiBaseUrl = userDefaults.string(forKey: "flutter.api_base_url") ?? "https://YOUR_BACKEND_DOMAIN"

        for content in contents {
            guard let url = extractUrl(from: content) else {
                print("[ShareExtension] No URL found in content, skipping upload")
                continue
            }
            uploadContent(apiBaseUrl: apiBaseUrl, token: token, url: url, sharedText: content, appGroupId: appGroupId)
        }
    }

    /// Fire a single POST to /content/ingest.
    /// On success, removes the content from pending_shares to prevent duplicate upload on app open.
    /// On failure, leaves it in pending_shares for the app-open fallback.
    private func uploadContent(apiBaseUrl: String, token: String, url: String, sharedText: String, appGroupId: String) {
        let endpoint = "\(apiBaseUrl)/content/ingest"
        guard let requestUrl = URL(string: endpoint) else {
            print("[ShareExtension] Invalid endpoint URL: \(endpoint)")
            return
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "url": url,
            "shared_text": sharedText
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // iOS gives the extension a few seconds of grace after completeRequest().
        // On success: remove from pending_shares so app-open doesn't re-upload.
        // On failure: leave in pending_shares for app-open fallback.
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[ShareExtension] Upload error for \(url): \(error.localizedDescription)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else { return }
            print("[ShareExtension] Upload response: HTTP \(httpResponse.statusCode) for \(url)")

            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                // Success — remove this content from pending_shares to prevent duplicate
                Self.removeFromPendingShares(content: sharedText, appGroupId: appGroupId)
            }
        }.resume()

        print("[ShareExtension] Fired upload for: \(url)")
    }

    /// Remove a successfully uploaded item from flutter.pending_shares in app group UserDefaults.
    /// Called from the upload completion handler to prevent the app-open path from re-uploading.
    private static func removeFromPendingShares(content: String, appGroupId: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else { return }

        guard let existingData = userDefaults.string(forKey: "flutter.pending_shares"),
              let data = existingData.data(using: .utf8),
              let sharesArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }

        // Filter out the item that matches this content
        let filtered = sharesArray.filter { share in
            guard let shareContent = share["content"] as? String else { return true }
            return shareContent != content
        }

        if filtered.isEmpty {
            userDefaults.removeObject(forKey: "flutter.pending_shares")
        } else if let jsonData = try? JSONSerialization.data(withJSONObject: filtered),
                  let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults.set(jsonString, forKey: "flutter.pending_shares")
        }
        userDefaults.synchronize()
        print("[ShareExtension] ✓ Removed uploaded content from pending_shares (\(filtered.count) remaining)")
    }

    /// Extract the first HTTP(S) URL from a string (matching Android's ContentSyncWorker.extractUrl)
    private func extractUrl(from content: String) -> String? {
        let pattern = "https?://[^\\s]+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range, in: content) else {
            return nil
        }
        return String(content[range])
    }

    private func completeExtension() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            self.hasCompleted = true
            print("[ShareExtension] ✓ Completing extension request")
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
