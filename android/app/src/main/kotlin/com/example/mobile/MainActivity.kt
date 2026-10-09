package com.example.mobile

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "mcs.media_store"
        const val APP_DIR = "Mother Care"
        const val PERMISSION_REQUEST_CODE = 4412
    }

    private var pendingSave: Triple<File, String, String>? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveMedia" -> {
                        val path = call.argument<String>("path")
                        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                        val fileName = call.argument<String>("fileName")
                        if (path == null || fileName == null || !File(path).exists()) {
                            result.error("bad_args", "Missing or unreadable source file", null)
                            return@setMethodCallHandler
                        }
                        requestSave(File(path), mime, sanitizeFileName(fileName), result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sanitizeFileName(name: String): String =
        name.replace('/', '_').replace('\\', '_').ifBlank { "file" }

    /// Starts a save. Android 6–9 needs WRITE_EXTERNAL_STORAGE; request it on
    /// first use and replay the save from onRequestPermissionsResult.
    /// (Below 23 permissions are granted at install time; 10+ needs none.)
    private fun requestSave(file: File, mime: String, fileName: String, result: MethodChannel.Result) {
        val needsPermission = Build.VERSION.SDK_INT in 23..28 &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            if (pendingResult != null) {
                result.error("busy", "Another save is in progress", null)
                return
            }
            pendingSave = Triple(file, mime, fileName)
            pendingResult = result
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSION_REQUEST_CODE)
            return
        }
        saveOnBackgroundThread(file, mime, fileName, result)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingResult
        val save = pendingSave
        pendingResult = null
        pendingSave = null
        if (result == null || save == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            saveOnBackgroundThread(save.first, save.second, save.third, result)
        } else {
            result.error("permission_denied", "Storage permission is required to save files", null)
        }
    }

    private fun saveOnBackgroundThread(file: File, mime: String, fileName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val destination = saveMedia(file, mime, fileName)
                runOnUiThread { result.success(destination) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("save_failed", e.message ?: "Could not save file", null)
                }
            }
        }.start()
    }

    private fun saveMedia(file: File, mime: String, fileName: String): String {
        val isImage = mime.startsWith("image/")
        val isVideo = mime.startsWith("video/")

        return if (Build.VERSION.SDK_INT >= 29) {
            saveViaMediaStore(file, mime, fileName, isImage, isVideo)
        } else {
            saveViaPublicDir(file, mime, fileName, isImage, isVideo)
        }
    }

    /// Android 10+ (Q): MediaStore insert — no storage permission needed for
    /// files the app itself creates. IS_PENDING keeps the entry hidden from
    /// other apps until the bytes are fully written, then it is published
    /// (without the publish step some OEM galleries never pick it up).
    private fun saveViaMediaStore(
        file: File,
        mime: String,
        fileName: String,
        isImage: Boolean,
        isVideo: Boolean,
    ): String {
        val collection = when {
            isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            isVideo -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (isImage || isVideo) {
                val dir = if (isImage) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_MOVIES
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$dir/$APP_DIR")
            }
            if (Build.VERSION.SDK_INT >= 29) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val resolver = contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IOException("MediaStore insert failed for $fileName")
        try {
            resolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("Could not open MediaStore stream for $fileName")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        if (Build.VERSION.SDK_INT >= 29) {
            val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, published, null, null)
        }
        return uri.toString()
    }

    /// Pre-Q: copy into the shared public directory and broadcast a media
    /// scan so the gallery indexes it (the scan broadcast is what makes the
    /// file appear in the gallery on Android 9 and below).
    private fun saveViaPublicDir(
        file: File,
        mime: String,
        fileName: String,
        isImage: Boolean,
        isVideo: Boolean,
    ): String {
        val baseDir = when {
            isImage -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            isVideo -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            else -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        }
        val targetDir = File(baseDir, APP_DIR).apply { mkdirs() }
        val dest = uniqueFile(targetDir, fileName)
        file.copyTo(dest, overwrite = true)
        MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf(mime), null)
        return dest.absolutePath
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        val candidate = File(dir, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var i = 1
        while (true) {
            val next = File(dir, "$stem ($i)$ext")
            if (!next.exists()) return next
            i++
        }
    }
}
