package com.kelasagaara.kelasagaara

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.kelasagaara.kelasagaara.security.DeviceKeyManager

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "kelasagara/external_navigation"
    private val CHANNEL_SECURITY = "kelasagara/security_attestation"
    private val CHANNEL_UIDAI = "kelasagara/uidai_facerd"

    private var uidaiBridge: UidaiFaceRdBridge? = null
    private var playIntegrityBridge: PlayIntegrityBridge? = null
    private var deviceKeyManager: DeviceKeyManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        uidaiBridge = UidaiFaceRdBridge(this)
        playIntegrityBridge = PlayIntegrityBridge(this)
        deviceKeyManager = DeviceKeyManager(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PlayIntegrityBridge.CHANNEL_NAME)
            .setMethodCallHandler(playIntegrityBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DeviceKeyManager.CHANNEL_NAME)
            .setMethodCallHandler(deviceKeyManager)

        val handleUidaiCall: (io.flutter.plugin.common.MethodCall, MethodChannel.Result) -> Unit = { call, result ->
            when (call.method) {
                "isInstalled" -> {
                    result.success(uidaiBridge?.isInstalled() ?: false)
                }
                "launchFaceRdCapture", "capture" -> {
                    val txnId = call.argument<String>("transactionId") ?: System.currentTimeMillis().toString()
                    uidaiBridge?.launchFaceRdCapture(txnId, result)
                }
                "generateLocalBioRdPidBlockXml" -> {
                    val txnId = call.argument<String>("transactionId") ?: System.currentTimeMillis().toString()
                    val wadh = call.argument<String>("wadh") ?: "2.5FYYNN"
                    val frameSha256 = call.argument<String>("frameSha256Hex") ?: ""
                    val cosineScore = call.argument<Double>("cosineMaxScore") ?: 0.0
                    val laplacian = call.argument<Double>("laplacianVariance") ?: 150.0
                    val xml = uidaiBridge?.generateLocalBioRdPidBlockXml(txnId, wadh, frameSha256, cosineScore, laplacian)
                    result.success(xml ?: "")
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_UIDAI).setMethodCallHandler(handleUidaiCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "in.kelasagara/aadhaar_facerd").setMethodCallHandler(handleUidaiCall)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SECURITY).setMethodCallHandler { call, result ->
            if (call.method == "checkDeviceSecurity") {
                try {
                    val assessment = SecurityHardeningEngine.assessDeviceSecurity(applicationContext)
                    result.success(assessment)
                } catch (e: Exception) {
                    result.error("SECURITY_CHECK_FAILED", e.localizedMessage, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "launchGoogleMaps") {
                val urlString = call.argument<String>("url")
                if (urlString.isNullOrBlank()) {
                    result.error("INVALID_URL", "URL must not be empty", null)
                    return@setMethodCallHandler
                }

                try {
                    val uri = Uri.parse(urlString)
                    // 1. Try launching specifically with Google Maps package
                    val mapsIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                        setPackage("com.google.android.apps.maps")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(mapsIntent)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    // 2. Google Maps package not installed -> fallback to browser / unqualified intent
                    try {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(urlString)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(browserIntent)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("LAUNCH_FAILED", e2.localizedMessage, null)
                    }
                } catch (e: Exception) {
                    // Any other failure, attempt browser fallback
                    try {
                        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(urlString)).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(browserIntent)
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("LAUNCH_FAILED", e.localizedMessage, null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (uidaiBridge?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}


