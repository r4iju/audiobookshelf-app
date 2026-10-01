package com.audiobookshelf.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

val AbsJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
    isLenient = true
}

/** Server 2.30.0 sends some durations as numeric strings. */
object LenientDoubleSerializer : KSerializer<Double> {
    override val descriptor = PrimitiveSerialDescriptor("LenientDouble", PrimitiveKind.DOUBLE)
    override fun deserialize(decoder: Decoder): Double {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement() ?: return decoder.decodeDouble()
        return (element as? JsonPrimitive)?.let { it.doubleOrNull ?: it.content.toDoubleOrNull() } ?: 0.0
    }
    override fun serialize(encoder: Encoder, value: Double) = encoder.encodeDouble(value)
}

@Serializable data class ServerStatus(
    val isInit: Boolean = true,
    val authMethods: List<String> = listOf("local"),
    val serverVersion: String? = null,
    val version: String? = null,
    val language: String? = null,
)

@Serializable data class Permissions(
    val download: Boolean = false,
    val update: Boolean = false,
    val delete: Boolean = false,
    val upload: Boolean = false,
    val accessExplicitContent: Boolean = true,
    val accessAllLibraries: Boolean = true,
)

@Serializable data class Bookmark(
    val libraryItemId: String,
    val title: String = "",
    val time: Double,
    val createdAt: Double? = null,
)

@Serializable data class MediaProgress(
    val id: String? = null,
    val libraryItemId: String,
    val episodeId: String? = null,
    val duration: Double = 0.0,
    val progress: Double = 0.0,
    val currentTime: Double = 0.0,
    val isFinished: Boolean = false,
    val hideFromContinueListening: Boolean = false,
    val ebookLocation: String? = null,
    val ebookProgress: Double? = null,
    val lastUpdate: Double? = null,
)

@Serializable data class User(
    val id: String,
    val username: String = "",
    val type: String = "user",
    val permissions: Permissions = Permissions(),
    val mediaProgress: List<MediaProgress> = emptyList(),
    val bookmarks: List<Bookmark> = emptyList(),
    val librariesAccessible: List<String> = emptyList(),
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val token: String? = null,
) {
    val isAdmin get() = type == "admin" || type == "root"
    /** Modern servers return accessToken; older servers only the long-lived legacy token. */
    val bearerToken get() = accessToken?.takeIf { it.isNotEmpty() } ?: token
}

@Serializable data class AuthResponse(val user: User, val userDefaultLibraryId: String? = null)

@Serializable data class LibraryFolder(val id: String, val fullPath: String = "")

@Serializable data class Library(
    val id: String,
    val name: String,
    val mediaType: String = "book",
    val folders: List<LibraryFolder> = emptyList(),
) {
    val isPodcast get() = mediaType == "podcast"
}

@Serializable data class LibrariesResponse(val libraries: List<Library> = emptyList())

@Serializable data class NamedRef(val id: String = "", val name: String = "")

@Serializable data class SeriesRef(val id: String = "", val name: String = "", val sequence: String? = null)

@Serializable data class Metadata(
    val title: String? = null,
    val subtitle: String? = null,
    val authorName: String? = null,
    val author: String? = null,
    val authors: List<NamedRef> = emptyList(),
    val narrators: List<String> = emptyList(),
    val narratorName: String? = null,
    val series: List<SeriesRef> = emptyList(),
    val seriesName: String? = null,
    val genres: List<String> = emptyList(),
    val description: String? = null,
    val publishedYear: String? = null,
    val publisher: String? = null,
    val language: String? = null,
    val explicit: Boolean = false,
    val feedUrl: String? = null,
    val imageUrl: String? = null,
)

@Serializable data class FileMetadata(
    val filename: String? = null,
    val ext: String? = null,
    val size: Long? = null,
    val path: String? = null,
)

@Serializable data class AudioTrack(
    val index: Int? = null,
    val startOffset: Double = 0.0,
    val duration: Double = 0.0,
    val title: String? = null,
    val contentUrl: String? = null,
    val mimeType: String? = null,
    val metadata: FileMetadata? = null,
    val ino: String? = null,
)

