package com.kelasagaara.kelasagaara.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.cert.Certificate
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec

/**
 * Android Keystore Device-Bound Key Manager (Phase 20.3)
 *
 * Implements hardware-backed ECDSA P-256 asymmetric key generation,
 * StrongBox evaluation with TEE fallback, Key Attestation certificate
 * export, and transaction signing for Kelasagara biometrics.
 */
class DeviceKeyManager(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val TAG = "DeviceKeyManager"
        const val CHANNEL_NAME = "kelasagara/device_key"
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val DEFAULT_ALIAS = "kelasagara_device_bound_key_v1"
        const val EC_CURVE = "secp256r1"
        const val SIGNATURE_ALGORITHM = "SHA256withECDSA"
    }

    private val keyStore: KeyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply {
        load(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "generateDeviceKey" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                val challengeStr = call.argument<String>("challenge")
                if (challengeStr.isNullOrBlank()) {
                    result.error("INVALID_CHALLENGE", "Attestation challenge cannot be empty", null)
                    return
                }

                try {
                    val challengeBytes = try {
                        Base64.decode(challengeStr, Base64.DEFAULT)
                    } catch (e: Exception) {
                        challengeStr.toByteArray(Charsets.UTF_8)
                    }

                    val keyResult = generateDeviceKey(alias, challengeBytes)
                    result.success(keyResult)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to generate device key: ${e.message}", e)
                    result.error("KEY_GENERATION_FAILED", e.localizedMessage, null)
                }
            }

            "getPublicKey" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                try {
                    val pem = getPublicKeyPem(alias)
                    if (pem != null) {
                        result.success(pem)
                    } else {
                        result.error("KEY_NOT_FOUND", "Device key with alias '$alias' does not exist", null)
                    }
                } catch (e: Exception) {
                    result.error("GET_PUBLIC_KEY_FAILED", e.localizedMessage, null)
                }
            }

            "getCertificateChain" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                try {
                    val chain = getCertificateChainBase64(alias)
                    result.success(chain)
                } catch (e: Exception) {
                    result.error("GET_CERTIFICATE_CHAIN_FAILED", e.localizedMessage, null)
                }
            }

            "signTransaction" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                val dataStr = call.argument<String>("canonicalData")
                if (dataStr.isNullOrBlank()) {
                    result.error("INVALID_DATA", "Data to sign cannot be empty", null)
                    return
                }

                try {
                    val dataBytes = try {
                        Base64.decode(dataStr, Base64.DEFAULT)
                    } catch (e: Exception) {
                        dataStr.toByteArray(Charsets.UTF_8)
                    }

                    val signatureBytes = signData(alias, dataBytes)
                    val signatureBase64 = Base64.encodeToString(signatureBytes, Base64.NO_WRAP)
                    result.success(signatureBase64)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to sign transaction: ${e.message}", e)
                    result.error("SIGNATURE_FAILED", e.localizedMessage, null)
                }
            }

            "hasDeviceKey" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                try {
                    result.success(hasKey(alias))
                } catch (e: Exception) {
                    result.error("KEY_CHECK_FAILED", e.localizedMessage, null)
                }
            }

            "deleteDeviceKey" -> {
                val alias = call.argument<String>("alias") ?: DEFAULT_ALIAS
                try {
                    result.success(deleteKey(alias))
                } catch (e: Exception) {
                    result.error("KEY_DELETION_FAILED", e.localizedMessage, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Generates a device-bound ECDSA P-256 key pair with Android Key Attestation.
     * Evaluates StrongBox on API 28+, falling back to TEE if unavailable.
     */
    fun generateDeviceKey(alias: String, challenge: ByteArray): Map<String, Any> {
        // Delete any existing key under this alias first to ensure clean key state
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }

        var isStrongBox = false
        var keyPairGenerated = false

        // Attempt StrongBox-backed key generation if Android P (API 28)+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generateKeyPairInternal(alias, challenge, useStrongBox = true)
                isStrongBox = true
                keyPairGenerated = true
                Log.i(TAG, "Successfully generated StrongBox-backed device key: $alias")
            } catch (e: Exception) {
                if (e is StrongBoxUnavailableException ||
                    e.cause is StrongBoxUnavailableException ||
                    e.message?.contains("StrongBox", ignoreCase = true) == true
                ) {
                    Log.w(TAG, "StrongBox unavailable on device, falling back to TEE: ${e.message}")
                } else {
                    Log.w(TAG, "StrongBox key generation failed, falling back to TEE: ${e.message}")
                }
            }
        }

        // Fall back to standard TEE / hardware-backed keystore
        if (!keyPairGenerated) {
            generateKeyPairInternal(alias, challenge, useStrongBox = false)
            Log.i(TAG, "Successfully generated TEE/hardware-backed device key: $alias")
        }

        val certChain = getCertificateChain(alias)
        val certChainBase64 = certChain.map { cert ->
            Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
        }

        val publicKeyPem = getPublicKeyPem(alias) ?: throw IllegalStateException("Public key unavailable")

        return mapOf(
            "alias" to alias,
            "publicKeyPem" to publicKeyPem,
            "certificateChain" to certChainBase64,
            "certificateCount" to certChain.size,
            "isStrongBoxBacked" to isStrongBox,
            "hasAttestationChain" to (certChain.size > 1),
            "keyAlgorithm" to "ECDSA_P256",
            "digest" to "SHA256"
        )
    }

    private fun generateKeyPairInternal(alias: String, challenge: ByteArray, useStrongBox: Boolean) {
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE_PROVIDER)

        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN
        ).apply {
            setAlgorithmParameterSpec(ECGenParameterSpec(EC_CURVE))
            setDigests(KeyProperties.DIGEST_SHA256)
            setAttestationChallenge(challenge)
            setUserAuthenticationRequired(false) // Device-bound transport key; human auth verified via SFace
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && useStrongBox) {
            builder.setIsStrongBoxBacked(true)
        }

        kpg.initialize(builder.build())
        kpg.generateKeyPair()
    }

    fun hasKey(alias: String): Boolean {
        return keyStore.containsAlias(alias)
    }

    fun deleteKey(alias: String): Boolean {
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
            return true
        }
        return false
    }

    fun getPublicKeyPem(alias: String): String? {
        val cert = keyStore.getCertificate(alias) ?: return null
        val pubKey = cert.publicKey
        val base64Key = Base64.encodeToString(pubKey.encoded, Base64.DEFAULT)
        return "-----BEGIN PUBLIC KEY-----\n$base64Key-----END PUBLIC KEY-----\n"
    }

    fun getCertificateChain(alias: String): List<Certificate> {
        val chain = keyStore.getCertificateChain(alias)
        return chain?.toList() ?: emptyList()
    }

    fun getCertificateChainBase64(alias: String): List<String> {
        val chain = getCertificateChain(alias)
        return chain.map { cert ->
            Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
        }
    }

    /**
     * Signs transaction canonical data using the hardware-backed private key.
     * Returns standard DER-encoded ASN.1 ECDSA signature bytes.
     */
    fun signData(alias: String, data: ByteArray): ByteArray {
        val privateKey = keyStore.getKey(alias, null) as? PrivateKey
            ?: throw IllegalStateException("Device private key not found for alias '$alias'")

        val signature = Signature.getInstance(SIGNATURE_ALGORITHM)
        signature.initSign(privateKey)
        signature.update(data)
        return signature.sign()
    }
}
