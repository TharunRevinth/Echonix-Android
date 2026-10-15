package com.chaquopy.chaquopy

import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.chaquo.python.Python

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** ChaquopyPlugin */
class ChaquopyPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    // Two thread pools: priority (2 threads) and background (2 threads)
    private val priorityExecutor: ExecutorService = Executors.newFixedThreadPool(2)
    private val backgroundExecutor: ExecutorService = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "chaquopy")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "invoke" -> {
                val fn: String = call.argument<String>("fn") ?: ""
                val args: String = call.argument<String>("args") ?: "{}"
                val requestedLane: String = call.argument<String>("lane") ?: "background"

                // Priority lane is used ONLY for get_stream_url, resolve_stream, diagnose_stream, rate_song, login_with_cookie, check_auth_status, init_ytmusic
                val isPriority = requestedLane == "priority" || fn in setOf(
                    "get_stream_url",
                    "resolve_stream",
                    "diagnose_stream",
                    "rate_song",
                    "login_with_cookie",
                    "check_auth_status",
                    "init_ytmusic"
                )
                val executor = if (isPriority) priorityExecutor else backgroundExecutor

                executor.submit {
                    try {
                        val python = Python.getInstance()
                        val backend = python.getModule("echonix_backend")
                        val pyResult = backend.callAttr("dispatch", fn, args).toString()
                        mainHandler.post {
                            result.success(pyResult)
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            val err = e.message ?: "Python execution error"
                            result.success("{\"success\": false, \"error\": ${JSONObject.quote(err)}}")
                        }
                    }
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        priorityExecutor.shutdown()
        backgroundExecutor.shutdown()
    }
}

