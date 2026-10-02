package com.audiobookshelf.android

import android.content.Context
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.AuthApi
import com.audiobookshelf.core.ErrorText
import com.audiobookshelf.core.ProgressResets
import com.audiobookshelf.core.PublicationLedger

/** Core failures shown on screen, in the app language. */
fun installErrorTexts(context: Context) {
    ErrorText.translate = { error ->
        val resources = context.resources
        when (error) {
            is ApiError.InvalidServer -> resources.getString(R.string.err_invalid_server)
            is ApiError.UnsafeMediaUrl -> resources.getString(R.string.err_unsafe_media_url)
            is ApiError.SignInRequired -> resources.getString(R.string.err_sign_in_required)
            is ApiError.Untrusted -> resources.getString(R.string.err_untrusted)
            is ApiError.Offline -> resources.getString(R.string.err_offline)
            is ApiError.Http -> when (error.status) {
                403 -> resources.getString(R.string.err_forbidden)
                404 -> resources.getString(R.string.err_not_found)
                in 500..599 -> resources.getString(R.string.err_server_problem, error.status)
                else -> resources.getString(R.string.err_rejected, error.status)
            }
            is ApiError.InvalidResponse -> resources.getString(R.string.err_invalid_response)
            is ApiError.NoAudio -> resources.getString(R.string.err_no_audio)
            is AuthApi.LoginRejected -> resources.getString(R.string.err_login_rejected)
            is PublicationLedger.Unreadable -> resources.getString(R.string.err_publications_unreadable)
            is ProgressResets.Unreadable -> resources.getString(R.string.err_discards_unreadable)
            else -> null
        }
    }
}
