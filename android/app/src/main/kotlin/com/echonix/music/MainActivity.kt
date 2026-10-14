package com.echonix.music

import android.media.audiofx.Virtualizer
import android.media.audiofx.BassBoost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.echonix.music/audio_effects"
    private var virtualizer: Virtualizer? = null
    private var bassBoost: BassBoost? = null
    private var currentSessionId: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initEffects" -> {
                    val sessionId = call.argument<Int>("sessionId")
                    if (sessionId != null) {
                        try {
                            if (currentSessionId != sessionId) {
                                releaseEffects()
                            }
                            currentSessionId = sessionId
                            
                            if (virtualizer == null) {
                                virtualizer = Virtualizer(0, sessionId).apply {
                                    enabled = true
                                }
                            }
                            if (bassBoost == null) {
                                bassBoost = BassBoost(0, sessionId).apply {
                                    enabled = true
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INIT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "SessionId is null", null)
                    }
                }
                "setVirtualizerStrength" -> {
                    val strength = call.argument<Int>("strength")
                    if (strength != null && virtualizer != null) {
                        try {
                            virtualizer?.setStrength(strength.toShort())
                            virtualizer?.enabled = strength > 0
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EFFECT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_INITIALIZED", "Virtualizer not initialized or strength null", null)
                    }
                }
                "setBassBoostStrength" -> {
                    val strength = call.argument<Int>("strength")
                    if (strength != null && bassBoost != null) {
                        try {
                            bassBoost?.setStrength(strength.toShort())
                            bassBoost?.enabled = strength > 0
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("EFFECT_ERROR", e.message, null)
                        }
                    } else {
                        result.error("NOT_INITIALIZED", "BassBoost not initialized or strength null", null)
                    }
                }
                "release" -> {
                    releaseEffects()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun releaseEffects() {
        try {
            virtualizer?.enabled = false
            virtualizer?.release()
            virtualizer = null
        } catch (e: Exception) {}

        try {
            bassBoost?.enabled = false
            bassBoost?.release()
            bassBoost = null
        } catch (e: Exception) {}
        currentSessionId = null
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}

