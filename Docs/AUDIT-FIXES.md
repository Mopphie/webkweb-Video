# Audit-Fixes und Prüfnachweise

Der Audit vom 13.10.2026 wurde umgesetzt. „Implementiert“ beschreibt den vorhandenen Code; es bedeutet keinen erfolgreichen Apple-SDK-/Gerätetest. L = ausgeführter Node-Test mit originaler Playback.js und DOM-Harness. X = vorhandener XCTest, erst auf dem Mac ausführbar. S = statisch geprüfter Codepfad. Der Harness ist kein echter Browser.

| Befund | Änderung | Nachweis |
| --- | --- | --- |
| F01 neue Autoplay-Player nach Timer | MutationObserver, Attach-/Play-/Tick-Sperre; explizites clearStop/resume | L: neue schon laufende Player, Cancel/Resume |
| F02 Audio/Nebenplayer als Video | primärer HTML-video-Player, Benutzerwahl, stabile Medien-/Zyklus-ID, Frame-Abgleich, Deduplizierung | L: Audio, Nebenplayer, primärer Endevent, Replay; X: SleepPlan |
| F03 Basisfilter/Listenlimit | Basis immer enthalten, alle unterstützten Regeln in <50k-Chunks, Ausnahmen je Chunk; keine alphabetische Kürzung | X: >40k Regeln/Basis/Ausnahmen; S: Quellenverwaltung |
| F04 Passwort-URL als Suche | credential-bearing URLs zurückweisen; Persistenz entfernt Benutzer/Passwort | X: Resolver/Sessionsnapshot |
| F05 zu breite Ausnahme | Host-Anker statt Teilstring, korrektes Ressourcen-/Domain-/Party-Scoping, bekannte Image-RegEx erhält Bedingungen; unbekannte Ausnahmen verwerfen Quelle | X: Query-/Userinfo-Spoof, Scoped-Regeln; S: Konverter |
| F06 Frame-Lifecycle | dokumentbezogene UUID, ready/dispose, Navigation/invalid-frame cleanup, SponsorTask-Cancel, BFCache-pageshow | L: gleiche URL verschiedene Dokumente, dispose/restore; S: WKFrameInfo-Lifecycle |
| F07 Datenlöschung/Rennen | alle Pending-Loads sofort abbrechen, Dokumente leeren und passenden WKNavigation-Abschluss abwarten, erst dann Stores löschen; währenddessen Tabs/Navigation sperren | X: Blank-Commit; S: Timeout/Abbruch/Storefolge |
| F08 veraltete Widget-Favoriten | gemeinsame stabile IDs, manuelle Reihenfolge, Besuchssync und @Query-Digest bei lokalen/Cloud-Änderungen | S: Snapshot-/Query-/Widgetpfad; Gerätetest offen |
| F09 Dialogverlust/prompt | Alert/Confirm/Prompt-Queue mit exakt einem Reply und Tab-Schließ-Cancel | X: zwei Replies/geschlossenes Tab; S: UI |
| F10 Cast/MIME/Fehler | currentSrc-MIME, reale SDK-Sitzung/Load/Status/Controls, lokale Pause nach Callback, Timer-/Commandrevision, Receiverfehler/Abort | L: MIME/DRM-Recycling; S: SDK/Signaturen; Workspace/Receiver offen |
| F11 Sponsorblock-Optionen | alle YouTube-Frames, native ID-/Kategorie-Abfrage, SPA-Lifecycle, Seiten-Ausnahmen, Skip/Undo | L: Kategorien/SPA/Skip/Undo; S: native iframe-Abfrage |
| F12 Update/Settings | tägliche aktive Foreground-/Aktivierungs-Checks, manuelles Update, persistierte Preferences inkl. Gesten | X: Preferences-Roundtrip; S: Scene-/Settingspfad |

## Ergänzte Optionen

| Bereich | Umsetzung | Noch nötige Apple-Prüfung |
| --- | --- | --- |
| Browser | Google/DuckDuckGo/Bing, Desktop-UA, Zoom, Popup/opener/close, private Tabs, History-off, normale Session-Wiederherstellung | WebKit/Popup/BFCache/Restore/Login |
| Filter | drei echte Preset-URLs, eigene HTTPS-Quellen/Textimport, Quelle ein/aus/löschen, Cache/Diagnose, Seiten-Allowlist | WK-RegEx/Chunk-Kompilierung/Performance |
| SponsorBlock | sponsor/intro/outro/selfpromo, Kategorien und Host-Seiten-/Frame-Ausnahmen, Skip/Undo | YouTube/iframe/SPA und Communitydaten |
| Timer | freie 1s–24h-Dauer, 1–100 Videos, aktuelles Video, normale Zeit-/Anzahlpläne persistiert | Suspension/Playlist/Neustart/Receiver |
| Daten | Favoriten editieren/manuell sortieren, stabile IDs und aktuelle Widget-/Siri-Snapshots | SwiftData/Migration/App Group |
| Widget/Siri | vier wählbare Favoriten per WidgetConfigurationIntent; vier queued App Intents, Home-Deep-Link | WidgetKit und Siri warm/kalt |
| Audio | MPRemoteCommandCenter/NowPlaying, Stop/Pause-Route für Clock, Unterbrechungen/Reaktivierung, private Metadaten | iOS stellt Befehle nicht garantiert an WK zu |
| Cast | echter Podfile und lokaler Workspace-Prüfpfad, Receiver-Steuerung/Fehler/Sessionwechsel | Pods/Xcode/Receiver/Lokalnetz-Berechtigung |
| CloudKit | default-fähiges Modell, opt-in, gleicher lokaler Store, realer Container konfigurierbar, lokaler Fallback | Apple-Team/Container/Push/Schema/Sync |
| Veröffentlichung | statische Privacy-/Support-/Betreiberfelder im App-Bundle, aktualisierte Datenflüsse/Store-Wording | echte öffentliche Angaben noch offen |

## Ausgeführt und offen

- Ausgeführt: 42 Node-Tests, Syntaxprüfung aller 23 Swift-Dateien, Plist-/YAML-/Manifest-/Ressourcen-, Shell- und Python-Syntaxprüfungen. Echte Preset-Dateien heruntergeladen (AdGuard ~4.5 MB, HaGeZi ~1.4 MB, StevenBlack ~2.2 MB); Swift-Konvertierung dieser Dateien und WebKit-Kompilierung hier nicht ausführbar.
- Vorbereitet, nicht ausgeführt: 30 XCTest-Definitionen. Lokaler Mac: `./Scripts/check-macos.sh`; mit Cast: `./Scripts/check-macos.sh --cast`.
- Extern offen: Xcode-Typprüfung, Standard- und Cast-Build, Simulator/UI, echte Medienfunktionen, Signing/App Group, CloudKit-Provisionierung und Sync. Öffentliche Policy-/Support-URL und Betreiberangaben bleiben auf Nutzerwunsch offen.
- Grenzen: keine vollständige EasyList-/Scriptlet-Engine, kein zuverlässiges Entfernen serverseitiger Streamwerbung, keine DRM/MSE-Cast-Übertragung, kein Cast-/Live-/Audio-Videozähler, keine Garantie für Hintergrund/Clock/Timer bei suspendierter App oder App-Store-Zulassung. Geschlossene Shadow Roots bleiben unzugänglich. Ein Timer für das konkrete alte Video wird beim Neustart bewusst verworfen, da neue Dokumente neue Medien-IDs erhalten.
- Keine GitHub Actions eingerichtet oder ausgeführt. Kein Merge in main.
