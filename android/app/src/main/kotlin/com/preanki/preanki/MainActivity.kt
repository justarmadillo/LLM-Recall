package com.preanki.preanki

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

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
                val text = decodeText(stream.readBytes())
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

    private fun decodeText(bytes: ByteArray): String {
        if (bytes.isEmpty()) {
            return ""
        }
        if (bytes.startsWith(0xEF, 0xBB, 0xBF)) {
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        if (bytes.startsWith(0xFF, 0xFE)) {
            return String(bytes, 2, bytes.size - 2, Charset.forName("UTF-16LE"))
        }
        if (bytes.startsWith(0xFE, 0xFF)) {
            return String(bytes, 2, bytes.size - 2, Charset.forName("UTF-16BE"))
        }

        val sampleLength = minOf(bytes.size, 512)
        var evenNulls = 0
        var oddNulls = 0
        for (index in 0 until sampleLength) {
            if (bytes[index].toInt() != 0) {
                continue
            }
            if (index % 2 == 0) {
                evenNulls += 1
            } else {
                oddNulls += 1
            }
        }
        val threshold = sampleLength / 8
        if (sampleLength >= 8 && oddNulls > threshold && oddNulls > evenNulls * 3) {
            return String(bytes, Charset.forName("UTF-16LE"))
        }
        if (sampleLength >= 8 && evenNulls > threshold && evenNulls > oddNulls * 3) {
            return String(bytes, Charset.forName("UTF-16BE"))
        }
        return decodeUtf8OrWindows1252(bytes)
    }

    // Mirrors the Dart-side CsvTools.decodeBytes fallback: strict UTF-8 first,
    // then Windows-1252 when the bytes look like single-byte Western text.
    private fun decodeUtf8OrWindows1252(bytes: ByteArray): String {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            decoder.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            if (looksLikeSingleByteText(bytes)) {
                String(bytes, Charset.forName("windows-1252"))
            } else {
                String(bytes, Charsets.UTF_8)
            }
        }
    }

    private fun looksLikeSingleByteText(bytes: ByteArray): Boolean {
        var highBytes = 0
        for (byte in bytes) {
            val value = byte.toInt() and 0xFF
            if (value == 0) {
                return false
            }
            if (value >= 0x80) {
                highBytes += 1
            }
        }
        return highBytes > 0 && highBytes <= bytes.size * 0.35
    }

    private fun ByteArray.startsWith(vararg prefix: Int): Boolean {
        if (size < prefix.size) {
            return false
        }
        for (index in prefix.indices) {
            if ((this[index].toInt() and 0xFF) != prefix[index]) {
                return false
            }
        }
        return true
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
