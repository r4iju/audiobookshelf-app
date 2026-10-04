import { editLibrary, editLibrarySchema, managedLibraries, removeLibrary } from "./catalog";
import {
  devicesFor,
  devicesInput,
  managedDevices,
  saveDevices,
  saveSmtpSettings,
  sendEbook,
  sendEbookInput,
  smtpInput,
  smtpSettings,
} from "./delivery";
import { allFeeds, closeFeed, openFeed, openFeedSchema } from "./feeds";
import { openIdInput, openIdSettings, saveOpenIdSettings } from "./openid";
import {
  allSchedules,
  checkPodcast,
  scheduleFor,
  startPodcastSchedules,
  updateSchedule,
} from "./podcast-schedules";
import {
  podcastSettings,
  podcastSettingsSchema,
  savePodcastSettings,
  searchPodcasts,
} from "./podcast-settings";
import {
  clearQueue,
  createPodcast,
  downloadsFor,
  enqueue,
  episodesInput,
  feedInput,
  newPodcastSchema,
  readFeed,
  recentEpisodes,
  removeEpisode,
  startPodcasts,
} from "./podcasts";
import { originAllowed, saveServerSettings, serverSettings, serverSettingsSchema } from "./server-settings";
import "server-only";
import "./realtime";
import { z } from "zod";
import {
  accountResponse,
  authenticate,
  createAccount,
  createAccountSchema,
  createOwner,
  credentialsSchema,
  DomainError,
  editAccount,
  editAccountSchema,
  endSession,
  findAccount,
  listAccounts,
  passwordLogin,
  refreshSession,
  removeAccount,
  requireAdministrator,
  revokeAccount,
  setupSchema,
} from "./accounts";
import { createBackup, listBackups, restoreBackup } from "./backups";
import {
  createLibrary,
  createLibrarySchema,
  filterData,
  findLibrary,
  itemFor,
  itemsFor,
  librariesFor,
  pagedItems,
  scanHistory,
  scanLibrary,
} from "./catalog";
import { database, initialized, setupKey } from "./data";
import { deliveryImportInput, importDelivery, inspectDelivery } from "./delivery-migration";
import { authorFor, authorGroups, pagedSeries, personalized, seriesFor } from "./discovery";
import { downloadItem, serveEbook } from "./documents";
import {
  cover,
  editMetadata,
  metadataEditInput,
  metadataSearch,
  providerSettings,
  providerSettingsInput,
  removeCatalogItem,
  restoreCatalogItem,
  saveCover,
  saveProvider,
  upload,
} from "./item-management";
import { importLists, inspectLists, listImportSchema } from "./list-migration";
import {
  changeList,
  createList,
  createListSchema,
  deleteList,
  editListSchema,
  listBatchSchema,
  listFor,
  listsFor,
} from "./lists";
import { commitMedia, inspectMedia, mediaCommitSchema, mediaInspectSchema } from "./media-migration";
import {
  commitImport,
  commitImportSchema,
  inspectImport,
  inspectImportSchema,
  migrationHistory,
} from "./migration";
import { closePlayback, openPlayback, playSchema, serveFile, serveTrack } from "./playback";
import {
  listeningStats,
  localReportsSchema,
  patchProgress,
  progressFor,
  progressPatchSchema,
  removeProgress,
  resetProgress,
  resetProgressSchema,
  syncLocal,
} from "./progress";
import { searchLibrary } from "./search";
import { cancelTranscode, serveHls, startTranscode } from "./transcode";

const MAX_BODY = 16_384;
export function json(value: unknown, status = 200) {
  return Response.json(value, { status, headers: { "cache-control": "no-store" } });
}
export async function boundary(work: () => Promise<Response> | Response) {
  try {
    return await work();
  } catch (error) {
    if (error instanceof DomainError) return new Response(error.message, { status: error.status });
    if (error instanceof z.ZodError || error instanceof SyntaxError)
      return new Response("Invalid request", { status: 400 });
    console.error("Leafwake request failed", error instanceof Error ? error.name : "UnknownError");
    return new Response("The server could not complete this request", { status: 500 });
  }
}
function sameOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin) return;
  if (!originAllowed(origin, request.headers.get("host") ?? ""))
    throw new DomainError(403, "This browser origin is not allowed");
}
async function body(request: Request, maximum = MAX_BODY): Promise<unknown> {
  sameOrigin(request);
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json"))
    throw new DomainError(415, "JSON request required");
  if (Number(request.headers.get("content-length")) > maximum)
    throw new DomainError(413, "Request too large");
  const reader = request.body?.getReader();
  if (!reader) throw new DomainError(400, "JSON request required");
  const chunks: Uint8Array[] = [];
  let size = 0;
  const deadline = Date.now() + 20000;
  try {
    for (;;) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const { done, value } = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new DomainError(408, "JSON request timed out")),
            Math.max(1, deadline - Date.now()),
          );
        }),
      ]).finally(() => {
        if (timer) clearTimeout(timer);
      });
      if (done) break;
      size += value.length;
      if (size > maximum) throw new DomainError(413, "Request too large");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
