import { z } from "zod";
import { feedSchema } from "./feeds";

// Contract boundary with the Audiobookshelf server (verified against 2.30.0). Objects are loose so newer servers
// can add fields; only fields this client reads are declared, and they are validated.

const nullableString = z.string().nullish();

export const statusSchema = z.looseObject({
  app: z.string().optional(),
  serverVersion: z.string().optional(),
  isInit: z.boolean(),
  language: z.string().nullish(),
  authMethods: z.array(z.string()).default(["local"]),
  authFormData: z
    .looseObject({
      authLoginCustomMessage: nullableString,
      authOpenIDButtonText: nullableString,
      authOpenIDAutoLaunch: z.boolean().nullish(),
    })
    .nullish(),
});
export type ServerStatus = z.infer<typeof statusSchema>;

export const permissionsSchema = z.looseObject({
  download: z.boolean().default(false),
  update: z.boolean().default(false),
  delete: z.boolean().default(false),
  upload: z.boolean().default(false),
  createEreader: z.boolean().default(false),
  accessExplicitContent: z.boolean().default(false),
});

export const mediaProgressSchema = z.looseObject({
  id: z.string(),
  libraryItemId: z.string(),
  episodeId: nullableString,
  duration: z.number().default(0),
  progress: z.number().default(0),
  currentTime: z.number().default(0),
  isFinished: z.boolean().default(false),
  hideFromContinueListening: z.boolean().nullish(),
  ebookLocation: nullableString,
  ebookProgress: z.number().nullish(),
  lastUpdate: z.number().default(0),
  startedAt: z.number().nullish(),
  finishedAt: z.number().nullish(),
});
export type MediaProgress = z.infer<typeof mediaProgressSchema>;

export const bookmarkSchema = z.looseObject({
  libraryItemId: z.string(),
  title: z.string(),
  time: z.number(),
  createdAt: z.number().nullish(),
});
export type Bookmark = z.infer<typeof bookmarkSchema>;

export const userSchema = z.looseObject({
  id: z.string(),
  username: z.string(),
  type: z.string(),
  token: nullableString,
  accessToken: nullableString,
  refreshToken: nullableString,
  mediaProgress: z.array(mediaProgressSchema).default([]),
  bookmarks: z.array(bookmarkSchema).default([]),
  seriesHideFromContinueListening: z.array(z.string()).default([]),
  permissions: permissionsSchema.default({
    download: false,
    update: false,
    delete: false,
    upload: false,
    createEreader: false,
    accessExplicitContent: false,
  }),
  librariesAccessible: z.array(z.string()).default([]),
});
export type User = z.infer<typeof userSchema>;

export const ereaderDeviceSchema = z.looseObject({ name: z.string() });

export const loginResponseSchema = z.looseObject({
  user: userSchema,
  userDefaultLibraryId: nullableString,
  serverSettings: z.looseObject({ version: z.string().optional(), language: nullableString }).nullish(),
  ereaderDevices: z.array(ereaderDeviceSchema).default([]),
});
export type LoginResponse = z.infer<typeof loginResponseSchema>;

export const librarySchema = z.looseObject({
  id: z.string(),
  name: z.string(),
  mediaType: z.enum(["book", "podcast"]),
  icon: z.string().nullish(),
  displayOrder: z.number().default(0),
  isArchived: z.boolean().default(false),
  folders: z.array(z.looseObject({ id: z.string(), fullPath: z.string() })).default([]),
  settings: z.looseObject({ coverAspectRatio: z.number().default(1) }).nullish(),
});
export type Library = z.infer<typeof librarySchema>;
export const librariesResponseSchema = z.object({ libraries: z.array(librarySchema) });

