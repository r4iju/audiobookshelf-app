package com.audiobookshelf.core

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** A user-entered server base, which may include a reverse-proxy subpath. */
class ServerAddress private constructor(val base: HttpUrl) {
    private val prefix: List<String> = base.pathSegments.filter { it.isNotEmpty() }

    /** Canonical form used to isolate accounts: lowercase scheme/host, default port elided, no trailing slash. */
    val canonical: String = base.newBuilder().encodedPath("/" + prefix.joinToString("/") { it.encodePathSegment() }).build()
        .toString().trimEnd('/')

    fun url(path: String, query: List<Pair<String, String>> = emptyList()): HttpUrl {
        val builder = base.newBuilder().encodedPath("/")
        prefix.forEach { builder.addPathSegment(it) }
        path.trim('/').split('/').filter { it.isNotEmpty() }.forEach { builder.addEncodedPathSegment(it) }
        query.forEach { (name, value) -> builder.addQueryParameter(name, value) }
        return builder.build()
    }

    /** Resolves a server-provided media path, rejecting anything that would leave this server. */
    fun mediaUrl(path: String): HttpUrl {
        if (path.startsWith("//") || path.contains('\\')) throw ApiError.UnsafeMediaUrl()
        if (Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:").containsMatchIn(path)) {
            val absolute = path.toHttpUrlOrNull() ?: throw ApiError.UnsafeMediaUrl()
            if (absolute.scheme != base.scheme || absolute.host != base.host || absolute.port != base.port ||
                absolute.username.isNotEmpty() || absolute.password.isNotEmpty()
            ) throw ApiError.UnsafeMediaUrl()
            return absolute
        }
        val relative = ("http://relative.invalid/" + path.trimStart('/')).toHttpUrlOrNull() ?: throw ApiError.UnsafeMediaUrl()
        if (relative.pathSegments.any { it == ".." }) throw ApiError.UnsafeMediaUrl()
        val builder = base.newBuilder().encodedPath("/")
        prefix.forEach { builder.addPathSegment(it) }
        relative.encodedPathSegments.filter { it.isNotEmpty() }.forEach { builder.addEncodedPathSegment(it) }
        builder.encodedQuery(relative.encodedQuery)
        return builder.build()
    }

    /** True when [url] is on this server's origin and inside its subpath, so credentials may be attached. */
    fun contains(url: HttpUrl): Boolean =
        url.scheme == base.scheme && url.host == base.host && url.port == base.port &&
            url.pathSegments.size >= prefix.size && url.pathSegments.subList(0, prefix.size) == prefix

    override fun toString(): String = canonical
    override fun equals(other: Any?) = other is ServerAddress && other.canonical == canonical
    override fun hashCode() = canonical.hashCode()

    companion object {
        fun parse(raw: String): ServerAddress {
            val trimmed = raw.trim()
            val scheme = trimmed.substringBefore("://", "").lowercase()
            if (scheme != "http" && scheme != "https") throw ApiError.InvalidServer()
            if (trimmed.contains('?') || trimmed.contains('#')) throw ApiError.InvalidServer()
            val url = trimmed.toHttpUrlOrNull() ?: throw ApiError.InvalidServer()
            if (url.host.isEmpty() || url.username.isNotEmpty() || url.password.isNotEmpty()) throw ApiError.InvalidServer()
            return ServerAddress(url)
        }

        private fun String.encodePathSegment() = HttpUrl.Builder().scheme("http").host("x").addPathSegment(this).build().encodedPathSegments.single()
    }
}
