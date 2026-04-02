# iOS Downloads – Verifikationsmatrix (manuell)

Voraussetzung: iPhone oder iPad, eingeloggter Account, genügend Speicher für mindestens einen Test-Download.

| # | Szenario | Erwartung |
|---|-----------|-----------|
| 1 | Download starten aus **Neu im Archiv** | Status in der Zeile: Vorbereitung → Fortschritt; nach Abschluss lokales Play-Icon; Eintrag im Tab **Downloads**. |
| 2 | Download aus **Archiv** (Sendungsliste) | Wie (1). |
| 3 | Download aus **Favoriten: Ausgaben** | Wie (1). |
| 4 | Download aus **BroadcastDetail** (Button „Herunterladen“) | Offline-Detail wird gespeichert; Audio lädt; Detail später offline nutzbar. |
| 5 | App in den **Hintergrund** während Download | Download läuft weiter; nach Rückkehr konsistenter Status / abgeschlossen. |
| 6 | **App killen** oder **Neustart** während Download | Entweder Fortsetzung über Background-Session oder klarer Fehler/Retry-Zustand; keine inkonsistenten „fertig“-Zustände ohne Datei. |
| 7 | **Flugmodus** bei **fertig heruntergeladener** Folge | Wiedergabe aus lokaler Datei; Now Playing wie online. |
| 8 | **Offline** Detail zu **nur gecachter**, nicht heruntergeladener Folge | Wo implementiert: Detail sichtbar, Audio mit klarer Hinweismeldung. |
| 9 | **Offline** ohne Cache | Leerzustand / klare Meldung statt stiller Fehler. |
| 10 | **Speicherlimit** in Download-Einstellungen erreichen | Alert: älteste Sendung löschen; bei Zustimmung Retry; bei Ablehnung Abbruch mit nachvollziehbarem Fehlertext in der Zeile. |
| 11 | **Wenig freier Gerätespeicher** | Alert „Speicher“ / kein stiller Fehler. |
| 12 | **Swipe-Löschen** eines Downloads | Datei und Metadaten weg; nicht mehr abspielbar offline. |
| 13 | **Bearbeiten** → Mehrfachauswahl → **Löschen** | Alle gewählten Einträge entfernt. |
| 14 | **Alle löschen** (mit Bestätigung) | Liste leer; keine verwaisten Dateien nach erneutem App-Start (`runForegroundMaintenance`). |
| 15 | **Retention** (1–4 Wochen, in Einstellungen) | Abgelaufene, vollständige Downloads werden entfernt; **aktuell laufende Wiedergabe** bleibt erhalten. |
| 16 | **Abmelden** | Alle Download-Datensätze, Offline-Details und lokale Download-Dateien entfernt. |
| 17 | **iPad**: Sidebar **Downloads** | `DownloadsView` im Detail wie auf dem iPhone-Tab. |
| 18 | **macOS** | Keine Download-Steuerung in Zeilen/Detail; kein Download-Tab (Regression-Check). |

Hinweis: Automatisierte Tests auf dem Paket laufen gegen **macOS**; iOS-spezifische SwiftData- und `URLSession`-Pfade sind hier dokumentiert und auf Gerät/Simulator zu prüfen.
