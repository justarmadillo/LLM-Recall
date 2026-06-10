package com.preanki.preanki

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val importChannelName = "llm_recall/imports"
    private var importChannel: MethodChannel? = null
    private var pendingImport: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingImport = readImportFromIntent(intent)
        importChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            importChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consumeInitialImport") {
                    result.success(pendingImport)
                    pendingImport = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = readImportFromIntent(intent)
        if (payload != null) {
            val channel = importChannel
            if (channel != null) {
                channel.invokeMethod("incomingCsv", payload)
            } else {
                pendingImport = payload
            }
        }
    }

    private fun readImportFromIntent(intent: Intent?): Map<String, String>? {
        if (intent == null) {
            return null
        }
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { readUriPayload(it) }
            Intent.ACTION_SEND -> readSharedPayload(intent)
            else -> null
        }
    }

    private fun readSharedPayload(intent: Intent): Map<String, String>? {
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (!sharedText.isNullOrBlank()) {
            return mapOf(
                "text" to sharedText,
                "sourceName" to "Shared text"
            )
        }

        val streamUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
        return streamUri?.let { readUriPayload(it) }
    }

    private fun readUriPayload(uri: Uri): Map<String, String>? {
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val text = stream.bufferedReader(Charsets.UTF_8).readText()
                if (text.isBlank()) {
                    null
                } else {
                    mapOf(
                        "text" to text,
                        "sourceName" to displayName(uri)
                    )
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) {
                        return name
                    }
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "Imported CSV"
    }
}
