import Flutter
import UIKit

/// `mcs.media_store` platform channel (iOS side).
///
///  * `image/*` → Photos library (requires NSPhotoLibraryAddUsageDescription)
///  * `video/*` → Photos library
///  * anything else → copied into the app's Documents directory, which is
///    browsable from the system Files app.
class MediaStorePlugin: NSObject, FlutterPlugin {

    private var pendingResult: FlutterResult?
    private var pendingPath: String?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "mcs.media_store",
            binaryMessenger: registrar.messenger()
        )
        let instance = MediaStorePlugin()
        registrar.addMethodCallHandler(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "saveMedia" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let fileName = args["fileName"] as? String,
            let mimeType = args["mimeType"] as? String
        else {
            result(FlutterError(code: "bad_args", message: "Missing save arguments", details: nil))
            return
        }
        let source = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "bad_args", message: "Source file not found", details: nil))
            return
        }
        let safeName = fileName.replacingOccurrences(of: "/", with: "_")

        if mimeType.hasPrefix("image/"), let data = try? Data(contentsOf: source), let image = UIImage(data: data) {
            pendingResult = result
            pendingPath = path
            UIImageWriteToSavedPhotosAlbum(
                image,
                self,
                #selector(image(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        } else if mimeType.hasPrefix("video/") {
            pendingResult = result
            pendingPath = path
            UISaveVideoAtPathToSavedPhotosAlbum(
                path,
                self,
                #selector(video(_:didFinishSavingWithError:contextInfo:)),
                nil
            )
        } else {
            do {
                let dest = try uniqueDestination(named: safeName)
                try FileManager.default.copyItem(at: source, to: dest)
                result(dest.path)
            } catch {
                result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
            }
        }
    }

    @objc private func image(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        finish(error: error)
    }

    @objc private func video(
        _ videoPath: String,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeRawPointer
    ) {
        finish(error: error)
    }

    private func finish(error: Error?) {
        let result = pendingResult
        let path = pendingPath
        pendingResult = nil
        pendingPath = nil
        if let error = error {
            result?(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
            return
        }
        // Photos save is async on a copy; the source temp file can be removed
        // by Dart after this success. Return the original path as the marker.
        result?(path ?? "photos://saved")
    }

    private func uniqueDestination(named fileName: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mother Care", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        var candidate = docs.appendingPathComponent(fileName)
        let dot = (fileName as NSString).pathExtension
        let stem = dot.isEmpty ? fileName : (fileName as NSString).deletingPathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = docs.appendingPathComponent(dot.isEmpty ? "\(stem) (\(i))" : "\(stem) (\(i)).\(dot)")
            i += 1
        }
        return candidate
    }
}