const namedSchema = z.looseObject({ id: z.string(), name: z.string() });
export const filterDataSchema = z.looseObject({
  authors: z.array(namedSchema).default([]),
  genres: z.array(z.string()).default([]),
  tags: z.array(z.string()).default([]),
  series: z.array(namedSchema).default([]),
  narrators: z.array(z.string()).default([]),
  languages: z.array(z.string()).default([]),
});
export type FilterData = z.infer<typeof filterDataSchema>;
export const libraryWithFilterDataSchema = z.looseObject({
  library: librarySchema,
  filterdata: filterDataSchema.nullish(),
  issues: z.number().default(0),
  numUserPlaylists: z.number().default(0),
});

const fileMetadataSchema = z.looseObject({
  filename: z.string(),
  ext: z.string(),
  size: z.number().nullish(),
});

export const ebookFileSchema = z.looseObject({
  ino: z.string(),
  ebookFormat: z.string().nullish(),
  metadata: fileMetadataSchema,
});

export const libraryFileSchema = z.looseObject({
  ino: z.string(),
  fileType: z.string(),
  isSupplementary: z.boolean().nullish(),
  metadata: fileMetadataSchema,
});
export type LibraryFile = z.infer<typeof libraryFileSchema>;

export const chapterSchema = z.looseObject({
  id: z.number(),
  start: z.number(),
  end: z.number(),
  title: z.string(),
});
export type Chapter = z.infer<typeof chapterSchema>;

export const audioTrackSchema = z.looseObject({
  index: z.number().nullish(),
  startOffset: z.number(),
  duration: z.number(),
  title: nullableString,
  contentUrl: z.string(),
  mimeType: nullableString,
});
export type AudioTrack = z.infer<typeof audioTrackSchema>;

export const seriesRefSchema = z.looseObject({ id: z.string(), name: z.string(), sequence: nullableString });

export const bookMetadataSchema = z.looseObject({
  title: z
    .string()
    .nullish()
    .transform((value) => value ?? ""),
  subtitle: nullableString,
  authorName: nullableString,
  authors: z.array(namedSchema).nullish(),
  narratorName: nullableString,
  narrators: z.array(z.string()).nullish(),
  seriesName: nullableString,
  // Minified items filtered by one series carry just that series as an object.
  series: z.union([z.array(seriesRefSchema), seriesRefSchema.transform((one) => [one])]).nullish(),
  genres: z.array(z.string()).default([]),
  publishedYear: nullableString,
  publisher: nullableString,
  description: nullableString,
  language: nullableString,
  explicit: z.boolean().nullish(),
  // Podcast metadata
  author: nullableString,
  feedUrl: nullableString,
  type: nullableString,
});
export type MediaMetadata = z.infer<typeof bookMetadataSchema>;

export const podcastEpisodeSchema = z.looseObject({
  id: z.string(),
  libraryItemId: z.string(),
  title: z
    .string()
    .nullish()
    .transform((value) => value ?? ""),
  subtitle: nullableString,
  description: nullableString,
  season: nullableString,
  episode: nullableString,
  episodeType: nullableString,
  publishedAt: z.number().nullish(),
  duration: z.number().nullish(),
  size: z.number().nullish(),
  audioFile: z.looseObject({ duration: z.number().nullish(), metadata: fileMetadataSchema }).nullish(),
  chapters: z.array(chapterSchema).default([]),
  /** Where a downloaded episode came from; matches the feed's enclosure. */
  enclosure: z.looseObject({ url: z.string() }).nullish(),
});
export type PodcastEpisode = z.infer<typeof podcastEpisodeSchema>;

const episodeDownloadSchema = z.looseObject({ id: z.string(), episodeDisplayTitle: nullableString });