@Serializable data class Chapter(val id: Int? = null, val start: Double, val end: Double, val title: String = "")

@Serializable data class EbookFile(val ino: String, val ebookFormat: String? = null, val metadata: FileMetadata? = null) {
    val format get() = (ebookFormat ?: metadata?.ext?.removePrefix("."))?.lowercase()
}

@Serializable data class LibraryFile(
    val ino: String,
    val fileType: String? = null,
    val isSupplementary: Boolean? = null,
    val metadata: FileMetadata? = null,
) {
    val format get() = metadata?.ext?.removePrefix(".")?.lowercase()
}

@Serializable data class AudioFile(val ino: String? = null, val duration: Double = 0.0, val metadata: FileMetadata? = null, val mimeType: String? = null)

@Serializable data class Episode(
    val id: String,
    val libraryItemId: String? = null,
    val title: String = "",
    val subtitle: String? = null,
    val description: String? = null,
    val duration: Double = 0.0,
    val publishedAt: Double? = null,
    val season: String? = null,
    val episode: String? = null,
    val episodeType: String? = null,
    val index: Int? = null,
    val audioTrack: AudioTrack? = null,
    val audioFile: AudioFile? = null,
    val chapters: List<Chapter> = emptyList(),
) {
    val playableDuration get() = duration.takeIf { it > 0 } ?: audioTrack?.duration?.takeIf { it > 0 } ?: audioFile?.duration ?: 0.0
}

@Serializable data class Media(
    val metadata: Metadata = Metadata(),
    val duration: Double? = null,
    val numTracks: Int? = null,
    val numChapters: Int? = null,
    val numEpisodes: Int? = null,
    val chapters: List<Chapter> = emptyList(),
    val tracks: List<AudioTrack> = emptyList(),
    val ebookFile: EbookFile? = null,
    val ebookFormat: String? = null,
    val episodes: List<Episode> = emptyList(),
    val coverPath: String? = null,
    val size: Long? = null,
)

@Serializable data class LibraryItem(
    val id: String,
    val libraryId: String? = null,
    val mediaType: String = "book",
    val media: Media = Media(),
    val libraryFiles: List<LibraryFile> = emptyList(),
    val recentEpisode: Episode? = null,
    val numEpisodesIncomplete: Int? = null,
    val addedAt: Double? = null,
    val updatedAt: Double? = null,
    val isMissing: Boolean = false,
    val isInvalid: Boolean = false,
) {
    val isPodcast get() = mediaType == "podcast"
    val title get() = media.metadata.title?.takeIf { it.isNotBlank() } ?: "Untitled"
    val author get() = media.metadata.authorName?.takeIf { it.isNotBlank() }
        ?: media.metadata.authors.joinToString(", ") { it.name }.takeIf { it.isNotBlank() }
        ?: media.metadata.author?.takeIf { it.isNotBlank() }
        ?: ""
    val narrators get() = media.metadata.narrators.ifEmpty { media.metadata.narratorName?.split(", ")?.filter { it.isNotBlank() } ?: emptyList() }
    val duration get() = media.duration ?: media.tracks.sumOf { it.duration }
    val hasAudio get() = isPodcast || (media.numTracks ?: media.tracks.size) > 0 || (media.duration ?: 0.0) > 0
    val primaryEbook get() = media.ebookFile
    val supplementaryEbooks get() = libraryFiles.filter { it.fileType == "ebook" && it.isSupplementary == true }
}

@Serializable data class ItemsPage(val results: List<LibraryItem>, val total: Int = 0, val limit: Int = 0, val page: Int = 0)

@Serializable data class PersonalizedShelf(
    val id: String,
    val label: String = "",
    val labelStringKey: String? = null,
    val type: String = "book",
    val entities: List<JsonElement> = emptyList(),
) {
    fun items(): List<LibraryItem> = if (type == "book" || type == "podcast" || type == "episode") {
        entities.mapNotNull { runCatching { AbsJson.decodeFromJsonElement(LibraryItem.serializer(), it) }.getOrNull() }
    } else emptyList()
}

