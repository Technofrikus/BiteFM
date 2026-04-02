# BiteFM (macOS + iOS)

Ein nativer Client für den Radiosender [ByteFM](https://www.byte.fm). **Gemeinsame Logik** (`BiteFMCore`), mit schlanken App-Hüllen für **macOS** (`BiteFMMac`) und **iOS** (`BiteFMiOS`): adaptive Navigation (`NavigationSplitView` vs. `TabView`), kompakte Layouts auf dem iPhone und macOS-Menü/Hotkeys nur auf dem Mac.

## Hauptmerkmale

### 🎙 Live-Streaming
- **Drei Stream-Varianten**: Direkter Zugriff auf die Streams "Web", "Hamburg" und "Nur Musik".
- **Echtzeit-Metadaten**: Anzeige des aktuellen Titels, Künstlers und der Sendungsinformationen.
- **Titel-Historie**: Übersicht der zuletzt gespielten Songs für alle Livestreams.
- **Visuelle Details**: Anzeige von Künstlerbildern (sofern verfügbar) direkt in der Live-Ansicht.

### 📚 Umfangreiches Archiv ("Neu im Archiv")
- **Lokale Datenbank (SwiftData)**: Alle Archiv-Sendungen werden lokal in einer SwiftData-Datenbank gespeichert, was schnelles Scrollen und Offline-Einsicht ermöglicht.
- **Automatischer Abgleich**: Die App sucht alle 30 Minuten im Hintergrund nach neuen Sendungen.
- **Intelligente Bereinigung**: Automatische Löschung von Sendungen, die älter als 4 Wochen sind, um die Datenbank kompakt zu halten.
- **Show-Details im Inspector**: Detaillierte Informationen zur Sendung (Playlist, Beschreibung) werden in einem nativen macOS-Seitenteil (Inspector) angezeigt.

### 🎵 Player & Bedienung
- **Vollständige Medientasten-Unterstützung**: Steuerung von Play/Pause sowie das Springen zwischen Songs (im Archiv) über die macOS-Medientasten (F7-F9 / Touch Bar).
- **Interaktive Playlisten**: Ein Klick auf einen Song in der Playlist springt direkt zum entsprechenden Zeitstempel in der Archiv-Aufnahme.
- **Song-zu-Song Navigation**: Unterstützung für "Nächster Titel" und "Vorheriger Titel" innerhalb von Archiv-Sendungen.
- **Now-Playing Anzeige**: Integration in das macOS Kontrollzentrum und den Sperrbildschirm mit detaillierten Song-Informationen ("Interpret — Titel" und "Sendung — Ausgabe").
- **Visuelles Feedback**: Anzeige des Ladestatus (Buffering) und Hervorhebung des aktuell spielenden Songs in der Playlist.

### 🔐 Sicherheit & Komfort
- **Sicherer Login**: Verschlüsselte Speicherung der ByteFM-Zugangsdaten im macOS Schlüsselbund (Keychain).
- **Auto-Login**: Automatisches Anmelden beim App-Start für direkten Zugriff auf den Mitgliederbereich.
- **Fenster-Management**: Intelligente Anpassung der Fensterbreite beim Öffnen des Detail-Bereichs für optimale Lesbarkeit.

## Technische Basis
- **SwiftPM-Package**: Library `BiteFMCore` + ausführbares `BiteFMMac` für `swift build` / CLI.
- **SwiftUI**: Adaptive UI (regular vs. compact) für Mac und iPhone.
- **SwiftData**: Persistente Speicherung und Abfrage von Archiv-Daten.
- **AVFoundation (AVPlayer)**: Hochwertige Audio-Wiedergabe und Streaming-Management.
- **MediaPlayer Framework**: Systemweite Integration der Wiedergabesteuerung.
- **xcodegen**: Xcode-Projekt mit zwei App-Targets (Mac + iOS) und lokalem SPM-Package.

## Installation & Entwicklung

### Xcode (Mac- und iPhone-App)

1. Installiere `xcodegen` (falls nicht vorhanden): `brew install xcodegen`
2. Generiere das Projekt: `xcodegen generate`
3. Öffne `BiteFM.xcodeproj` in Xcode.
4. Schemes: **BiteFM** (macOS), **BiteFMiOS** (iPhone/iPad). iOS nutzt `Info-iOS.plist` inkl. **Background Audio** (`audio`).
5. **Echtes iPhone:** Scheme **BiteFMiOS**, Zielgerät wählen. Unter *Signing & Capabilities* für das Target **BiteFMiOS** ein **Team** auswählen (Apple-ID mit kostenloser oder bezahlter Mitgliedschaft). Dauerhaft über `xcodegen generate`: `DEVELOPMENT_TEAM` unter `BiteFMiOS` → `settings` in `project.yml` setzen (siehe `project.local.yml.example`).

### SwiftPM (nur Core + Mac-CLI)

```bash
swift build
swift test
swift run BiteFMMac
```

Details zu manuellen UI-/Audio-Checks: siehe `TESTING.md`.

---
*Hinweis: Dies ist ein inoffizieller Client und steht in keiner direkten Verbindung zur ByteFM GmbH.*
