# BiteFM — Domain & Module Context

Shared vocabulary for architecture work. Names the seams so future reviews and
refactors use one language. This is a glossary, not a spec — see `AGENTS.md`
for build/test commands and `docs/adr/` (none yet) for recorded decisions.

## Domain terms

- **Broadcast** — one episode / *Ausgabe* of a show. The unit users play. Keyed by
  `terminID` (episode id) and `terminSlug`. Surfaces as `ArchiveItem` in the UI
  and `StoredArchiveItem` in SwiftData.
- **Show** (*Sendungsreihe*) — a recurring program. Keyed by `id` and `slug`.
  Surfaces as `Show` and `StoredShow`. An archive tab groups broadcasts under shows.
- **Favorite** — two distinct flavors, easy to conflate:
  - *Broadcast-level* favorite, tracked by `favoriteSlugs: Set<String>` (slugs + titles).
  - *Episode-level* favorite, tracked by `favoriteShowIDs: Set<Int>` (show/termin ids).
  - Resolution lives in `FavoriteStateLogic` (`isFavoriteBroadcast`,
    `isEpisodeFavorite`, `isFavoriteArchiveItem`).
- **Listening-history / Played** — episodes the user has heard, tracked by
  `listenedShowIDs: Set<Int>`. Drives the "hide played" filter.
- **Live metadata** — now-playing song info for the live stream, polled every 60s.
  Consumed only by `LiveView` and `PlayerBarView` (when live).

## Modules (BiteFMCore)

- **`APIClient`** — networking facade (`ObservableObject`). Owns `URLSession`,
  auth, and all remote fetches (favorites, history, archive, shows, live metadata).
  Publishes the raw state sets above; does not own view-level snapshots.
- **`FavoritePlayedStore`** — *deep module* (added 2026-07-20). Single narrow
  snapshot (`FavoritePlayedState`) of favorite/played state that list rows need.
  Observes `APIClient`'s three sets and republishes one value, so rows (via
  `makeBroadcastRow`) don't observe the whole `APIClient` and aren't re-rendered
  by unrelated publishes (e.g. the 60s live-metadata poll). `APIClient` calls
  `FavoritePlayedStore.shared.refresh()` after mutating the underlying sets.
- **`ActivePlaybackStore`** — narrow "which row is active" snapshot of
  `AudioPlayerManager`, so the 1 Hz progress tick doesn't re-render every row.
- **`AudioPlayerManager`** — `AVPlayer` wrapper: playback, seeking, live stream,
  Now Playing, session restore.
- **`PlaybackQueueStore`** — *Warteschlange* / "Als Nächstes": only the upcoming
  broadcasts (never the current one), unique by `terminID`, persisted as JSON in
  `UserDefaults` (no expiry, unlike `AppRestorationStore`). `AudioPlayerManager`
  pops the next entry on natural end and when ⏭ runs past the last track; starting
  a broadcast removes it from the queue. Local only, no sync.
- **`ArchiveSectioner`** (candidate) — grouping/sort logic for archive tabs is
  currently duplicated in `ArchiveView` / `ArchiveNew`; proposed to extract.
