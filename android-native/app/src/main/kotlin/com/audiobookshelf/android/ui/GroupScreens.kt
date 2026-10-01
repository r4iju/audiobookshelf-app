package com.audiobookshelf.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.audiobookshelf.android.data.CatalogModel
import com.audiobookshelf.android.data.SessionState
import com.audiobookshelf.android.graph
import com.audiobookshelf.android.playback.PlaySource
import com.audiobookshelf.android.playback.itemKey
import com.audiobookshelf.core.ApiClient
import com.audiobookshelf.core.ApiError
import com.audiobookshelf.core.Collection
import com.audiobookshelf.core.Episode
import com.audiobookshelf.core.LibraryItem
import com.audiobookshelf.core.Playlist
import com.audiobookshelf.core.User
import kotlinx.coroutines.launch

const val COLLECTIONS = "collections"
const val PLAYLISTS = "playlists"

data class GroupMember(val itemId: String, val episodeId: String?, val item: LibraryItem?, val episode: Episode?) {
    val key get() = if (episodeId == null) itemId else "$itemId:$episodeId"
    val title get() = episode?.title ?: item?.title ?: "Unavailable title"
}

/** Collections and playlists behave alike in the UI; only the server calls and permissions differ. */
data class Group(val kind: String, val id: String, val libraryId: String, val ownerId: String?, val name: String, val description: String, val members: List<GroupMember>) {
    fun canEdit(user: User?) = user != null && if (kind == COLLECTIONS) user.permissions.update else ownerId == user.id
    fun canDelete(user: User?) = user != null && if (kind == COLLECTIONS) user.permissions.delete else ownerId == user.id

    companion object {
        fun of(value: Collection) = Group(COLLECTIONS, value.id, value.libraryId, value.userId, value.name, value.description.orEmpty(),
            value.books.map { GroupMember(it.id, null, it, null) })
        fun of(value: Playlist) = Group(PLAYLISTS, value.id, value.libraryId, value.userId, value.name, value.description.orEmpty(),
            value.items.map { GroupMember(it.libraryItemId, it.episodeId, it.libraryItem, it.episode) })
    }
}

private fun label(kind: String, plural: Boolean = false) = if (kind == COLLECTIONS) (if (plural) "Collections" else "Collection") else (if (plural) "Playlists" else "Playlist")

fun canCreateGroup(kind: String, catalog: CatalogModel) =
    if (kind == COLLECTIONS) catalog.user?.permissions?.update == true && catalog.library?.isPodcast == false else catalog.user != null

private suspend fun ApiClient.group(kind: String, id: String) = if (kind == COLLECTIONS) Group.of(collection(id)) else Group.of(playlist(id))

