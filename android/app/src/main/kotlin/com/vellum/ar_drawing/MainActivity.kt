package com.vellum.ar_drawing

import android.os.Handler
import android.os.Looper
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (t: Throwable) {
                main.post { result.error("timelapse", t.message ?: t.toString(), null) }
            }
        }
    }

    override fun onDestroy() {
        worker.execute { encoder?.release(); encoder = null }
        worker.shutdown()
        super.onDestroy()
    }
}
