package com.example.stock_alert_app

import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private var textToSpeech: TextToSpeech? = null
    private var ttsReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName())
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    initMethod() -> {
                        ensureTts()
                        result.success(true)
                    }

                    speakMethod() -> {
                        val text = call.argument<String>(textArgument()).orEmpty().trim()
                        if (text.isEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        ensureTts()
                        result.success(speak(text))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            val locale = Locale.SIMPLIFIED_CHINESE
            val availability = textToSpeech?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
            if (availability >= TextToSpeech.LANG_AVAILABLE) {
                textToSpeech?.language = locale
            }
            textToSpeech?.setSpeechRate(1.0f)
            textToSpeech?.setPitch(1.0f)
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    private fun ensureTts() {
        if (textToSpeech == null) {
            textToSpeech = TextToSpeech(this, this)
        }
    }

    private fun speak(text: String): Boolean {
        if (!ttsReady) {
            return false
        }
        return textToSpeech?.speak(
            text,
            TextToSpeech.QUEUE_FLUSH,
            null,
            utterancePrefix() + System.currentTimeMillis()
        ) == TextToSpeech.SUCCESS
    }

    private fun channelName(): String =
        charArrayOf(
            's', 't', 'o', 'c', 'k', '_', 'a', 'l', 'e', 'r', 't', '_', 'a', 'p', 'p', '/', 't', 't', 's'
        ).concatToString()

    private fun initMethod(): String = charArrayOf('i', 'n', 'i', 't', 'T', 't', 's').concatToString()

    private fun speakMethod(): String = charArrayOf('s', 'p', 'e', 'a', 'k').concatToString()

    private fun textArgument(): String = charArrayOf('t', 'e', 'x', 't').concatToString()

    private fun utterancePrefix(): String =
        charArrayOf('s', 't', 'o', 'c', 'k', '-', 'a', 'l', 'e', 'r', 't', '-').concatToString()
}
