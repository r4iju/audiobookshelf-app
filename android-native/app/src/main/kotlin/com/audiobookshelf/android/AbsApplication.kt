package com.audiobookshelf.android

import android.app.Application
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor

class AbsApplication : Application(), SingletonImageLoader.Factory {
    override fun newImageLoader(context: PlatformContext): ImageLoader {
        // Artwork needs the bearer token, but only for the active server's own origin and subpath.
        val auth = Interceptor { chain ->
            val request = chain.request()
            val client = graph.accounts.activeClient
            val authorized = client?.takeIf { it.owns(request.url) }?.let { runCatching { runBlocking { it.bearer() } }.getOrNull() }
            chain.proceed(if (authorized != null) request.newBuilder().header("Authorization", "Bearer $authorized").build() else request)
        }
        val http = graph.http.newBuilder().addInterceptor(auth).build()
        return ImageLoader.Builder(context).components { add(OkHttpNetworkFetcherFactory(callFactory = { http })) }.build()
    }
}
