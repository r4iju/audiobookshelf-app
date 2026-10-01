package com.audiobookshelf.android

import android.content.Context
import android.os.Build
import com.audiobookshelf.android.data.AccountStore
import com.audiobookshelf.android.data.CredentialVault
import com.audiobookshelf.android.data.SettingsStore
import com.audiobookshelf.core.DeviceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.OkHttpClient
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Process-wide dependencies, created lazily so tests can reset app data before first use. */
class AppGraph private constructor(val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    val deviceInfo: DeviceInfo by lazy {
        val file = File(context.filesDir, "device-id")
        val id = file.takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }
            ?: UUID.randomUUID().toString().also { file.parentFile?.mkdirs(); file.writeText(it) }
        DeviceInfo(id, "Audiobookshelf Android", BuildConfig.VERSION_NAME, Build.MANUFACTURER, Build.MODEL, Build.VERSION.SDK_INT)
    }
    val settings by lazy { SettingsStore(File(context.filesDir, "settings.json")) }
    val accounts by lazy { AccountStore(CredentialVault(File(context.noBackupFilesDir, "vault/connections.bin")), http, deviceInfo).also { it.restore() } }

    companion object {
        @Volatile private var instance: AppGraph? = null
        fun get(context: Context): AppGraph = instance ?: synchronized(this) {
            instance ?: AppGraph(context.applicationContext).also { instance = it }
        }
    }
}

val Context.graph: AppGraph get() = AppGraph.get(this)
