package com.doeimproved.app

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "doe_improved/cookies"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("ARG_NULL", "Missing 'url' argument", null)
                        return@setMethodCallHandler
                    }
                    // CookieManager reads the full native cookie jar,
                    // INCLUDING HttpOnly cookies invisible to document.cookie.
                    val raw = CookieManager.getInstance().getCookie(url)
                    if (raw == null) {
                        result.success(emptyMap<String, String>())
                    } else {
                        val cookies = HashMap<String, String>()
                        for (pair in raw.split(";")) {
                            val idx = pair.indexOf('=')
                            if (idx > 0) {
                                cookies[pair.substring(0, idx).trim()] =
                                    pair.substring(idx + 1).trim()
                            }
                        }
                        result.success(cookies)
                    }
                }
                "clearCookies" -> {
                    CookieManager.getInstance().removeAllCookies { success ->
                        result.success(success)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}