export function serverStatus() {
  const ready = initialized();
  if (!ready) setupKey();
  return json({
    app: "Leafwake",
    serverVersion: "1.0.0-dev",
    isInit: ready,
    language: serverSettings().language,
    serverName: serverSettings().serverName,
    authMethods: openIdSettings().enabled ? ["local", "openid"] : ["local"],
    authFormData: {
      authLoginCustomMessage: serverSettings().loginMessage,
      authOpenIDButtonText: openIdSettings().buttonText,
      authOpenIDAutoLaunch: openIdSettings().enabled && openIdSettings().autoLaunch,
    },
  });
}
export function health() {
  startTranscode();
  startPodcasts();
  startPodcastSchedules();
  database().prepare("SELECT 1").get();
  return json({ status: "ready", app: "Leafwake" });
}
export async function login(request: Request) {
  return boundary(async () => json(await passwordLogin(credentialsSchema.parse(await body(request)))));
}
export function refresh(request: Request) {
  return boundary(() => {
    sameOrigin(request);
    return json(refreshSession(request.headers.get("x-refresh-token")));
  });
}
export function logout(request: Request) {
  return boundary(() => {
    sameOrigin(request);
    endSession(bearer(request), request.headers.get("x-refresh-token"));
    return json({ success: true });
  });
}
export function bearer(request: Request) {
  const value = request.headers.get("authorization");
  return value?.startsWith("Bearer ") ? value.slice(7) : null;
}
export async function api(request: Request) {
  return boundary(async () => {
    const incomingPath = new URL(request.url).pathname;
    const prefix = globalThis.leafwakeBasePath ?? "";
    const path =
      prefix && incomingPath.startsWith(`${prefix}/`) ? incomingPath.slice(prefix.length) : incomingPath;
    if (path === "/api/setup" && request.method === "POST") {
      if (initialized()) throw new DomainError(409, "This server is already initialized");
      const input = await body(request);
      // Missing bootstrap authority is a denied setup attempt, not malformed owner credentials.
      if (!input || typeof input !== "object" || !("setupKey" in input))
        throw new DomainError(403, "The setup key is required");
      await createOwner(setupSchema.parse(input));
      return json({ initialized: true }, 201);
    }
    if (path === "/api/setup/import/inspect" && request.method === "POST")
      return json(inspectImport(inspectImportSchema.parse(await body(request))));
    if (path === "/api/setup/import" && request.method === "POST")
      return json(commitImport(commitImportSchema.parse(await body(request))));
    const fileRoute = path.match(/^\/api\/items\/([^/]+)\/file\/([^/]+)(?:\/(download))?$/);
    const ebookRoute = path.match(/^\/api\/items\/([^/]+)\/ebook(?:\/([^/]+))?$/);
    const downloadRoute = path.match(/^\/api\/items\/([^/]+)\/download$/);
    const coverRoute = path.match(/^\/api\/items\/([^/]+)\/cover$/);
    const token =
      bearer(request) ??
      (fileRoute || ebookRoute || downloadRoute || (coverRoute && ["GET", "HEAD"].includes(request.method))
        ? new URL(request.url).searchParams.get("token")
        : null);
    const user = authenticate(token);
    if ((request.method === "GET" || request.method === "HEAD") && ebookRoute)
      return serveEbook(request, () => authenticate(token), z.string().parse(ebookRoute[1]), ebookRoute[2]);
    if ((request.method === "GET" || request.method === "HEAD") && downloadRoute)
      return downloadItem(request, () => authenticate(token), z.string().parse(downloadRoute[1]));
    if (path === "/api/emails/settings") {
      requireAdministrator(user);
      if (request.method === "GET") return json(smtpSettings(user));
      if (request.method === "PATCH")
        return json(saveSmtpSettings(user, smtpInput.parse(await body(request))));
    }
    if (path === "/api/emails/ereader-devices") {
      if (request.method === "GET") return json(managedDevices(user));
      if (request.method === "POST") return json(saveDevices(user, devicesInput.parse(await body(request))));
    }
    if (path === "/api/emails/send-ebook-to-device" && request.method === "POST")
      return json(await sendEbook(() => authenticate(token), sendEbookInput.parse(await body(request))));
    if (path === "/api/feeds" && request.method === "GET") return json(allFeeds(user));
    const feedOpen = path.match(/^\/api\/feeds\/item\/([^/]+)\/open$/),
      feedClose = path.match(/^\/api\/feeds\/([^/]+)\/close$/);
    if (feedOpen && request.method === "POST")
      return json(openFeed(user, z.string().parse(feedOpen[1]), openFeedSchema.parse(await body(request))));
    if (feedClose && request.method === "POST") {
      sameOrigin(request);
      return json(closeFeed(user, z.string().parse(feedClose[1])));
    }
    if (path === "/api/admin/openid/settings") {
      requireAdministrator(user);
      if (request.method === "GET") return json(openIdSettings());
      if (request.method === "PATCH")
        return json(
          await saveOpenIdSettings(user, openIdInput.parse(await body(request)), () => authenticate(token)),
        );
    }
    if (path === "/api/settings") {
      requireAdministrator(user);
      if (request.method === "GET") return json(serverSettings());
      if (request.method === "PATCH") {
        sameOrigin(request);
        return json(saveServerSettings(user, serverSettingsSchema.parse(await body(request))));
      }
    }
    if (path === "/api/admin/libraries" && request.method === "GET")
      return json({ libraries: managedLibraries(user) });
    if (path === "/api/admin/podcasts/subscriptions" && request.method === "GET") {
      requireAdministrator(user);
      return json(allSchedules(user));
    }
    if (path === "/api/admin/podcasts/settings") {
      requireAdministrator(user);
      if (request.method === "GET") return json(podcastSettings());
      if (request.method === "PATCH") {
        sameOrigin(request);
        return json(savePodcastSettings(user, podcastSettingsSchema.parse(await body(request))));
      }
    }
    if (path === "/api/search/podcast" && request.method === "GET")
      return json(await searchPodcasts(user, new URL(request.url).searchParams.get("term") ?? ""));
    if (path === "/api/podcasts/feed" && request.method === "POST") {
      requireAdministrator(user);
      return json(await readFeed(feedInput.parse(await body(request)).rssFeed));
    }
    if (path === "/api/podcasts" && request.method === "POST")
      return json(
        await createPodcast(user, newPodcastSchema.parse(await body(request)), () => authenticate(token)),
        201,
      );
    const podcastRoute = path.match(
      /^\/api\/podcasts\/([^/]+)\/(download-episodes|clear-queue|episode|downloads|check|schedule)(?:\/([^/]+))?$/,
    );
    if (podcastRoute) {
      const id = z.string().parse(podcastRoute[1]);
      if (podcastRoute[2] === "check" && request.method === "POST") return json(await checkPodcast(user, id));
      if (podcastRoute[2] === "schedule" && request.method === "PATCH") {
        sameOrigin(request);
        return json(
          updateSchedule(
            user,
            id,
            z.object({ autoDownloadEpisodes: z.boolean() }).parse(await body(request)).autoDownloadEpisodes,
          ),
        );
      }
      if (podcastRoute[2] === "schedule" && request.method === "GET") return json(scheduleFor(user, id));
      if (podcastRoute[2] === "downloads" && request.method === "GET") return json(downloadsFor(user, id));
      if (podcastRoute[2] === "download-episodes" && request.method === "POST")
        return json(enqueue(authenticate(token), id, episodesInput.parse(await body(request))));
      if (podcastRoute[2] === "clear-queue" && ["GET", "POST"].includes(request.method))
        return json(await clearQueue(user, id));
      if (podcastRoute[2] === "episode" && request.method === "DELETE")
        return json(await removeEpisode(user, id, z.string().parse(podcastRoute[3])));
    }
    const recentRoute = path.match(/^\/api\/libraries\/([^/]+)\/recent-episodes$/);
    if (recentRoute && request.method === "GET")
      return json(recentEpisodes(user, z.string().parse(recentRoute[1]), new URL(request.url).searchParams));
    if (path === "/api/admin/migrations/media/inspect" && request.method === "POST")
      return json(
        await inspectMedia(mediaInspectSchema.parse(await body(request)), () => authenticate(token)),
      );
    if (path === "/api/admin/migrations/media" && request.method === "POST")
      return json(await commitMedia(mediaCommitSchema.parse(await body(request)), () => authenticate(token)));
    if (path === "/api/admin/backups") {
      if (request.method === "GET") return json(listBackups(user));
      if (request.method === "POST") {
        sameOrigin(request);
        return json(await createBackup(user));
      }
    }
    const restoreRoute = path.match(/^\/api\/admin\/backups\/([^/]+)\/restore$/);
    if (restoreRoute && request.method === "POST") {
      sameOrigin(request);
      return json(restoreBackup(user, z.string().parse(restoreRoute[1])));
    }
    if (path === "/api/admin/migrations" && request.method === "GET") {
      requireAdministrator(user);
      return json(migrationHistory());
    }
    if (path === "/api/session/local-all" && request.method === "POST") {
      const input = localReportsSchema.parse(await body(request, 262144));
      return json(syncLocal(authenticate(token), input));
    }
    if (path === "/api/me/listening-stats" && request.method === "GET") return json(listeningStats(user));
    const resetRoute = path.match(/^\/api\/me\/progress\/([^/]+)(?:\/([^/]+))?\/reset$/);
    if (resetRoute && request.method === "POST") {
      sameOrigin(request);
      const input = resetProgressSchema.parse(await body(request));
      return json(
        resetProgress(
          authenticate(token),
          z.string().parse(resetRoute[1]),
          resetRoute[2] ?? "",
          input.resetId,
        ),
      );
    }
    const progressRoute = path.match(/^\/api\/me\/progress\/([^/]+)(?:\/([^/]+))?$/);
    if (progressRoute) {
      const id = z.string().parse(progressRoute[1]);
      const episode = progressRoute[2] ?? "";
      if (request.method === "GET") {
        const progress = progressFor(user, id, episode);
        if (!progress) throw new DomainError(404, "Not found");
        return json(progress);
      }
      if (request.method === "PATCH") {
        const input = progressPatchSchema.parse(await body(request));
        return json(patchProgress(authenticate(token), id, episode, input));
      }
      if (request.method === "DELETE" && !episode) {
        sameOrigin(request);
        removeProgress(user, id);
        return json({ success: true });
      }
    }
    if (fileRoute && ["GET", "HEAD"].includes(request.method))
      return serveFile(
        request,
        () => authenticate(token),
        z.string().parse(fileRoute[1]),
        z.string().parse(fileRoute[2]),
        Boolean(fileRoute[3]),
      );
    const playRoute = path.match(/^\/api\/items\/([^/]+)\/play(?:\/([^/]+))?$/);
    if (playRoute && request.method === "POST")
      return json(
        openPlayback(
          user,
          z.string().parse(playRoute[1]),
          playSchema.parse(await body(request)),
          playRoute[2],
        ),
      );
    const closeRoute = path.match(/^\/api\/session\/([^/]+)\/close$/);
    if (closeRoute && request.method === "POST") {
      sameOrigin(request);
      const sessionId = z.string().parse(closeRoute[1]);
      closePlayback(user, sessionId);
      await cancelTranscode(sessionId);
      return json({ success: true });
    }
    if (path.startsWith("/api/users")) {
      requireAdministrator(user);
      const segments = path.split("/");
      if (segments.length === 3 && request.method === "GET") return json({ users: listAccounts(user) });
      if (segments.length === 3 && request.method === "POST")
        return json(await createAccount(user, createAccountSchema.parse(await body(request))));
      const id = segments[3];
      if (id && segments.length === 4) {
        if (request.method === "GET") return json(accountResponse(findAccount(id)));
        if (request.method === "PATCH")
          return json(await editAccount(user, id, editAccountSchema.parse(await body(request))));
        if (request.method === "DELETE") {
          sameOrigin(request);
          removeAccount(user, id);
          return json({ success: true });
        }
      }
      if (id && segments.length === 5 && segments[4] === "revoke" && request.method === "POST") {
        sameOrigin(request);
        revokeAccount(user, id);
        return json({ success: true });
      }
    }
    if (path === "/api/me" && request.method === "GET") return json(accountResponse(user));
    if (path === "/api/authorize" && request.method === "POST")
      return json({ user: accountResponse(user), ereaderDevices: devicesFor(user) });
    if (
      ["/api/admin/migrations/lists", "/api/admin/migrations/lists/inspect"].includes(path) &&
      request.method === "POST"
    ) {
      const input = listImportSchema.parse(await body(request));
      return json(
        path.endsWith("/inspect") ? inspectLists(user, input.digest) : importLists(user, input.digest),
      );
    }
    if (
      ["/api/admin/migrations/delivery", "/api/admin/migrations/delivery/inspect"].includes(path) &&
      request.method === "POST"
    ) {
      const input = deliveryImportInput.parse(await body(request));
      return json(path.endsWith("/inspect") ? inspectDelivery(user, input) : importDelivery(user, input));
    }
    const listRoute = path.match(/^\/api\/(collections|playlists)(?:\/([^/]+)(?:\/(.*))?)?$/);
    if (listRoute) {
      const kind = listRoute[1] === "collections" ? "collection" : "playlist";
      const id = listRoute[2],
        action = listRoute[3];
      if (!id && request.method === "POST")
        return json(createList(user, kind, createListSchema.parse(await body(request))));
      if (id && !action) {
        if (request.method === "GET") return json(listFor(user, kind, id));
        if (request.method === "PATCH")
          return json(changeList(user, kind, id, editListSchema.parse(await body(request))));
        if (request.method === "DELETE") {
          sameOrigin(request);
          deleteList(user, kind, id);
          return json({ success: true });
        }
      }
      if (id && action?.match(/^batch\/(add|remove)$/) && request.method === "POST")
        return json(
          changeList(
            user,
            kind,
            id,
            listBatchSchema.parse(await body(request)),
            action === "batch/add" ? "add" : "remove",
          ),
        );
      if (id && kind === "collection" && action === "book" && request.method === "POST")
        return json(
          changeList(
            user,
            kind,
            id,
            { books: [z.object({ id: z.string() }).parse(await body(request)).id] },
            "add",
          ),
        );
      if (id && request.method === "DELETE") {
        sameOrigin(request);
        const member = action?.match(/^(?:book|item)\/([^/]+)(?:\/([^/]+))?$/);
        if (member)
          return json(
            changeList(
              user,
              kind,
              id,
              kind === "collection"
                ? { books: [z.string().parse(member[1])] }
                : { items: [{ libraryItemId: z.string().parse(member[1]), episodeId: member[2] ?? null }] },
              "remove",
            ),
          );
      }
    }
    if (path === "/api/libraries") {
      if (request.method === "GET") return json({ libraries: librariesFor(user) });
      if (request.method === "POST")
        return json(await createLibrary(user, createLibrarySchema.parse(await body(request))));
    }
    const seriesRoute = path.match(/^\/api\/libraries\/([^/]+)\/series\/([^/]+)$/);
    if (seriesRoute && request.method === "GET")
      return json(
        seriesFor(
          user,
          z.string().parse(seriesRoute[1]),
          decodeURIComponent(z.string().parse(seriesRoute[2])),
        ),
      );
    const authorRoute = path.match(/^\/api\/authors\/([^/]+)$/);
    if (authorRoute && request.method === "GET")
      return json(
        authorFor(
          user,
          decodeURIComponent(z.string().parse(authorRoute[1])),
          new URL(request.url).searchParams.get("library"),
        ),
      );
    const libraryRoute = path.match(/^\/api\/libraries\/([^/]+)(?:\/([^/]+))?$/);
    if (libraryRoute) {
      const id = z.string().parse(libraryRoute[1]);
      const action = libraryRoute[2];
      if (!action && request.method === "PATCH")
        return json(
          await editLibrary(user, id, editLibrarySchema.parse(await body(request)), () =>
            authenticate(token),
          ),
        );
      if (!action && request.method === "DELETE") {
        sameOrigin(request);
        removeLibrary(user, id);
        return json({ success: true });
      }
      if (action === "scan" && request.method === "POST") {
        sameOrigin(request);
        return json(await scanLibrary(user, id));
      }
      if (action === "scans" && request.method === "GET") return json({ scans: scanHistory(user, id) });
      if (request.method === "GET") {
        const items = itemsFor(user, id);
        if (!action)
          return json({
            library: findLibrary(id),
            ...(new URL(request.url).searchParams.get("include")?.split(",").includes("filterdata")
              ? { filterdata: filterData(items) }
              : {}),
            issues: items.filter((item) => item.isMissing || item.isInvalid).length,
            numUserPlaylists: listsFor(user, "playlist", id).total,
          });
        if (action === "collections" || action === "playlists")
          return json(
            listsFor(
              user,
              action === "collections" ? "collection" : "playlist",
              id,
              new URL(request.url).searchParams,
            ),
          );
        if (action === "search") return json(searchLibrary(user, id, new URL(request.url).searchParams));
        if (action === "items") return json(pagedItems(user, id, new URL(request.url).searchParams));
        if (action === "personalized") return json(personalized(user, id, new URL(request.url).searchParams));
        if (action === "authors") return json({ authors: authorGroups(items) });
        if (action === "series") return json(pagedSeries(user, id, new URL(request.url).searchParams));
        if (action === "filterdata") return json(filterData(items));
      }
    }
    const uploadRoute = path.match(/^\/api\/libraries\/([^/]+)\/upload$/);
    if (uploadRoute && request.method === "POST") {
      sameOrigin(request);
      return json(await upload(request, () => authenticate(token), z.string().parse(uploadRoute[1])));
    }
    if (coverRoute) {
      const id = z.string().parse(coverRoute[1]);
      if (["GET", "HEAD"].includes(request.method)) return cover(request, user, id);
      if (request.method === "POST") {
        sameOrigin(request);
        return json(await saveCover(request, () => authenticate(token), id));
      }
    }
    const editRoute = path.match(/^\/api\/items\/([^/]+)\/media$/);
    if (editRoute && request.method === "PATCH") {
      sameOrigin(request);
      return json(
        editMetadata(
          user,
          z.string().parse(editRoute[1]),
          metadataEditInput.parse(await body(request, 131072)),
        ),
      );
    }
    const restoreItemRoute = path.match(/^\/api\/items\/([^/]+)\/restore$/);
    if (restoreItemRoute && request.method === "POST") {
      sameOrigin(request);
      return json(restoreCatalogItem(user, z.string().parse(restoreItemRoute[1])));
    }
    if (path === "/api/admin/metadata-provider") {
      if (request.method === "GET") return json(providerSettings(user));
      if (request.method === "PATCH") {
        sameOrigin(request);
        return json(saveProvider(user, providerSettingsInput.parse(await body(request))));
      }
    }
    if (path === "/api/search/books" && request.method === "GET")
      return json(
        await metadataSearch(() => authenticate(token), new URL(request.url).searchParams.get("query") ?? ""),
      );
    const itemRoute = path.match(/^\/api\/items\/([^/]+)$/);
    if (itemRoute && request.method === "DELETE") {
      sameOrigin(request);
      z.object({ confirmation: z.literal("REMOVE") }).parse(await body(request));
      return json(removeCatalogItem(user, z.string().parse(itemRoute[1])));
    }
    if (itemRoute && request.method === "GET") return json(itemFor(user, z.string().parse(itemRoute[1])));
    throw new DomainError(404, "Not found");
  });
}

export function publicMedia(request: Request) {
  return boundary(async () => {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/public\/session\/([^/]+)\/track\/(\d+)$/);
    if (!match) throw new DomainError(404, "Not found");
    const token = bearer(request) ?? url.searchParams.get("token");
    return serveTrack(
      request,
      () => authenticate(token),
      z.string().parse(match[1]),
      z.coerce.number().int().min(1).parse(match[2]),
    );
  });
}

export function hlsMedia(request: Request) {
  return boundary(async () => {
    const url = new URL(request.url);
    const prefix = globalThis.leafwakeBasePath ?? "";
    const path =
      prefix && url.pathname.startsWith(`${prefix}/`) ? url.pathname.slice(prefix.length) : url.pathname;
    const match = path.match(/^\/hls\/([0-9a-f-]{36})\/([^/]+)$/);
    if (!match) throw new DomainError(404, "Not found");
    const token = bearer(request) ?? url.searchParams.get("token");
    return serveHls(
      request,
      () => authenticate(token),
      z.string().uuid().parse(match[1]),
      z.string().parse(match[2]),
    );
  });
}
