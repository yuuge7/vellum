package com.vellum.ar_drawing

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    // All encoder access happens on this single worker thread.
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var encoder: TimelapseEncoder? = null

    // Image handed over by another app (Share / Open with), waiting for Dart to take it.
    private val reader = Executors.newSingleThreadExecutor()
    private var shareChannel: MethodChannel? = null
    private var pendingImage: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A restored activity, or one reopened from Recents, still carries its old intent;
        // only a fresh launch delivers an image.
        val replayed = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !replayed) pendingImage = imageUri(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = imageUri(intent) ?: return
        pendingImage = uri
        shareChannel?.invokeMethod("incoming", null)
    }

    private fun imageUri(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_SEND ->
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
        Intent.ACTION_VIEW -> intent.data
        else -> null
    }

    private fun readImage(uri: Uri): Map<String, Any?> {
        var name: String? = null
        runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) name = c.getString(0)
            }
        }
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: error("could not open the shared image")
        if (bytes.size > MAX_SHARED_BYTES) error("that image is too large")
        return mapOf("name" to (name ?: uri.lastPathSegment), "bytes" to bytes)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vellum/share").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Returns the waiting image as {name, bytes}, or null when there is none.
                    "take" -> {
                        val uri = pendingImage
                        pendingImage = null
                        if (uri == null) result.success(null) else background(result, reader, "share") { readImage(uri) }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vellum/timelapse").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> background(result) {
                    encoder?.let { it.release(); it.file.delete() }
                    val dir = File(cacheDir, "timelapse").apply { mkdirs() }
                    val file = File(dir, "vellum_${System.currentTimeMillis()}.mp4")
                    val e = TimelapseEncoder(
                        file,
                        call.argument<Int>("width") ?: 576,
                        call.argument<Int>("height") ?: 1024,
                        call.argument<Int>("fps") ?: 30,
                        call.argument<Int>("bitrate") ?: 3_000_000,
                    )
                    encoder = e
                    mapOf("path" to file.absolutePath, "width" to e.width, "height" to e.height)
                }
                "frame" -> background(result) {
                    val e = encoder ?: error("recorder not started")
                    val rgba = call.argument<ByteArray>("rgba") ?: error("missing frame")
                    e.addFrame(rgba, call.argument<Int>("repeat") ?: 1)
                    e.frameCount
                }
                "finish" -> background(result) {
                    val e = encoder ?: error("recorder not started")
                    encoder = null
                    e.finish(call.argument<Int>("holdFrames") ?: 0)
                    e.file.absolutePath
                }
                "cancel" -> background(result) {
                    encoder?.let { it.release(); it.file.delete() }
                    encoder = null
                    null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(
        result: MethodChannel.Result,
        executor: java.util.concurrent.ExecutorService = worker,
        code: String = "timelapse",
        block: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (t: Throwable) {
                main.post { result.error(code, t.message ?: t.toString(), null) }
            }
        }
    }

    override fun onDestroy() {
        worker.execute { encoder?.release(); encoder = null }
        worker.shutdown()
        reader.shutdown()
        shareChannel = null
        super.onDestroy()
    }

    private companion object {
        const val MAX_SHARED_BYTES = 64 * 1024 * 1024
    }
}
