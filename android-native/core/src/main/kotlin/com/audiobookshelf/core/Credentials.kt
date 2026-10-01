package com.audiobookshelf.core

import kotlinx.serialization.Serializable

/** Server plus server-side user ID: the unit that isolates credentials, downloads and listening history. */
@Serializable data class AccountIdentity(val server: String, val userId: String) {
    init {
        require(userId.isNotEmpty())
    }
    /** Filesystem-safe key, stable for the same canonical server and user. */
    val storageKey: String get() = sha256Hex("$server\n$userId").take(24)
}

@Serializable data class Credentials(
    val server: String,
    val userId: String,
    val username: String,
    val accessToken: String,
    val refreshToken: String? = null,
) {
    val account get() = AccountIdentity(server, userId)
    val address get() = ServerAddress.parse(server)
    override fun toString() = "Credentials(server=$server, user=$username, refresh=${refreshToken != null})"
}

/** Persists rotated credentials before the rotated token is used again. */
fun interface CredentialSink {
    fun rotated(previous: Credentials, next: Credentials)
}

@Serializable data class DeviceInfo(
    val deviceId: String,
    val clientName: String = "Audiobookshelf Android",
    val clientVersion: String = "native-preview",
    val manufacturer: String = "",
    val model: String = "",
    val sdkVersion: Int = 0,
)

internal fun sha256Hex(value: String): String =
    java.security.MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