export const libraryItemSchema = z.looseObject({
  progressGeneration: z.number().int().nonnegative().optional(),
  progressGenerations: z.record(z.string(), z.number().int().nonnegative()).optional(),
  id: z.string(),
  libraryId: z.string(),
  mediaType: z.enum(["book", "podcast"]),
  addedAt: z.number().nullish(),
  updatedAt: z.number().nullish(),
  isMissing: z.boolean().nullish(),
  historyOnly: z.boolean().optional(),
  historicalTagsUnknown: z.boolean().optional(),
  isInvalid: z.boolean().nullish(),
  media: z.looseObject({
    metadata: bookMetadataSchema,
    coverPath: nullableString,
    tags: z.array(z.string()).default([]),
    duration: z.number().nullish(),
    numTracks: z.number().nullish(),
    numChapters: z.number().nullish(),
    numEpisodes: z.number().nullish(),
    ebookFormat: nullableString,
    ebookFile: ebookFileSchema.nullish(),
    chapters: z.array(chapterSchema).nullish(),
    tracks: z.array(audioTrackSchema).nullish(),
    episodes: z.array(podcastEpisodeSchema).nullish(),
  }),
  libraryFiles: z.array(libraryFileSchema).nullish(),
  numEpisodesIncomplete: z.number().nullish(),
  recentEpisode: podcastEpisodeSchema.nullish(),
  collapsedSeries: z.looseObject({ id: z.string(), name: z.string(), numBooks: z.number() }).nullish(),
  progressLastUpdate: z.number().nullish(),
  episodeDownloadsQueued: z.array(episodeDownloadSchema).nullish(),
  episodesDownloading: z.array(episodeDownloadSchema).nullish(),
  rssFeed: feedSchema.nullish(),
});
export type LibraryItem = z.infer<typeof libraryItemSchema>;

export const pagedItemsSchema = z.looseObject({
  results: z.array(libraryItemSchema),
  total: z.number(),
  page: z.number().default(0),
});

export const seriesSchema = z.looseObject({
  id: z.string(),
  name: z.string(),
  description: nullableString,
  books: z.array(libraryItemSchema).default([]),
});
export type Series = z.infer<typeof seriesSchema>;
export const pagedSeriesSchema = z.looseObject({ results: z.array(seriesSchema), total: z.number() });

export const authorSchema = z.looseObject({
  id: z.string(),
  name: z.string(),
  description: nullableString,
  imagePath: nullableString,
  numBooks: z.number().nullish(),
  updatedAt: z.number().nullish(),
});
export type Author = z.infer<typeof authorSchema>;
export const authorsResponseSchema = z.looseObject({ authors: z.array(authorSchema) });
export const authorDetailSchema = authorSchema.extend({
  libraryItems: z.array(libraryItemSchema).default([]),
  series: z
    .array(z.looseObject({ id: z.string(), name: z.string(), items: z.array(libraryItemSchema).default([]) }))
    .default([]),
});

const episodeWithPodcastSchema = podcastEpisodeSchema.extend({
  podcast: z
    .looseObject({
      id: z.string().nullish(),
      libraryItemId: z.string().nullish(),
      metadata: bookMetadataSchema,
      coverPath: nullableString,
    })
    .nullish(),
});
export type EpisodeWithPodcast = z.infer<typeof episodeWithPodcastSchema>;

export const shelfSchema = z.discriminatedUnion("type", [
  z.looseObject({
    id: z.string(),
    label: z.string(),
    labelStringKey: nullableString,
    type: z.literal("book"),
    entities: z.array(libraryItemSchema),
  }),
  z.looseObject({
    id: z.string(),
    label: z.string(),
    labelStringKey: nullableString,
    type: z.literal("podcast"),
    entities: z.array(libraryItemSchema),
  }),
  z.looseObject({
    id: z.string(),
    label: z.string(),
    labelStringKey: nullableString,
    type: z.literal("series"),
    entities: z.array(seriesSchema),
  }),
  z.looseObject({
    id: z.string(),
    label: z.string(),
    labelStringKey: nullableString,
    type: z.literal("authors"),
    entities: z.array(authorSchema),
  }),
  z.looseObject({
    id: z.string(),
    label: z.string(),
    labelStringKey: nullableString,
    type: z.literal("episode"),
    entities: z.array(libraryItemSchema),
  }),
]);
export type Shelf = z.infer<typeof shelfSchema>;
// Unknown shelf types from newer servers are dropped rather than failing the whole home screen.
export const personalizedSchema = z.array(z.unknown()).transform((shelves) =>
  shelves.flatMap((shelf) => {
    const parsed = shelfSchema.safeParse(shelf);
    return parsed.success ? [parsed.data] : [];
  }),
);