@Serializable data class SearchItem(val libraryItem: LibraryItem)
@Serializable data class SeriesResult(val series: NamedRef, val books: List<LibraryItem> = emptyList())
@Serializable data class NarratorResult(val name: String, val numBooks: Int = 0)
@Serializable data class TagResult(val name: String, val numItems: Int = 0)
@Serializable data class AuthorResult(val id: String, val name: String = "", val numBooks: Int? = null)

@Serializable data class SearchResponse(
    val book: List<SearchItem> = emptyList(),
    val podcast: List<SearchItem> = emptyList(),
    val episodes: List<SearchItem> = emptyList(),
    val authors: List<AuthorResult> = emptyList(),
    val series: List<SeriesResult> = emptyList(),
    val narrators: List<NarratorResult> = emptyList(),
    val tags: List<TagResult> = emptyList(),
    val genres: List<TagResult> = emptyList(),
) {
    val isEmpty get() = book.isEmpty() && podcast.isEmpty() && episodes.isEmpty() && authors.isEmpty() && series.isEmpty() && narrators.isEmpty() && tags.isEmpty()
}

@Serializable data class FilterData(
    val genres: List<String> = emptyList(),
    val authors: List<NamedRef> = emptyList(),
    val series: List<NamedRef> = emptyList(),
    val tags: List<String> = emptyList(),
    val narrators: List<String> = emptyList(),
    val languages: List<String> = emptyList(),
    val publishers: List<String> = emptyList(),
)

@Serializable data class AuthorDetail(
    val id: String,
    val name: String = "",
    val description: String? = null,
    val libraryItems: List<LibraryItem> = emptyList(),
    val series: List<AuthorSeries> = emptyList(),
)
@Serializable data class AuthorSeries(val id: String, val name: String = "", val items: List<LibraryItem> = emptyList())

@Serializable data class PlaybackSession(
    val id: String,
    val userId: String? = null,
    val libraryItemId: String,
    val episodeId: String? = null,
    val mediaType: String? = null,
    val currentTime: Double = 0.0,
    val duration: Double = 0.0,
    val playMethod: Int = 0,
    val displayTitle: String? = null,
    val displayAuthor: String? = null,
    val audioTracks: List<AudioTrack> = emptyList(),
    val chapters: List<Chapter> = emptyList(),
)

@Serializable data class Collection(
    val id: String,
    val libraryId: String = "",
    val userId: String? = null,
    val name: String = "",
    val description: String? = null,
    val books: List<LibraryItem> = emptyList(),
)

@Serializable data class PlaylistItem(
    val libraryItemId: String,
    val episodeId: String? = null,
    val libraryItem: LibraryItem? = null,
    val episode: Episode? = null,
)

@Serializable data class Playlist(
    val id: String,
    val libraryId: String = "",
    val userId: String = "",
    val name: String = "",
    val description: String? = null,
    val items: List<PlaylistItem> = emptyList(),
)

@Serializable data class GroupPage<T>(val results: List<T> = emptyList(), val total: Int = 0)

@Serializable data class StatsSession(
    val id: String,
    val libraryItemId: String? = null,
    val episodeId: String? = null,
    val displayTitle: String? = null,
    val displayAuthor: String? = null,
    val mediaMetadata: Metadata? = null,
    @Serializable(with = LenientDoubleSerializer::class) val timeListening: Double = 0.0,
    val updatedAt: Double? = null,
) {
    val title get() = displayTitle ?: mediaMetadata?.title ?: "Untitled"
    val author get() = displayAuthor ?: mediaMetadata?.authorName ?: mediaMetadata?.author ?: ""
}

@Serializable data class ListeningStats(
    @Serializable(with = LenientDoubleSerializer::class) val totalTime: Double = 0.0,
    val days: Map<String, Double> = emptyMap(),
    val dayOfWeek: Map<String, Double> = emptyMap(),
    val recentSessions: List<StatsSession> = emptyList(),
)

@Serializable data class PodcastDiscovery(
    val id: Long = 0,
    val title: String = "",
    val artistName: String? = null,
    val feedUrl: String? = null,
    val cover: String? = null,
    val genres: List<String> = emptyList(),
    val description: String? = null,
)
