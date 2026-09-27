package com.afaanoromo.stt

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL      = "com.afaanoromo.stt/audio_decoder"
    private val URL_CHANNEL  = "com.afaanoromo.stt/url_launcher"
    private val NOTIF_CHANNEL = "com.afaanoromo.stt/notifications"

    private val NOTIF_CHANNEL_ID   = "afaanoromo_tasks"
    private val NOTIF_CHANNEL_NAME = "Task Notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Audio decoder channel ────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeAudio" -> {
                    val audioPath = call.argument<String>("audioPath")
                    val targetSampleRate = call.argument<Int>("targetSampleRate") ?: 16000
                    if (audioPath != null) {
                        try {
                            val samples = decodeAudioToFloat32(audioPath, targetSampleRate)
                            result.success(samples)
                        } catch (e: Exception) {
                            result.error("DECODE_ERROR", "Failed to decode audio: ${e.message}", null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Audio path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── URL launcher channel (no url_launcher package needed) ────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, URL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launch" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LAUNCH_ERROR", "Could not open URL: ${e.message}", null)
                        }
                    } else {
                        result.error("INVALID_URL", "URL is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── Notifications channel ────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    createNotificationChannel()
                    result.success(true)
                }
                "showNotification" -> {
                    val id    = call.argument<Int>("id") ?: 0
                    val title = call.argument<String>("title") ?: "Afaan Oromo AI"
                    val body  = call.argument<String>("body")  ?: ""
                    showNotification(id, title, body)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                NOTIF_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifications when speech tasks complete"
                enableVibration(true)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun showNotification(id: Int, title: String, body: String) {
        createNotificationChannel()
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(id, notification)
    }

    private fun decodeAudioToFloat32(audioPath: String, targetSampleRate: Int): FloatArray {
        val extractor = MediaExtractor()
        extractor.setDataSource(audioPath)

        var audioTrackIndex = -1
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                break
            }
        }

        if (audioTrackIndex == -1) {
            throw Exception("No audio track found in file")
        }

        extractor.selectTrack(audioTrackIndex)
        val format = extractor.getTrackFormat(audioTrackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME) ?: throw Exception("No MIME type")

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val samples = mutableListOf<Short>()
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        
        val channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT, 1)

        while (!outputDone) {
            if (!inputDone) {
                val inputBufferIndex = codec.dequeueInputBuffer(10000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = codec.getInputBuffer(inputBufferIndex)
                    val sampleSize = extractor.readSampleData(inputBuffer!!, 0)
                    
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }

            val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputBufferIndex >= 0) {
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    outputDone = true
                }
                
                if (bufferInfo.size > 0) {
                    val outputBuffer = codec.getOutputBuffer(outputBufferIndex)
                    outputBuffer?.let {
                        it.position(bufferInfo.offset)
                        it.limit(bufferInfo.offset + bufferInfo.size)
                        it.order(ByteOrder.LITTLE_ENDIAN)
                        val shortBuffer = it.asShortBuffer()
                        val tempSamples = ShortArray(shortBuffer.remaining())
                        shortBuffer.get(tempSamples)
                        samples.addAll(tempSamples.toList())
                    }
                }
                codec.releaseOutputBuffer(outputBufferIndex, false)
            } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                // Output format changed, ignore
            }
        }

        codec.stop()
        codec.release()
        extractor.release()
        
        val monoSamples = if (channelCount > 1) {
            convertToMono(samples.toShortArray(), channelCount)
        } else {
            samples.toShortArray()
        }

        val sourceSampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE, 44100)
        val floatSamples = monoSamples.map { it / 32768.0f }.toFloatArray()
        
        val resampledSamples = if (sourceSampleRate != targetSampleRate) {
            resample(floatSamples, sourceSampleRate, targetSampleRate)
        } else {
            floatSamples
        }
        
        return resampledSamples
    }

    private fun convertToMono(samples: ShortArray, channelCount: Int): ShortArray {
        val monoSamples = ShortArray(samples.size / channelCount)
        for (i in monoSamples.indices) {
            var sum = 0
            for (ch in 0 until channelCount) {
                sum += samples[i * channelCount + ch]
            }
            monoSamples[i] = (sum / channelCount).toShort()
        }
        return monoSamples
    }

    private fun resample(samples: FloatArray, sourceSampleRate: Int, targetSampleRate: Int): FloatArray {
        if (sourceSampleRate == targetSampleRate) {
            return samples
        }

        val ratio = targetSampleRate.toDouble() / sourceSampleRate.toDouble()
        val outputLength = (samples.size * ratio).toInt()
        val output = FloatArray(outputLength)

        for (i in output.indices) {
            val srcIndex = i / ratio
            val srcIndexInt = srcIndex.toInt()
            
            if (srcIndexInt < samples.size - 1) {
                val fraction = srcIndex - srcIndexInt
                output[i] = (samples[srcIndexInt] * (1 - fraction) + samples[srcIndexInt + 1] * fraction).toFloat()
            } else if (srcIndexInt < samples.size) {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }
}
