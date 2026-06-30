package com.dgvault.dgvault

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dgvault/open_file"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                // The intent that launched us — a VIEW intent carries the .kdbx.
                result.success(readFile(intent))
            } else {
                result.notImplemented()
            }
        }
    }

    // Warm start: app already running, user opens another .kdbx (singleTop).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = readFile(intent) ?: return
        channel?.invokeMethod("openFile", payload)
    }

    private fun readFile(intent: Intent?): Map<String, Any>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri: Uri = intent.data ?: return null
        return try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: return null
            mapOf("name" to displayName(uri), "bytes" to bytes)
        } catch (e: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
            )?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) return c.getString(idx)
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "vault.kdbx"
    }
}
