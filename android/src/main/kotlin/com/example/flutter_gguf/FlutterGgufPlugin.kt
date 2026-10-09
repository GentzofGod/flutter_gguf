package com.example.flutter_gguf

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import kotlin.concurrent.thread

/** FlutterGgufPlugin providing robust GGUF model loading and file picking */
class FlutterGgufPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var pendingResult: Result? = null

    private val requestCodePickModel = 7431

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_gguf")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "pickGgufFile" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Activity is not available", null)
                    return
                }
                if (pendingResult != null) {
                    result.error("ALREADY_PICKING", "A file picker operation is already in progress", null)
                    return
                }
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "*/*"))
                }
                act.startActivityForResult(intent, requestCodePickModel)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == requestCodePickModel) {
            val res = pendingResult ?: return false
            pendingResult = null

            if (resultCode != Activity.RESULT_OK || data == null || data.data == null) {
                res.success(null)
                return true
            }

            val uri = data.data!!
            try {
                val takeFlags: Int = Intent.FLAG_GRANT_READ_URI_PERMISSION
                context?.contentResolver?.takePersistableUriPermission(uri, takeFlags)
            } catch (_: Exception) {}

            thread {
                val resolvedPath = resolvePath(uri)
                activity?.runOnUiThread {
                    res.success(resolvedPath)
                }
            }
            return true
        }
        return false
    }

    private fun resolvePath(uri: Uri): String {
        val ctx = context ?: return uri.path ?: uri.toString()

        // 1. Try resolving primary external storage direct path
        try {
            if (DocumentsContract.isDocumentUri(ctx, uri)) {
                val docId = DocumentsContract.getDocumentId(uri)
                if (uri.authority == "com.android.externalstorage.documents") {
                    val split = docId.split(":")
                    val type = split[0]
                    if ("primary".equals(type, ignoreCase = true) && split.size > 1) {
                        val path = "${Environment.getExternalStorageDirectory()}/${split[1]}"
                        val file = File(path)
                        if (file.exists() && file.canRead()) {
                            return file.absolutePath
                        }
                    }
                } else if (docId.startsWith("raw:")) {
                    val rawPath = docId.substring(4)
                    val file = File(rawPath)
                    if (file.exists() && file.canRead()) {
                        return file.absolutePath
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. Query file name and check common storage directories
        var displayName: String? = null
        try {
            ctx.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (cursor.moveToFirst() && nameIndex >= 0) {
                    displayName = cursor.getString(nameIndex)
                }
            }
        } catch (_: Exception) {}

        if (displayName != null) {
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val downloadFile = File(downloadDir, displayName!!)
            if (downloadFile.exists() && downloadFile.canRead()) {
                return downloadFile.absolutePath
            }

            val storageDir = Environment.getExternalStorageDirectory()
            val storageFile = File(storageDir, displayName!!)
            if (storageFile.exists() && storageFile.canRead()) {
                return storageFile.absolutePath
            }
        }

        // 3. Fallback: Copy via streaming chunk buffer to app's model cache directory
        // This avoids OutOfMemoryError and provides a clean, permanent file path for native llama.cpp
        try {
            val fileName = displayName ?: "model_${System.currentTimeMillis()}.gguf"
            val modelsDir = File(ctx.filesDir, "models")
            if (!modelsDir.exists()) {
                modelsDir.mkdirs()
            }
            val targetFile = File(modelsDir, fileName)

            // If file already cached and same size, reuse
            var uriSize: Long = -1
            try {
                ctx.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (cursor.moveToFirst() && sizeIndex >= 0) {
                        uriSize = cursor.getLong(sizeIndex)
                    }
                }
            } catch (_: Exception) {}

            if (targetFile.exists() && uriSize > 0 && targetFile.length() == uriSize) {
                return targetFile.absolutePath
            }

            ctx.contentResolver.openInputStream(uri)?.use { inputStream: InputStream ->
                FileOutputStream(targetFile).use { outputStream: FileOutputStream ->
                    val buffer = ByteArray(1024 * 1024) // 1MB chunk buffer
                    var bytesRead: Int
                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                    }
                    outputStream.flush()
                }
            }

            if (targetFile.exists() && targetFile.canRead()) {
                return targetFile.absolutePath
            }
        } catch (_: Exception) {}

        return uri.path ?: uri.toString()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }
}