export const searchResultsSchema = z.looseObject({
  book: z.array(z.looseObject({ libraryItem: libraryItemSchema })).default([]),
  podcast: z.array(z.looseObject({ libraryItem: libraryItemSchema })).default([]),
  episodes: z.array(z.looseObject({ libraryItem: libraryItemSchema })).default([]),
  series: z
    .array(z.looseObject({ series: seriesSchema, books: z.array(libraryItemSchema).default([]) }))
    .default([]),
  authors: z.array(authorSchema).default([]),
  narrators: z.array(z.looseObject({ name: z.string(), numBooks: z.number().nullish() })).default([]),
  tags: z.array(z.looseObject({ name: z.string(), numItems: z.number().nullish() })).default([]),
  genres: z.array(z.looseObject({ name: z.string(), numItems: z.number().nullish() })).default([]),
});
export type SearchResults = z.infer<typeof searchResultsSchema>;

export const collectionSchema = z.looseObject({
  id: z.string(),
  userId: z.string().optional(),
  libraryId: z.string(),
  name: z.string(),
  description: nullableString,
  books: z.array(libraryItemSchema).default([]),
});
export type Collection = z.infer<typeof collectionSchema>;
export const pagedCollectionsSchema = z.looseObject({
  results: z.array(collectionSchema),
  total: z.number(),
});

export const playlistItemSchema = z.looseObject({
  libraryItemId: z.string(),
  episodeId: nullableString,
  libraryItem: libraryItemSchema.nullish(),
  episode: podcastEpisodeSchema.nullish(),
});
export type PlaylistItem = z.infer<typeof playlistItemSchema>;
export const playlistSchema = z.looseObject({
  id: z.string(),
  libraryId: z.string(),
  userId: z.string(),
  name: z.string(),
  description: nullableString,
  items: z.array(playlistItemSchema).default([]),
});
export type Playlist = z.infer<typeof playlistSchema>;
export const pagedPlaylistsSchema = z.looseObject({ results: z.array(playlistSchema), total: z.number() });

export const recentEpisodesSchema = z.looseObject({
  episodes: z.array(episodeWithPodcastSchema.extend({ libraryId: z.string() })),
  limit: z.number().nullish(),
  page: z.number().nullish(),
});

export const playbackSessionSchema = z.looseObject({
  progressGeneration: z.number().int().nonnegative().optional(),
  id: z.string(),
  libraryItemId: z.string(),
  episodeId: nullableString,
  mediaType: z.enum(["book", "podcast"]),
  displayTitle: nullableString,
  displayAuthor: nullableString,
  duration: z.number(),
  currentTime: z.number(),
  playMethod: z.number(),
  chapters: z.array(chapterSchema).default([]),
  audioTracks: z.array(audioTrackSchema),
  startedAt: z.number().nullish(),
  updatedAt: z.number().nullish(),
});
export type PlaybackSession = z.infer<typeof playbackSessionSchema>;

export const localSyncResultSchema = z.looseObject({
  results: z.array(
    z.looseObject({
      id: z.string(),
      success: z.boolean(),
      progressSynced: z.boolean().nullish(),
      error: nullableString,
    }),
  ),
});

export const listeningStatsSchema = z.looseObject({
  totalTime: z.number().default(0),
  days: z.record(z.string(), z.number()).default({}),
  dayOfWeek: z.record(z.string(), z.number()).default({}),
  items: z
    .record(
      z.string(),
      z.looseObject({
        id: z.string(),
        timeListening: z.number(),
        mediaMetadata: bookMetadataSchema.nullish(),
      }),
    )
    .default({}),
  recentSessions: z
    .array(
      z.looseObject({
        id: z.string(),
        libraryItemId: z.string(),
        displayTitle: nullableString,
        displayAuthor: nullableString,
        timeListening: z.union([z.number(), z.string()]).transform(Number),
        updatedAt: z.number(),
        deviceInfo: z.looseObject({ clientName: nullableString, deviceName: nullableString }).nullish(),
      }),
    )
    .default([]),
});
export type ListeningStats = z.infer<typeof listeningStatsSchema>;

