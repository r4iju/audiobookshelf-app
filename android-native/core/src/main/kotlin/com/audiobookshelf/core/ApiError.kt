package com.audiobookshelf.core

/**
 * Failures are classified so that callers never confuse a transient connection problem with an
 * authorization rejection: only [SignInRequired] may lead to reauthentication.
 */
sealed class ApiError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    override fun getLocalizedMessage(): String? = ErrorText.of(this)

    class InvalidServer : ApiError("Enter a server address starting with http:// or https://, for example https://books.example.com/abs.")
    class UnsafeMediaUrl : ApiError("The server returned a media address outside this server. It was not opened.")
    /** [account] and [rejectedToken] identify which saved session was refused, so a late failure cannot sign out another one. */
    class SignInRequired(val account: AccountIdentity? = null, val rejectedToken: String? = null) :
        ApiError("Your session is no longer accepted. Sign in again; unsent listening is kept.")
    class Untrusted(cause: Throwable) : ApiError(
        "The server's certificate is not trusted by this device. Install your server's certificate authority in Android Settings > Security > Encryption & credentials, then try again.",
        cause,
    )
    class Offline(cause: Throwable) : ApiError("The server could not be reached. Check the address or your connection and try again.", cause)
    class Http(val status: Int, val body: String? = null) : ApiError(
        when (status) {
            403 -> "Your account is not allowed to do this."
            404 -> "This content is no longer available on the server."
            in 500..599 -> "The server had a temporary problem (HTTP $status). Try again."
            else -> "The server rejected the request (HTTP $status)."
        },
    )
    class InvalidResponse(cause: Throwable? = null) : ApiError("The server sent a response this app could not read.", cause)
    class NoAudio : ApiError("This item has no playable audio.")
}
