package com.audiobookshelf.core

import okhttp3.HttpUrl

/**
 * Where a cast receiver fetches [track]. Receivers cannot send the app's Authorization header, so,
 * like the existing app, servers from 2.22.0 serve direct play through the open session's public
 * route and older servers take the token in the query.
 */
fun castTrackUrl(address: ServerAddress, serverVersion: String?, sessionId: String, track: AudioTrack, transcoded: Boolean, token: String): HttpUrl {
    val modern = serverVersion?.let { versionAtLeast(it, listOf(2, 22, 0)) } ?: false
    val content = address.mediaUrl(track.contentUrl ?: throw ApiError.NoAudio())
    return when {
        modern && !transcoded -> address.url("public/session/$sessionId/track/${track.index ?: 0}")
        modern -> content
        else -> content.newBuilder().addQueryParameter("token", token).build()
    }
}

private fun versionAtLeast(version: String, minimum: List<Int>): Boolean {
    val parts = version.substringBefore('-').split('.').map { it.toIntOrNull() ?: 0 }
    for (index in minimum.indices) {
        val part = parts.getOrElse(index) { 0 }
        if (part != minimum[index]) return part > minimum[index]
    }
    return true
}
