package com.kelasagaara.kelasagaara

import android.content.Context
import android.util.Log
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityException
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.model.StandardIntegrityErrorCode
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * KELASAGARA V20.2: Trusted Android Application Integrity Engine
 * Native bridge providing Standard Play Integrity API integration to Flutter.
 */
class PlayIntegrityBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val TAG = "PlayIntegrityBridge"
        const val CHANNEL_NAME = "kelasagara/play_integrity"
        const val DEFAULT_CLOUD_PROJECT_NUMBER: Long = 993968093461L // Google Cloud Project: kelasagara-f127a
    }

    private val standardIntegrityManager: StandardIntegrityManager by lazy {
        IntegrityManagerFactory.createStandard(context.applicationContext)
    }

    @Volatile
    private var tokenProvider: StandardIntegrityTokenProvider? = null

    @Volatile
    private var isPreparing = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepareIntegrityProvider" -> {
                val cloudProjectNumber = call.argument<Number>("cloudProjectNumber")?.toLong()
                    ?: DEFAULT_CLOUD_PROJECT_NUMBER
                prepareIntegrityProvider(cloudProjectNumber, result)
            }
            "requestIntegrityToken" -> {
                val requestHash = call.argument<String>("requestHash")
                if (requestHash.isNullOrBlank()) {
                    result.error(
                        "INVALID_ARGUMENT",
                        "requestHash parameter is required and cannot be empty",
                        null
                    )
                    return
                }
                requestIntegrityToken(requestHash, result)
            }
            "refreshIntegrityProvider" -> {
                val cloudProjectNumber = call.argument<Number>("cloudProjectNumber")?.toLong()
                    ?: DEFAULT_CLOUD_PROJECT_NUMBER
                disposeIntegrityProvider()
                prepareIntegrityProvider(cloudProjectNumber, result)
            }
            "disposeIntegrityProvider" -> {
                disposeIntegrityProvider()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    fun prepareIntegrityProvider(cloudProjectNumber: Long, result: MethodChannel.Result? = null) {
        if (tokenProvider != null) {
            Log.d(TAG, "StandardIntegrityTokenProvider is already prepared.")
            result?.success(true)
            return
        }

        if (isPreparing) {
            Log.d(TAG, "StandardIntegrityTokenProvider is currently preparing.")
            result?.success(true)
            return
        }

        isPreparing = true
        Log.i(TAG, "Preparing StandardIntegrityTokenProvider for project $cloudProjectNumber...")

        val request = PrepareIntegrityTokenRequest.builder()
            .setCloudProjectNumber(cloudProjectNumber)
            .build()

        standardIntegrityManager.prepareIntegrityToken(request)
            .addOnSuccessListener { provider ->
                synchronized(this) {
                    tokenProvider = provider
                    isPreparing = false
                }
                Log.i(TAG, "StandardIntegrityTokenProvider prepared successfully.")
                result?.success(true)
            }
            .addOnFailureListener { exception ->
                synchronized(this) {
                    tokenProvider = null
                    isPreparing = false
                }
                val mappedError = mapNativeError(exception)
                Log.e(TAG, "Failed to prepare StandardIntegrityTokenProvider: ${mappedError.code} - ${mappedError.message}", exception)
                result?.error(mappedError.code, mappedError.message, mappedError.details)
            }
    }

    fun requestIntegrityToken(requestHash: String, result: MethodChannel.Result) {
        val provider = tokenProvider
        if (provider == null) {
            Log.w(TAG, "requestIntegrityToken called but provider is not initialized. Auto-initiating warmup.")
            val request = PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(DEFAULT_CLOUD_PROJECT_NUMBER)
                .build()

            standardIntegrityManager.prepareIntegrityToken(request)
                .addOnSuccessListener { freshProvider ->
                    synchronized(this) {
                        tokenProvider = freshProvider
                    }
                    executeTokenRequest(freshProvider, requestHash, result)
                }
                .addOnFailureListener { exception ->
                    val mappedError = mapNativeError(exception)
                    result.error(mappedError.code, mappedError.message, mappedError.details)
                }
            return
        }

        executeTokenRequest(provider, requestHash, result)
    }

    private fun executeTokenRequest(
        provider: StandardIntegrityTokenProvider,
        requestHash: String,
        result: MethodChannel.Result
    ) {
        val tokenRequest = StandardIntegrityTokenRequest.builder()
            .setRequestHash(requestHash)
            .build()

        provider.request(tokenRequest)
            .addOnSuccessListener { response ->
                val token = response.token()
                Log.d(TAG, "Integrity token acquired successfully (length: ${token.length}).")
                result.success(token)
            }
            .addOnFailureListener { exception ->
                if (exception is StandardIntegrityException &&
                    exception.errorCode == StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID
                ) {
                    Log.w(TAG, "Integrity provider expired. Refreshing provider...")
                    synchronized(this) {
                        tokenProvider = null
                    }
                    prepareIntegrityProvider(DEFAULT_CLOUD_PROJECT_NUMBER, object : MethodChannel.Result {
                        override fun success(res: Any?) {
                            val refreshedProvider = tokenProvider
                            if (refreshedProvider != null) {
                                executeTokenRequest(refreshedProvider, requestHash, result)
                            } else {
                                result.error("PROVIDER_EXPIRED", "Integrity provider expired and could not be renewed.", null)
                            }
                        }
                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            result.error(errorCode, errorMessage, errorDetails)
                        }
                        override fun notImplemented() {
                            result.notImplemented()
                        }
                    })
                    return@addOnFailureListener
                }

                val mappedError = mapNativeError(exception)
                Log.e(TAG, "Failed to acquire integrity token: ${mappedError.code} - ${mappedError.message}")
                result.error(mappedError.code, mappedError.message, mappedError.details)
            }
    }

    @Synchronized
    fun disposeIntegrityProvider() {
        tokenProvider = null
        isPreparing = false
        Log.d(TAG, "StandardIntegrityTokenProvider disposed.")
    }

    private data class MappedError(val code: String, val message: String, val details: Map<String, Any>?)

    private fun mapNativeError(exception: Exception): MappedError {
        if (exception is StandardIntegrityException) {
            val code = when (exception.errorCode) {
                StandardIntegrityErrorCode.PLAY_SERVICES_NOT_FOUND,
                StandardIntegrityErrorCode.PLAY_SERVICES_VERSION_OUTDATED -> "PLAY_SERVICES_UNAVAILABLE"
                StandardIntegrityErrorCode.PLAY_STORE_NOT_FOUND -> "PLAY_STORE_UNAVAILABLE"
                StandardIntegrityErrorCode.NETWORK_ERROR -> "NETWORK_UNAVAILABLE"
                StandardIntegrityErrorCode.INTEGRITY_TOKEN_PROVIDER_INVALID -> "PROVIDER_EXPIRED"
                StandardIntegrityErrorCode.CLIENT_TRANSIENT_ERROR -> "INTEGRITY_REQUEST_FAILED"
                StandardIntegrityErrorCode.APP_NOT_INSTALLED -> "UNSUPPORTED_DEVICE"
                StandardIntegrityErrorCode.INTERNAL_ERROR -> "INTERNAL_NATIVE_ERROR"
                else -> "INTEGRITY_REQUEST_FAILED"
            }
            return MappedError(
                code = code,
                message = exception.localizedMessage ?: "StandardIntegrity error ${exception.errorCode}",
                details = mapOf("errorCode" to exception.errorCode)
            )
        }

        val msg = (exception.localizedMessage ?: "").lowercase()
        val code = when {
            msg.contains("network") || msg.contains("timeout") || msg.contains("connection") -> "NETWORK_UNAVAILABLE"
            msg.contains("play store") -> "PLAY_STORE_UNAVAILABLE"
            msg.contains("play services") -> "PLAY_SERVICES_UNAVAILABLE"
            else -> "INTERNAL_NATIVE_ERROR"
        }

        return MappedError(
            code = code,
            message = exception.localizedMessage ?: "Unexpected native integrity error",
            details = null
        )
    }
}
