package com.audiobookshelf.android.data

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.audiobookshelf.core.AbsJson
import com.audiobookshelf.core.Credentials
import com.audiobookshelf.core.writeAtomically
import kotlinx.serialization.Serializable
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@Serializable data class SavedConnection(
    val id: String,
    val credentials: Credentials,
    val libraryId: String? = null,
    /** Set when the server rejected the session; the connection and its local data are kept. */
    val needsSignIn: Boolean = false,
)

@Serializable data class VaultDocument(val version: Int = 1, val connections: List<SavedConnection> = emptyList(), val activeId: String? = null)

/**
 * Saved connections encrypted with an app-owned Android Keystore key. The alias is distinct from
 * the legacy app's `AudiobookshelfRefreshTokens` so the two clients never overwrite each other.
 */
class CredentialVault(private val file: File) {
    class Unreadable(cause: Throwable) : Exception("Saved sign-ins could not be decrypted. They are kept on the device; sign in again to continue.", cause)

    @Synchronized
    fun load(): VaultDocument {
        if (!file.exists()) return VaultDocument()
        return try {
            val data = file.readBytes()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, IV_LENGTH)))
            AbsJson.decodeFromString(VaultDocument.serializer(), cipher.doFinal(data, IV_LENGTH, data.size - IV_LENGTH).decodeToString())
        } catch (error: Exception) {
            throw Unreadable(error)
        }
    }

    @Synchronized
    fun save(document: VaultDocument) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(AbsJson.encodeToString(VaultDocument.serializer(), document).toByteArray())
        writeAtomically(file, sealed)
    }

    @Synchronized
    fun update(transform: (VaultDocument) -> VaultDocument): VaultDocument = transform(load()).also(::save)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ALIAS = "AudiobookshelfNativeVault"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
    }
}