export const podcastSearchResultSchema = z.looseObject({
  id: z.number().nullish(),
  title: z.string(),
  artistName: nullableString,
  description: nullableString,
  feedUrl: nullableString,
  cover: nullableString,
  genres: z.array(z.string()).default([]),
  releaseDate: nullableString,
  pageUrl: nullableString,
  artistId: z.number().nullish(),
  language: nullableString,
  explicit: z.boolean().nullish(),
});

export type PodcastSearchResult = z.infer<typeof podcastSearchResultSchema>;
export const podcastSearchResultsSchema = z.array(podcastSearchResultSchema);

export const podcastFeedSchema = z.looseObject({
  podcast: z.looseObject({
    metadata: z.looseObject({
      title: z.string(),
      author: nullableString,
      description: nullableString,
      descriptionPlain: nullableString,
      releaseDate: nullableString,
      genres: z.array(z.string()).nullish(),
      categories: z.array(z.string()).nullish(),
      feedUrl: nullableString,
      image: nullableString,
      imageUrl: nullableString,
      itunesPageUrl: nullableString,
      itunesId: z.union([z.string(), z.number()]).nullish(),
      itunesArtistId: z.union([z.string(), z.number()]).nullish(),
      language: nullableString,
      explicit: z.union([z.boolean(), z.string()]).nullish(),
      type: nullableString,
    }),
    episodes: z
      .array(
        z.looseObject({
          title: z.string().nullish(),
          description: nullableString,
          publishedAt: z.number().nullish(),
          enclosure: z.looseObject({ url: z.string() }).nullish(),
          guid: nullableString,
          duration: z.union([z.string(), z.number()]).nullish(),
        }),
      )
      .default([]),
  }),
});
export type PodcastFeed = z.infer<typeof podcastFeedSchema>;

export const anyJson = z.unknown();

const ranked = <Shape extends z.ZodRawShape>(shape: Shape) =>
  z.array(z.looseObject({ ...shape, time: z.number().default(0) })).default([]);
const rankedGenres = ranked({ genre: z.string() }).transform((genres) =>
  genres.map(({ genre, time }) => ({ name: genre, time })),
);
const itemIds = z.array(z.string()).default([]);

export const yearStatsSchema = z.looseObject({
  totalListeningSessions: z.number().default(0),
  totalListeningTime: z.number().default(0),
  numBooksFinished: z.number().default(0),
  numBooksListened: z.number().default(0),
  topAuthors: ranked({ name: z.string() }),
  topGenres: rankedGenres,
  mostListenedNarrator: z.looseObject({ name: z.string(), time: z.number() }).nullish(),
  mostListenedMonth: z.looseObject({ month: z.number(), time: z.number() }).nullish(),
  booksWithCovers: itemIds,
  finishedBooksWithCovers: itemIds,
});
export type YearStats = z.infer<typeof yearStatsSchema>;

export const serverYearStatsSchema = z.looseObject({
  numListeningSessions: z.number().default(0),
  totalListeningTime: z.number().default(0),
  numBooksAdded: z.number().default(0),
  numAuthorsAdded: z.number().default(0),
  totalBooksAddedSize: z.number().default(0),
  totalBooksSize: z.number().default(0),
  totalBooksAddedDuration: z.number().default(0),
  totalBooksDuration: z.number().default(0),
  booksAddedWithCovers: itemIds,
  topAuthors: ranked({ name: z.string() }),
  topNarrators: ranked({ name: z.string() }),
  topGenres: rankedGenres,
});
export type ServerYearStats = z.infer<typeof serverYearStatsSchema>;
