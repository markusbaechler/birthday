package ch.markusbaechler.geburtstage

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridge for greetings with pictures:
 * - receives text or an image shared from other apps (e.g. ChatGPT),
 * - sends image and text to WhatsApp, straight into the person's chat,
 * - hands text to another app (e.g. the image prompt to ChatGPT).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "geburtstage/share")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialShare" -> {
                    result.success(pending)
                    pending = null
                }
                "sendWhatsApp" -> result.success(
                    sendWhatsApp(call.argument("phone"), call.argument("text"), call.argument("path"))
                )
                "share" -> result.success(share(call.argument("text"), call.argument("path")))
                "sendTextToApp" -> result.success(
                    sendTextToApp(call.argument<String>("package")!!, call.argument("text"))
                )
                "batteryUnrestricted" -> {
                    val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryUnrestricted" -> result.success(openFirst(
                    Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")),
                    Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"))
                ))
                "openAppSettings" -> result.success(openFirst(
                    Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"))
                ))
                else -> result.notImplemented()
            }
        }
        channel = ch
        pending = readShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = readShare(intent) ?: return
        val ch = channel
        if (ch == null) pending = data else ch.invokeMethod("share", data)
    }

    private fun openFirst(vararg intents: Intent): Boolean {
        for (i in intents) {
            try {
                startActivity(i)
                return true
            } catch (e: Exception) {
                // next
            }
        }
        return false
    }

    /** Copies a shared image into the cache so Flutter can read it. */
    private fun readShare(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        var path: String? = null
        if (uri != null) {
            try {
                val mime = contentResolver.getType(uri) ?: intent.type ?: "image/jpeg"
                val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime) ?: "jpg"
                val dir = File(cacheDir, "shared_in").apply { mkdirs() }
                val file = File(dir, "in_${System.currentTimeMillis()}.$ext")
                contentResolver.openInputStream(uri)?.use { input ->
                    file.outputStream().use { input.copyTo(it) }
                }
                if (file.length() > 0) path = file.absolutePath
            } catch (e: Exception) {
                path = null
            }
        }
        // Handled once, also after a rotation.
        intent.action = Intent.ACTION_MAIN
        if (text.isNullOrBlank() && path == null) return null
        return mapOf("text" to text, "path" to path)
    }

    private fun uriFor(path: String): Uri =
        FileProvider.getUriForFile(this, "$packageName.greetings", File(path))

    private fun mimeOf(path: String): String {
        val ext = path.substringAfterLast('.', "jpg").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "image/jpeg"
    }

    /**
     * Opens the WhatsApp chat of [phone] (E.164) with image and text.
     * The «jid» extra is not an official interface; if it fails, the
     * Android share sheet opens instead.
     */
    private fun sendWhatsApp(phone: String?, text: String?, path: String?): Boolean {
        val file = path?.let { File(it) }?.takeIf { it.exists() }
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            val i = Intent(Intent.ACTION_SEND).apply {
                setPackage(pkg)
                if (file != null) {
                    type = mimeOf(file.path)
                    putExtra(Intent.EXTRA_STREAM, uriFor(file.path))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                } else {
                    type = "text/plain"
                }
                putExtra(Intent.EXTRA_TEXT, text ?: "")
                if (!phone.isNullOrBlank()) {
                    putExtra("jid", phone.trimStart('+') + "@s.whatsapp.net")
                }
            }
            try {
                startActivity(i)
                return true
            } catch (e: ActivityNotFoundException) {
                // try the next one
            } catch (e: Exception) {
                break
            }
        }
        return share(text, path)
    }

    private fun share(text: String?, path: String?): Boolean {
        val file = path?.let { File(it) }?.takeIf { it.exists() }
        val i = Intent(Intent.ACTION_SEND).apply {
            if (file != null) {
                type = mimeOf(file.path)
                putExtra(Intent.EXTRA_STREAM, uriFor(file.path))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } else {
                type = "text/plain"
            }
            if (!text.isNullOrEmpty()) putExtra(Intent.EXTRA_TEXT, text)
        }
        return try {
            startActivity(Intent.createChooser(i, null))
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun sendTextToApp(pkg: String, text: String?): Boolean {
        val i = Intent(Intent.ACTION_SEND).apply {
            setPackage(pkg)
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text ?: "")
        }
        return try {
            startActivity(i)
            true
        } catch (e: Exception) {
            false
        }
    }
}
