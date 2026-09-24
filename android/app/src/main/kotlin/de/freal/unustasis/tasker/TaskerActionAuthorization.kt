package de.freal.unustasis.tasker

import android.content.Context
import android.os.Bundle
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Only a configuration issued by this app's Tasker editor can fire an action. */
object TaskerActionAuthorization {
    private val editorCallers = setOf("net.dinglisch.android.taskerm", "net.dinglisch.android.tasker")
    const val BUNDLE_KEY_SIGNATURE = "de.freal.unustasis.tasker.SIGNATURE"
    private const val PREF_FILE = "tasker_authorization"
    private const val PREF_KEY = "signing_key"
    private val hex = "0123456789abcdef".toCharArray()

    fun isTrustedEditorCaller(packageName: String?): Boolean = packageName in editorCallers

    fun sign(context: Context, action: TaskerAction): String =
        signature(secret(context, create = true)!!, action.key)

    fun accepts(context: Context, action: TaskerAction, settings: Bundle?): Boolean {
        val supplied = settings?.getString(BUNDLE_KEY_SIGNATURE) ?: return false
        val key = secret(context, create = false) ?: return false
        return matches(key, action.key, supplied)
    }

    private fun secret(context: Context, create: Boolean): ByteArray? = synchronized(this) {
        val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val saved = prefs.getString(PREF_KEY, null)
        if (saved != null) {
            val decoded = try {
                Base64.decode(saved, Base64.NO_WRAP).takeIf { it.size == 32 }
            } catch (_: IllegalArgumentException) {
                null
            }
            if (decoded != null || !create) return@synchronized decoded
        }
        if (!create) return@synchronized null
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        check(prefs.edit().putString(PREF_KEY, Base64.encodeToString(bytes, Base64.NO_WRAP)).commit()) {
            "Tasker authorization could not be stored"
        }
        bytes
    }

    internal fun signature(secret: ByteArray, action: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return buildString {
            for (byte in mac.doFinal(action.toByteArray(Charsets.UTF_8))) {
                val value = byte.toInt() and 0xff
                append(hex[value ushr 4])
                append(hex[value and 0x0f])
            }
        }
    }

    internal fun matches(secret: ByteArray, action: String, supplied: String): Boolean {
        val expected = signature(secret, action)
        return MessageDigest.isEqual(
            expected.toByteArray(Charsets.US_ASCII),
            supplied.toByteArray(Charsets.US_ASCII),
        )
    }
}
