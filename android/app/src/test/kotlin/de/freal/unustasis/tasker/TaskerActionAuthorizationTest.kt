package de.freal.unustasis.tasker

import android.app.Activity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TaskerActionAuthorizationTest {
    private val secret = ByteArray(32) { it.toByte() }

    @Test
    fun signatureIsBoundToActionAndInstallation() {
        val lock = TaskerActionAuthorization.signature(secret, "lock")
        assertTrue(TaskerActionAuthorization.matches(secret, "lock", lock))
        assertFalse(TaskerActionAuthorization.matches(secret, "unlock", lock))
        assertFalse(TaskerActionAuthorization.matches(ByteArray(32), "lock", lock))
        assertFalse(TaskerActionAuthorization.matches(secret, "lock", ""))
    }

    @Test
    fun onlyOfficialTaskerHostsCanRequestSignedConfigurations() {
        assertTrue(TaskerActionAuthorization.isTrustedEditorCaller("net.dinglisch.android.taskerm"))
        assertTrue(TaskerActionAuthorization.isTrustedEditorCaller("net.dinglisch.android.tasker"))
        assertFalse(TaskerActionAuthorization.isTrustedEditorCaller("example.automation.app"))
        assertFalse(TaskerActionAuthorization.isTrustedEditorCaller(null))
    }

    @Test
    fun resultCodesMatchTaskerPluginSetting() {
        assertEquals(Activity.RESULT_OK, TaskerPluginProtocol.RESULT_CODE_OK)
        assertEquals(Activity.RESULT_FIRST_USER + 1, TaskerPluginProtocol.RESULT_CODE_FAILED)
        assertEquals(Activity.RESULT_FIRST_USER + 2, TaskerPluginProtocol.RESULT_CODE_PENDING)
    }
}
