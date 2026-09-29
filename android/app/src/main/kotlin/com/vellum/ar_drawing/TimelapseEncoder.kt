package com.vellum.ar_drawing

import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

/**
 * Encodes RGBA frames into an H.264 MP4 at a fixed frame rate. Each frame gets
 * a synthetic timestamp (index / fps), so snapshots taken seconds apart play
 * back as a sped-up time-lapse.
 */
class TimelapseEncoder(
    val file: File,
    requestedWidth: Int,
    requestedHeight: Int,
    private val fps: Int,
    bitrate: Int,
) {
    val width: Int
    val height: Int
    var frameCount = 0
        private set

    private val codec: MediaCodec
    private val muxer: MediaMuxer
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxerStarted = false
    private var released = false
    private var lastFrame: ByteArray? = null
    private val yRow: ByteArray

    init {
        val (w, h) = chooseSize(requestedWidth, requestedHeight)
        width = w
        height = h
        yRow = ByteArray(w)
        val format = MediaFormat.createVideoFormat(MIME, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec = MediaCodec.createEncoderByType(MIME)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }

    fun addFrame(rgba: ByteArray, repeat: Int = 1) {
        require(rgba.size == width * height * 4) {
            "frame is ${rgba.size} bytes, expected ${width * height * 4} (${width}x$height RGBA)"
        }
        for (i in 0 until maxOf(1, repeat)) queue(rgba)
        lastFrame = rgba
    }

    /** Holds the final frame for [holdFrames] frames, then closes the file. */
    fun finish(holdFrames: Int) {
        lastFrame?.let { frame -> for (i in 0 until holdFrames) queue(frame) }
        val index = dequeueInput()
        codec.queueInputBuffer(index, 0, 0, pts(frameCount), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(true)
        release()
    }

    fun release() {
        if (released) return
        released = true
        try { codec.stop() } catch (_: Throwable) {}
        codec.release()
        try { if (muxerStarted) muxer.stop() } catch (_: Throwable) {}
        muxer.release()
    }

    private fun pts(frame: Int): Long = frame * 1_000_000L / fps

    private fun dequeueInput(): Int {
        while (true) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index >= 0) return index
            drain(false)
        }
    }

    private fun queue(rgba: ByteArray) {
        val index = dequeueInput()
        val image = codec.getInputImage(index) ?: error("encoder has no input image")
        fill(image, rgba)
        codec.queueInputBuffer(index, 0, width * height * 3 / 2, pts(frameCount), 0)
        frameCount++
        drain(false)
    }

    private fun drain(endOfStream: Boolean) {
        var idleSpins = 0
        while (true) {
            val out = codec.dequeueOutputBuffer(info, if (endOfStream) 10_000 else 0)
            when {
                out == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++idleSpins > 300) return
                }
                out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }
                out >= 0 -> {
                    val buf = codec.getOutputBuffer(out)
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (buf != null && info.size > 0 && muxerStarted) {
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buf, info)
                    }
                    codec.releaseOutputBuffer(out, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /** BT.601 limited-range RGBA -> YUV 4:2:0 into whatever layout the codec exposes. */
    private fun fill(image: Image, rgba: ByteArray) {
        val planes = image.planes
        val yPlane = planes[0]
        val yBuf = yPlane.buffer
        val yRs = yPlane.rowStride
        val yPs = yPlane.pixelStride
        for (y in 0 until height) {
            var p = y * width * 4
            if (yPs == 1) {
                for (x in 0 until width) {
                    val r = rgba[p].toInt() and 0xFF
                    val g = rgba[p + 1].toInt() and 0xFF
                    val b = rgba[p + 2].toInt() and 0xFF
                    yRow[x] = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte()
                    p += 4
                }
                yBuf.position(y * yRs)
                yBuf.put(yRow, 0, width)
            } else {
                for (x in 0 until width) {
                    val r = rgba[p].toInt() and 0xFF
                    val g = rgba[p + 1].toInt() and 0xFF
                    val b = rgba[p + 2].toInt() and 0xFF
                    yBuf.put(y * yRs + x * yPs, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                    p += 4
                }
            }
        }
        val uPlane = planes[1]
        val vPlane = planes[2]
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val uRs = uPlane.rowStride
        val vRs = vPlane.rowStride
        val uPs = uPlane.pixelStride
        val vPs = vPlane.pixelStride
        val cw = width / 2
        val ch = height / 2
        for (cy in 0 until ch) {
            for (cx in 0 until cw) {
                var r = 0
                var g = 0
                var b = 0
                for (dy in 0..1) {
                    val row = (cy * 2 + dy) * width
                    for (dx in 0..1) {
                        val p = (row + cx * 2 + dx) * 4
                        r += rgba[p].toInt() and 0xFF
                        g += rgba[p + 1].toInt() and 0xFF
                        b += rgba[p + 2].toInt() and 0xFF
                    }
                }
                r = r shr 2
                g = g shr 2
                b = b shr 2
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                uBuf.put(cy * uRs + cx * uPs, u.coerceIn(0, 255).toByte())
                vBuf.put(cy * vRs + cx * vPs, v.coerceIn(0, 255).toByte())
            }
        }
    }

    companion object {
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

        private fun align16(v: Int) = maxOf(16, (v + 8) / 16 * 16)

        /** Shrinks the requested size until the device encoder accepts it. */
        fun chooseSize(w: Int, h: Int): Pair<Int, Int> {
            var width = align16(w)
            var height = align16(h)
            val caps = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .firstOrNull { it.isEncoder && it.supportedTypes.any { t -> t.equals(MIME, ignoreCase = true) } }
                ?.getCapabilitiesForType(MIME)
                ?.videoCapabilities
                ?: return width to height
            var guard = 0
            while (!caps.isSizeSupported(width, height) && width > 160 && guard++ < 30) {
                width = align16((width * 0.85).toInt())
                height = align16((height * 0.85).toInt())
            }
            return width to height
        }
    }
}
