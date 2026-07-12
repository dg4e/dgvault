package com.dgvault.dgvault

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dgvault/open_file"
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE keeps the vault out of the recents-screen thumbnail and
        // blocks screenshots / screen recording of the app window.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    // Storage Access Framework: open/create a document with persistable
    // read/write so edits save back to the original file (no local copy).
    private val docsChannelName = "dgvault/documents"
    private var pendingResult: MethodChannel.Result? = null
    private val rcOpen = 4011
    private val rcCreate = 4012

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, docsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickOpen" -> {
                        if (pendingResult != null) { result.error("busy", "picker in progress", null) }
                        else { pendingResult = result; launchOpen() }
                    }
                    "pickCreate" -> {
                        if (pendingResult != null) { result.error("busy", "picker in progress", null) }
                        else { pendingResult = result; launchCreate(call.argument<String>("name") ?: "vault.kdbx") }
                    }
                    "read" -> result.success(readUri(Uri.parse(call.argument<String>("uri"))))
                    "write" -> {
                        try {
                            writeUri(Uri.parse(call.argument<String>("uri")), call.argument<ByteArray>("bytes")!!)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("write_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchOpen() {
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        startActivityForResult(i, rcOpen)
    }

    private fun launchCreate(name: String) {
        val i = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        startActivityForResult(i, rcCreate)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val res = pendingResult ?: return
        if (requestCode != rcOpen && requestCode != rcCreate) return
        pendingResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) { res.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: Exception) { /* best effort */ }
        try {
            if (requestCode == rcOpen) {
                res.success(mapOf(
                    "uri" to uri.toString(),
                    "name" to displayName(uri),
                    "bytes" to readUri(uri),
                ))
            } else {
                res.success(mapOf("uri" to uri.toString(), "name" to displayName(uri)))
            }
        } catch (e: Exception) {
            res.error("open_failed", e.message, null)
        }
    }

    private fun readUri(uri: Uri): ByteArray? =
        contentResolver.openInputStream(uri)?.use { it.readBytes() }

    private fun writeUri(uri: Uri, bytes: ByteArray) {
        // "wt" = write + truncate, so the file is fully replaced (not appended).
        contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
            ?: throw IllegalStateException("could not open output stream")
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
