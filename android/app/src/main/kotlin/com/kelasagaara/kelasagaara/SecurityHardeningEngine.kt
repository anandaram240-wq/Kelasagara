package com.kelasagaara.kelasagaara

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import java.io.File

object SecurityHardeningEngine {

    /**
     * Checks if the device has signs of root access or compromised OS integrity.
     */
    fun isDeviceRooted(): Boolean {
        // 1. Check test-keys
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) {
            return true
        }

        // 2. Check standard SU binary locations
        val suPaths = arrayOf(
            "/system/app/Superuser.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/xbin/su",
            "/data/local/bin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/data/local/su"
        )
        for (path in suPaths) {
            try {
                if (File(path).exists()) return true
            } catch (_: Exception) {}
        }

        // 3. Check for Magisk / KernelSU mounts in /proc/self/mounts
        try {
            val mountsFile = File("/proc/self/mounts")
            if (mountsFile.exists() && mountsFile.canRead()) {
                val mounts = mountsFile.readText()
                if (mounts.contains("magisk") || mounts.contains("core/mirror") || mounts.contains("ksu")) {
                    return true
                }
            }
        } catch (_: Exception) {}

        return false
    }

    /**
     * Scans process memory maps for dynamic instrumentation hooks (Frida, Xposed, Substrate).
     */
    fun isDynamicHookDetected(): Boolean {
        try {
            val mapsFile = File("/proc/self/maps")
            if (mapsFile.exists() && mapsFile.canRead()) {
                val maps = mapsFile.readText()
                if (maps.contains("frida") || maps.contains("xposed") || maps.contains("substrate") || maps.contains("edxposed")) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }

    /**
     * Checks if the active camera hardware is a mock, virtual, or legacy camera injection.
     */
    fun isVirtualOrMockCamera(context: Context): Boolean {
        try {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return false
            val cameraIds = manager.cameraIdList
            if (cameraIds.isEmpty()) return true

            // Look for front camera
            for (id in cameraIds) {
                val chars = manager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                    val hwLevel = chars.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
                    // On physical devices, modern cameras are at least LIMITED (0) or FULL (1) / LEVEL_3 (3).
                    // Emulators and virtual mock cameras often report LEGACY (2).
                    if (hwLevel == CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY && isEmulator()) {
                        return true
                    }
                }
            }
        } catch (_: Exception) {}
        return false
    }

    fun isEmulator(): Boolean {
        return (Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.MANUFACTURER.contains("Genymotion")
                || (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
                || "google_sdk" == Build.PRODUCT
                || Build.HARDWARE.contains("goldfish")
                || Build.HARDWARE.contains("ranchu"))
    }

    /**
     * Comprehensive security assessment returns a Map with status breakdown.
     */
    fun assessDeviceSecurity(context: Context): Map<String, Any> {
        val rooted = isDeviceRooted()
        val hooked = isDynamicHookDetected()
        val mockCam = isVirtualOrMockCamera(context)
        val emulator = isEmulator()
        val isPassed = !rooted && !hooked && !mockCam

        return mapOf(
            "isSecure" to isPassed,
            "isRooted" to rooted,
            "isHooked" to hooked,
            "isVirtualCamera" to mockCam,
            "isEmulator" to emulator
        )
    }
}
