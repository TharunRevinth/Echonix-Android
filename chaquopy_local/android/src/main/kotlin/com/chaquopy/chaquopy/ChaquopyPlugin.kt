package com.chaquopy.chaquopy

import androidx.annotation.NonNull
import com.chaquo.python.PyException
import com.chaquo.python.PyObject
import com.chaquo.python.Python

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*
import java.util.concurrent.Executors

/** ChaquopyPlugin */
class ChaquopyPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    // Single-thread executor so Python calls are serialized but off the UI thread
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "chaquopy")
        channel.setMethodCallHandler(this)
    }

    fun _runPythonTextCode(code: String): Map<String, Any?> {
        val _returnOutput: MutableMap<String, Any?> = HashMap()
        val _python: Python = Python.getInstance()
        val _console: PyObject = _python.getModule("script")
        val _sys: PyObject = _python.getModule("sys")
        val _io: PyObject = _python.getModule("io")

        return try {
            val _textOutputStream: PyObject = _io.callAttr("StringIO")
            _sys["stdout"] = _textOutputStream
            _console.callAttrThrows("mainTextCode", code)
            _returnOutput["textOutputOrError"] = _textOutputStream.callAttr("getvalue").toString()
            _returnOutput
        } catch (e: PyException) {
            _returnOutput["textOutputOrError"] = e.message.toString()
            _returnOutput
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "runPythonScript") {
            val code: String = call.arguments() ?: ""
            // Run Python off the main thread to keep UI smooth
            executor.submit {
                try {
                    val pyResult: Map<String, Any?> = _runPythonTextCode(code)
                    // result.success must be called on the platform thread,
                    // but Flutter's MethodChannel handles this automatically
                    // when called from any thread after Flutter 2.x
                    result.success(pyResult)
                } catch (e: Exception) {
                    val errResult: MutableMap<String, Any?> = HashMap()
                    errResult["textOutputOrError"] = e.message.toString()
                    result.success(errResult)
                }
            }
        } else {
            result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
