# Changelog

## 2026-03-20

### Inspector & Text
- Sendungsbeschreibung: markier- und kopierbar (`textSelection`), ohne Editierfeld.
- HTML-Fragmente aus der API: `&nbsp;`, `<br>` u. a. werden für die Anzeige sinnvoll in Klartext umgewandelt (`htmlFragmentPlainText`).
- Playlist: Titel & Künstler markierbar; Abspielen über sichtbare Play-Taste links und Kontextmenü „Von hier abspielen“; Wellensymbol entfernt (nur farbliche Hervorhebung).

### Wiedergabe & Position
- Gespeicherte Abspielposition wird verworfen, wenn die Folge bis fast ans Ende gehört wurde bzw. nahe dem Ende pausiert wird (verhindert „Abspielen am Ende“ ohne Ton).
- macOS: Leertaste pausiert/startet auch, wenn fokussierte, nicht editierbare Textauswahl im Inspector die Taste sonst schluckt (`MacSpacePlaybackKeyMonitor`).

### macOS: Steuerung
- Dock-Kontextmenü: Abspielen/Pause, nächster/vorheriger Titel (`MacAppDelegate` + `applicationDockMenu`).
- Globaler Hotkey **⌥⌘P** für Play/Pause (Carbon `RegisterEventHotKey`); Medientasten unverändert.

### API / Sendungsdetails
- Detail-URL wie die Website: `…/broadcasts/{Sendungs-Slug}/{datum_de}/{termin_slug}/?listen=no`.
- Erstes Pfadsegment: Slug der **Sendung** über `id_sendung` (`id_sendung` im Archiv-JSON) bzw. Titelabgleich mit der Sendungsliste, nicht nur `sendung_slug` aus dem Archiv (u. a. ByteFM-Mixtape-Folgen).
- `termin_slug`: typografische Bindestriche werden für die URL in ASCII-`-` normalisiert.
- Sendungsliste: `toArchiveItem` übergibt `sendungID` für konsistente URLs.
- Kein ISO-Datum im URL-Pfad (entfernt); robustere JSON-Dekodierung für Sendungsdetails bleibt erhalten.

### Archiv-Navigation
- **Neu im Archiv**: Liste nach **Kalendertag** in Abschnitte gegliedert; Überschriften „Heute / Gestern / Vorgestern“ jeweils mit Datum, ältere Tage mit Wochentag + Datum (`ArchiveSectionHelpers` + `ArchiveNew`).
- **Archiv** (Sendungsliste): Gruppierung nach Anfangsbuchstabe; **#** (Ziffern & Sonstiges) zuerst, dann A–Z; **Indexstreifen** mit `#` oben; Inhalt als **ScrollView + VStack-Sektionen** (statt `List`), damit Sprungmarken zuverlässig scrollen (lazy `NSTableView` vermeiden).
- Archiv-Sprung: **vertikale Elastizität** des Scrollviews wieder Standard (kein Abschalten mehr); nach `scrollTo` wird die **NSScrollView-Position auf den Inhalt begrenzt**, damit programmatisches Springen nicht kurz in den Gummiband-Bereich rutscht; zweiter `scrollTo`-Pass nach Layout (LazyVStack).
- Archiv: Sprung zum Buchstaben wieder **animiert** (`easeInOut`); Hover im Index **ohne Layout-Animation** und feste Zeilenhöhe, damit die Sendungsliste beim Überfahren nicht mitwandert.
- macOS: **Leertasten-Monitor** und **globaler Hotkey** werden in `applicationDidFinishLaunching` registriert (`MacAppDelegate`), nicht mehr in `BiteFMApp.init` (vermeidet fehlende Symbole / klarere Trennung).

### Projekt
- Neue Dateien in Xcode-Target und ggf. `project.pbxproj` ergänzt (`MacSpacePlaybackKeyMonitor`, `MacPlaybackGlobalHotkey`, `MacAppDelegate`, `ArchiveSectionHelpers`).
