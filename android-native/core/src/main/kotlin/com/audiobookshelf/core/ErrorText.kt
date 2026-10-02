package com.audiobookshelf.core

/**
 * What a person reads for a core failure. [Throwable.message] stays English for diagnostics; the app installs
 * [translate] at start, so [Throwable.getLocalizedMessage], which screens show, follows the app language.
 */
object ErrorText {
    @Volatile var translate: (Throwable) -> String? = { null }

    internal fun of(error: Throwable): String? = translate(error) ?: error.message
}