@Composable
fun GroupsScreen(kind: String, active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onOpen: (String) -> Unit) {
    val graph = LocalContext.current.graph
    val libraryId = catalog.library?.id
    var groups by remember(kind, libraryId) { mutableStateOf<List<Group>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    LaunchedEffect(kind, libraryId, attempt) {
        if (libraryId == null) return@LaunchedEffect
        error = null
        try {
            groups = if (kind == COLLECTIONS) active.client.collections(libraryId).map(Group::of) else active.client.playlists(libraryId).map(Group::of)
        } catch (failure: Exception) { error = failure.message ?: "Could not load ${label(kind, true).lowercase()}."; graph.accounts.handle(failure) }
    }
    val list = groups
    Box(Modifier.fillMaxSize().padding(padding).testTag("groups-$kind")) {
        when {
            error != null && list == null -> MessageState("${label(kind, true)} unavailable", error, tag = "groups-error", action = "Retry", actionTag = "groups-retry") { attempt++ }
            list == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            list.isEmpty() -> MessageState("No ${label(kind, true).lowercase()} yet", if (canCreateGroup(kind, catalog)) "Create one to keep titles together in your own order." else null, tag = "groups-empty")
            else -> LazyColumn(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
                items(list, key = { it.id }) { group ->
                    Row(
                        Modifier.fillMaxWidth().clickable(role = Role.Button) { onOpen(group.id) }.padding(vertical = 10.dp).testTag("group-${group.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        val first = group.members.firstOrNull()
                        Cover(first?.let { active.client.coverUrl(it.itemId).toString() }, group.name, Modifier.size(56.dp), podcast = first?.episodeId != null)
                        Column(Modifier.weight(1f)) {
                            Text(group.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${group.members.size} ${if (group.members.size == 1) "title" else "titles"}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
fun GroupScreen(kind: String, id: String, active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onMember: (GroupMember) -> Unit, onEdit: () -> Unit, onDeleted: () -> Unit) {
    val graph = LocalContext.current.graph
    val scope = rememberCoroutineScope()
    val player by graph.playback.state.collectAsState()
    var group by remember(id) { mutableStateOf<Group?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }
    var confirmDelete by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(id, attempt) {
        error = null
        try { group = active.client.group(kind, id) } catch (failure: Exception) {
            error = if (failure is ApiError.Http && failure.status == 404) "This ${label(kind).lowercase()} was deleted." else failure.message ?: "Could not load."
            graph.accounts.handle(failure)
        }
    }
    val loaded = group
    if (loaded == null) {
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            if (error != null) MessageState("${label(kind)} unavailable", error, tag = "group-error", action = "Retry", actionTag = "group-retry") { attempt++ }
            else CircularProgressIndicator()
        }
        return
    }
    val playingThis = player.queueId == loaded.id && player.now != null
    val user = catalog.user
    LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("group-detail-${loaded.id}"), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(label(kind), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text(loaded.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                if (loaded.description.isNotBlank()) Text(loaded.description, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Button(
                        onClick = {
                            if (playingThis) { graph.playback.toggle(); return@Button }
                            busy = true; actionError = null
                            scope.launch {
                                try {
                                    val fresh = catalog.freshUser()
                                    val finished = fresh.mediaProgress.filter { it.isFinished }.mapTo(HashSet()) { itemKey(it.libraryItemId, it.episodeId) }
                                    val playable = loaded.members.filter { it.item != null }
                                    val pending = playable.filterNot { itemKey(it.itemId, it.episodeId) in finished }.ifEmpty { playable }
                                    val sources = pending.map { member ->
                                        val progress = fresh.mediaProgress.firstOrNull { it.libraryItemId == member.itemId && it.episodeId == member.episodeId }
                                        PlaySource.Stream(active.client, member.itemId, member.episodeId, active.client.coverUrl(member.itemId).toString(), progress?.lastUpdate)
                                    }
                                    if (sources.isEmpty()) actionError = "Nothing in this ${label(kind).lowercase()} can play."
                                    else graph.playback.playQueue(loaded.id, sources)
                                } catch (failure: Exception) {
                                    actionError = failure.message ?: "Could not start playback."; graph.accounts.handle(failure)
                                } finally { busy = false }
                            }
                        },
                        enabled = !busy && loaded.members.isNotEmpty(),
                        modifier = Modifier.testTag("group-play"),
                    ) {
                        val pause = playingThis && player.playing
                        Icon(if (pause) Icons.Filled.Pause else Icons.Filled.PlayArrow, null)
                        Text(if (pause) "Pause" else if (playingThis) "Resume" else "Play ${label(kind).lowercase()}", Modifier.padding(start = 6.dp))
                    }
                    if (loaded.canEdit(user)) IconButton(onClick = onEdit, modifier = Modifier.testTag("edit-group")) { Icon(Icons.Outlined.Edit, "Edit ${label(kind).lowercase()}") }
                    if (loaded.canDelete(user)) IconButton(onClick = { confirmDelete = true }, modifier = Modifier.testTag("delete-group")) { Icon(Icons.Outlined.Delete, "Delete ${label(kind).lowercase()}") }
                }
                (actionError ?: player.openError?.takeIf { failure -> loaded.members.any { itemKey(it.itemId, it.episodeId) == failure.first } }?.second)?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("group-action-error"))
                }
            }
        }
        if (loaded.members.isEmpty()) item { Text("No titles yet", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(loaded.members, key = { it.key }) { member ->
            val progress = catalog.progressFor(member.itemId, member.episodeId)
            Row(
                Modifier.fillMaxWidth().clickable(enabled = member.item != null, role = Role.Button) { onMember(member) }.padding(vertical = 6.dp).testTag("group-member-${member.itemId}:${member.episodeId.orEmpty()}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Cover(active.client.coverUrl(member.itemId).toString(), member.title, Modifier.size(52.dp), podcast = member.episodeId != null)
                Column(Modifier.weight(1f)) {
                    Text(member.title, style = MaterialTheme.typography.bodyLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    val subtitle = if (member.episode != null) member.item?.title else member.item?.author
                    subtitle?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
                    if (progress?.isFinished == true) Text("Finished", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    else if (progress != null && progress.progress > 0) ProgressLine(progress.progress, Modifier.padding(top = 4.dp))
                }
            }
        }
    }
    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text("Delete ${label(kind).lowercase()}?") },
        text = { Text("“${loaded.name}” is removed from your server. The titles in it are kept.") },
        confirmButton = {
            TextButton(onClick = {
                confirmDelete = false; actionError = null
                scope.launch {
                    try { active.client.deleteGroup(kind, loaded.id); onDeleted() }
                    catch (failure: Exception) { actionError = "Not deleted: ${failure.message ?: "try again"}"; graph.accounts.handle(failure) }
                }
            }, modifier = Modifier.testTag("confirm-delete-group")) { Text("Delete", color = MaterialTheme.colorScheme.error) }
        },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
    )
}

/**
 * Creates or edits a group. Membership removals, additions and the final rename/reorder are separate
 * server calls, so each step that succeeds is folded into [saved] and a retry resumes from there.
 */
@Composable
fun GroupEditorScreen(kind: String, id: String?, active: SessionState.Active, catalog: CatalogModel, padding: PaddingValues, onSaved: (String) -> Unit) {
    val graph = LocalContext.current.graph
    val scope = rememberCoroutineScope()
    val libraryId = catalog.library?.id
    var saved by remember(id) { mutableStateOf<Group?>(null) }
    var name by remember(id) { mutableStateOf("") }
    var description by remember(id) { mutableStateOf("") }
    var members by remember(id) { mutableStateOf<List<GroupMember>>(emptyList()) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var candidates by remember { mutableStateOf<List<LibraryItem>>(emptyList()) }
    LaunchedEffect(id) {
        if (id == null) return@LaunchedEffect
        try {
            val group = active.client.group(kind, id)
            saved = group; name = group.name; description = group.description; members = group.members
        } catch (failure: Exception) { loadError = failure.message ?: "Could not load."; graph.accounts.handle(failure) }
    }
    val choosable = catalog.library?.isPodcast == false
    LaunchedEffect(libraryId, choosable) {
        if (libraryId == null || !choosable) return@LaunchedEffect
        runCatching { active.client.items(libraryId, 0, limit = 100).results }.onSuccess { candidates = it }.onFailure { graph.accounts.handle(it) }
    }
    if (id != null && saved == null) {
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            loadError?.let { MessageState("${label(kind)} unavailable", it, tag = "group-error") } ?: CircularProgressIndicator()
        }
        return
    }

    fun save() {
        if (libraryId == null) return
        saving = true; error = null
        scope.launch {
            try {
                val target = members
                var current = saved
                if (current == null) {
                    val created = if (kind == COLLECTIONS) Group.of(active.client.createCollection(libraryId, name.trim(), description.trim(), target.map { it.itemId }))
                    else Group.of(active.client.createPlaylist(libraryId, name.trim(), description.trim(), target.map { it.itemId to it.episodeId }))
                    saved = created
                    onSaved(created.id)
                    return@launch
                }
                val wanted = target.map { it.key }.toSet()
                val removed = current.members.filter { it.key !in wanted }
                if (removed.isNotEmpty()) {
                    if (kind == COLLECTIONS) active.client.collectionMembership(current.id, false, removed.map { it.itemId })
                    else active.client.playlistMembership(current.id, false, removed.map { it.itemId to it.episodeId })
                    current = current.copy(members = current.members - removed.toSet()); saved = current
                }
                val existing = current.members.map { it.key }.toSet()
                val added = target.filter { it.key !in existing }
                if (added.isNotEmpty()) {
                    if (kind == COLLECTIONS) active.client.collectionMembership(current.id, true, added.map { it.itemId })
                    else active.client.playlistMembership(current.id, true, added.map { it.itemId to it.episodeId })
                    current = current.copy(members = current.members + added); saved = current
                }
                if (current.name != name.trim() || current.description != description.trim() || current.members.map { it.key } != target.map { it.key }) {
                    if (kind == COLLECTIONS) active.client.updateCollection(current.id, name.trim(), description.trim(), target.map { it.itemId })
                    else active.client.updatePlaylist(current.id, name.trim(), description.trim(), target.map { it.itemId to it.episodeId })
                    current = current.copy(name = name.trim(), description = description.trim(), members = target); saved = current
                }
                onSaved(current.id)
            } catch (failure: Exception) {
                error = when {
                    failure is ApiError.Http && failure.status == 403 -> "Your server account is not allowed to change this ${label(kind).lowercase()}."
                    failure is ApiError.Http && failure.status == 404 -> "This ${label(kind).lowercase()} no longer exists."
                    else -> "Not saved: ${failure.message ?: "try again"}"
                }
                graph.accounts.handle(failure)
            } finally { saving = false }
        }
    }

    val chosen = members.map { it.key }.toSet()
    LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth().testTag("group-name"))
                OutlinedTextField(description, { description = it }, label = { Text("Description") }, modifier = Modifier.fillMaxWidth().testTag("group-description"))
                Button(onClick = ::save, enabled = !saving && name.isNotBlank() && members.isNotEmpty(), modifier = Modifier.fillMaxWidth().testTag("save-group")) {
                    Text(if (saving) "Saving…" else if (id == null) "Create ${label(kind).lowercase()}" else "Save changes")
                }
                if (members.isEmpty()) Text("Choose at least one title.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.testTag("group-error")) }
                if (members.isNotEmpty()) Text("Order", style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
            }
        }
        items(members, key = { "member-${it.key}" }) { member ->
            val index = members.indexOf(member)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("${index + 1}.", Modifier.padding(end = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(member.title, Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
                IconButton(onClick = { members = members.toMutableList().apply { add(index - 1, removeAt(index)) } }, enabled = index > 0 && !saving, modifier = Modifier.testTag("move-up-${member.key}")) {
                    Icon(Icons.Outlined.ArrowUpward, "Move ${member.title} up")
                }
                IconButton(onClick = { members = members - member }, enabled = !saving, modifier = Modifier.testTag("remove-${member.key}")) {
                    Icon(Icons.Outlined.Close, "Remove ${member.title}")
                }
            }
        }
        if (choosable) {
            item { Text("Add titles", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 12.dp).semantics { heading() }) }
            items(candidates, key = { "choose-${it.id}" }) { item ->
                val selected = item.id in chosen
                Row(
                    Modifier.fillMaxWidth().clickable(enabled = !saving, role = Role.Checkbox) {
                        members = if (selected) members.filterNot { it.key == item.id } else members + GroupMember(item.id, null, item, null)
                    }.padding(vertical = 4.dp).testTag("choose-${item.id}"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(checked = selected, onCheckedChange = null)
                    Text(item.title, Modifier.padding(start = 8.dp), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        } else if (id == null) item {
            Text("Add episodes from a podcast's episode page.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Adds one title or episode to an existing playlist or collection of the current library. */
@Composable
fun AddToGroupButton(itemId: String, episodeId: String?, active: SessionState.Active, catalog: CatalogModel) {
    val graph = LocalContext.current.graph
    val scope = rememberCoroutineScope()
    var open by remember { mutableStateOf(false) }
    var groups by remember { mutableStateOf<List<Group>?>(null) }
    var message by remember { mutableStateOf<String?>(null) }
    val libraryId = catalog.library?.id ?: return
    val kinds = listOfNotNull(PLAYLISTS, COLLECTIONS.takeIf { episodeId == null && catalog.user?.permissions?.update == true })
    OutlinedButton(onClick = { open = true; message = null }, modifier = Modifier.fillMaxWidth().testTag("add-to-group")) {
        Icon(Icons.Outlined.Add, null); Text(if (episodeId == null) "Add to playlist or collection" else "Add to playlist", Modifier.padding(start = 6.dp))
    }
    message?.let { Text(it, style = MaterialTheme.typography.bodySmall, modifier = Modifier.testTag("add-to-group-result")) }
    if (open) {
        LaunchedEffect(Unit) {
            try {
                groups = kinds.flatMap { kind ->
                    if (kind == COLLECTIONS) active.client.collections(libraryId).map(Group::of) else active.client.playlists(libraryId).map(Group::of)
                }.filter { it.canEdit(catalog.user) }
            } catch (failure: Exception) { message = failure.message; open = false; graph.accounts.handle(failure) }
        }
        AlertDialog(
            onDismissRequest = { open = false },
            title = { Text("Add to") },
            text = {
                val list = groups
                when {
                    list == null -> CircularProgressIndicator()
                    list.isEmpty() -> Text("Nothing you can add to here yet.")
                    else -> LazyColumn {
                        items(list, key = { it.kind + it.id }) { group ->
                            val present = group.members.any { it.itemId == itemId && it.episodeId == episodeId }
                            Row(Modifier.fillMaxWidth().clickable(enabled = !present) {
                                open = false
                                scope.launch {
                                    message = try {
                                        if (group.kind == COLLECTIONS) active.client.collectionMembership(group.id, true, listOf(itemId))
                                        else active.client.playlistMembership(group.id, true, listOf(itemId to episodeId))
                                        "Added to ${group.name}"
                                    } catch (failure: Exception) { graph.accounts.handle(failure); "Not added: ${failure.message ?: "try again"}" }
                                }
                            }.padding(vertical = 10.dp).testTag("add-to-${group.id}")) {
                                Column {
                                    Text(group.name)
                                    Text(if (present) "Already included" else label(group.kind), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { open = false }) { Text("Close") } },
        )
    }
}
