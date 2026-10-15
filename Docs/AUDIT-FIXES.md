# Audit-Fixes und Prüfnachweise

> Historische Audit-Momentaufnahme. Der aktuelle Stand der Tests, Website und offenen Release-Punkte steht in [RELEASE.md](RELEASE.md); ältere Testzahlen und die dort als fehlend bezeichneten Kontaktangaben sind überholt.

Der Audit vom 13.10.2026 wurde umgesetzt und am 15.10.2026 auf die kommerziell bereinigte Fassung angepasst. Entfernte Integrationen werden nicht mehr als verfügbare Funktionen geführt. „Implementiert“ beschreibt den vorhandenen Code; es bedeutet keinen erfolgreichen Apple-SDK-/Gerätetest. L = ausgeführter Node-Test mit originaler Playback.js und DOM-Harness. X = vorhandener XCTest, erst auf dem Mac ausführbar. S = statisch geprüfter Codepfad. Der Harness ist kein echter Browser.

| Befund | Änderung | Nachweis |
| --- | --- | --- |
| F01 neue Autoplay-Player nach Timer | MutationObserver, Attach-/Play-/Tick-Sperre; explizites clearStop/resume | L: neue schon laufende Player, Cancel/Resume |
| F02 Audio/Nebenplayer als Video | primärer HTML-video-Player, Benutzerwahl, stabile Medien-/Zyklus-ID, Frame-Abgleich, Deduplizierung | L: Audio, Nebenplayer, primärer Endevent, Replay; X: SleepPlan |
| F03 Basisfilter/Listenlimit | Basis immer enthalten, alle unterstützten Regeln in <50k-Chunks, Ausnahmen je Chunk; keine alphabetische Kürzung | X: >40k Regeln/Basis/Ausnahmen; S: Quellenverwaltung |
| F04 Passwort-URL als Suche | credential-bearing URLs zurückweisen; Persistenz entfernt Benutzer/Passwort | X: Resolver/Sessionsnapshot |
| F05 zu breite Ausnahme | Host-Anker statt Teilstring, korrektes Ressourcen-/Domain-/Party-Scoping, bekannte Image-RegEx erhält Bedingungen; unbekannte Ausnahmen verwerfen Quelle | X: Query-/Userinfo-Spoof, Scoped-Regeln; S: Konverter |
| F06 Frame-Lifecycle | dokumentbezogene UUID, ready/dispose, Navigation/invalid-frame cleanup, BFCache-pageshow | L: gleiche URL verschiedene Dokumente, dispose/restore; S: WKFrameInfo-Lifecycle |
| F07 Datenlöschung/Rennen | alle Pending-Loads sofort abbrechen, Dokumente leeren und passenden WKNavigation-Abschluss abwarten, erst dann Stores löschen; währenddessen Tabs/Navigation sperren | X: Blank-Commit; S: Timeout/Abbruch/Storefolge |
| F08 veraltete Widget-Favoriten | gemeinsame stabile IDs, manuelle Reihenfolge, Besuchssync und @Query-Digest bei lokalen/Cloud-Änderungen | S: Snapshot-/Query-/Widgetpfad; Gerätetest offen |
| F09 Dialogverlust/prompt | Alert/Confirm/Prompt-Queue mit exakt einem Reply und Tab-Schließ-Cancel | X: zwei Replies/geschlossenes Tab; S: UI |
| F12 Update/Settings | tägliche aktive Foreground-/Aktivierungs-Checks, manuelles Update, persistierte Preferences inkl. Gesten | X: Preferences-Roundtrip; S: Scene-/Settingspfad |

## Ergänzte Optionen

| Bereich | Umsetzung | Noch nötige Apple-Prüfung |
| --- | --- | --- |
| Browser | Google/DuckDuckGo/Bing, Desktop-UA, Zoom, Popup/opener/close, private Tabs, History-off, normale Session-Wiederherstellung | WebKit/Popup/BFCache/Restore/Login |
| Filter | zwei Preset-URLs mit Lizenzhinweisen, eigene HTTPS-Quellen/Textimport, Quelle ein/aus/löschen, Cache/Diagnose, Seiten-Allowlist | WK-RegEx/Chunk-Kompilierung/Performance |
| Timer | freie 1s–24h-Dauer, 1–100 Videos, aktuelles Video, normale Zeit-/Anzahlpläne persistiert | Suspension/Playlist/Neustart |
| Daten | Favoriten editieren/manuell sortieren, stabile IDs und aktuelle Widget-/Siri-Snapshots | SwiftData/Migration/App Group |
| Widget/Siri | vier wählbare Favoriten per WidgetConfigurationIntent; vier queued App Intents, Home-Deep-Link | WidgetKit und Siri warm/kalt |
| Audio | MPRemoteCommandCenter/NowPlaying, Stop/Pause-Route für Clock, Unterbrechungen/Reaktivierung, private Metadaten | iOS stellt Befehle nicht garantiert an WK zu |
| CloudKit | default-fähiges Modell, opt-in, gleicher lokaler Store, realer Container konfigurierbar, lokaler Fallback | Apple-Team/Container/Push/Schema/Sync |
| Veröffentlichung | statische Privacy-/Support-/Betreiberfelder im App-Bundle, aktualisierte Datenflüsse/Store-Wording | Abgleich der vorhandenen Angaben mit finalem Build offen |

## Ausgeführt und offen

- Ausgeführt am 15.10.2026: 40/40 Node-Tests mit den originalen verbleibenden Seitenskripten, Tree-sitter-Syntaxprüfung von 24 Swift-Dateien, Plist-/Entitlement-/Manifest-/JSON-/YAML-/Ressourcen-, Shell- und Python-Prüfungen. Die portable Prüfung bestätigt entfernte Dateien, Produktionssymbole, Buildflags und Cast-Netzwerkberechtigungen.
- Vorbereitet, nicht ausgeführt: 34 XCTest-Definitionen. Mac: `./Scripts/check-macos.sh`.
- Extern offen: Apple-SDK-Typprüfung, Xcode/Simulator/Geräte, echte Medienfunktionen, Signierung/App Group, CloudKit-Provisionierung und Sync. Öffentliche Angaben und externe Rechteseite müssen mit dem finalen Build abgeglichen werden.
- Grenzen: keine vollständige EasyList-/Scriptlet-Engine, keine zuverlässige Entfernung serverseitiger Streamwerbung und keine Garantie für Hintergrund/Clock/Timer bei suspendierter App. Geschlossene Shadow Roots bleiben unzugänglich. Ein Timer für das konkrete alte Video wird beim Neustart verworfen, da neue Dokumente neue Medien-IDs erhalten.
- Keine Actions gestartet, kein Merge. Der übernommene Workflow bleibt ausschließlich manuell auslösbar.

## Erneuter Audit am 14.10.2026

Quellcodeprüfung über Route/Bridge/Medien/Timer/Tabs/Queue/Filter/Settings/SwiftData/Intents/Widget und native Integration. Echte Regressionstests sichern die weiter vorhandenen Funktionen; Tests ausschließlich entfernter Funktionen sind ebenfalls entfernt. Keine kosmetischen Icon-Mirror-Tests. Die Startseite verwendet jetzt acht flache Glyphs ohne Glasflächen, mit unverändert großer transparenter Trefferfläche. Suchfeld und funktionale Browsersteuerung behalten Glass/Material.

| Konkreter Befund | Korrektur | Nachweis |
| --- | --- | --- |
| App-Start/Foreground aktivierten AVAudioSession ohne Player und konnten fremdes Audio unterbrechen | Bedarfspolitik statt unbedingtem setActive; bereits aktives Audio bleibt bis tatsächlicher Pausebestätigung aktiv | Native Policy-Tests vorbereitet; AV-Gerätetest offen |
| Now Playing meldete immer 1×; medienloser neuer Tab verlor Hintergrund-Remote-Steuerung | reale lokale Rate, Pause 0; aktiver Hintergrundplayer als Fallback, ausgewählter Player behält Vorrang | Native Policy-Tests vorbereitet |
| Restore lud alle Tabs mit Autoplayfreigabe und speicherte vor Abschluss leere Adressen | passive Restore-Tabs verlangen Useraktion; pending angeforderte URL bleibt im Session-Snapshot | Native Restore-/Persistenztest vorbereitet |
| Repeat-One konnte nach Hauptvideo-Ende einen noch laufenden Nebenplayer neu starten | konkreter Medien-ID-Restart im ursprünglichen Frame, kein anderer/neuer Player und keine Timerstop-Umgehung | Zwei ausführbare JS-Regressionen |
| Favoritcurrent übernahm URL-Userinfo in Bibliothek/Widget/Siri | gemeinsame StoredAddress-Grenze entfernt User/Pass; bestehende Seiten werden normalisiert, Snapshots/Deep-Links erneut bereinigt | Native Persistenz-/DeepLink-Test vorbereitet |

Any-playing-Bridge-Tests bestätigen, dass die Audiositzung nicht schon nach Pause des ersten von mehreren Playern freigegeben werden muss. Swift-Syntax ersetzt keine Apple-SDK-Typprüfung; neue Hilfsfunktionen wurden zusätzlich auf Returns/Optional-Unwrapping gelesen.

## Entfernung am 15.10.2026

- Native Medien-Downloads samt Downloader, UI, Dateiverwaltung, Tests nur dafür und Entwicklerflags entfernt. Bereits gespeicherte Nutzerdateien werden nicht angerührt.
- SponsorBlock vollständig entfernt: API, Datenmodell, Abfragen/Tasks, Preferences, Allowlist, Segment-/Skip-/Undo-Brücke, UI, spezifische Tests und Browsing-History-Deklaration.
- Google Cast vollständig entfernt: SDK-Pfad, Podfile, Status-/Receiversteuerung, Netzwerkberechtigungen, lokale Prüfflag und direkte Medien-URL-/MIME-Ausleitung. AirPlay bleibt eine öffentliche iOS-Systemfunktion.
- StevenBlack-Preset auf Neuinstallation und beim Preferences-Upgrade entfernt; lokale/eigene Quellen bleiben erhalten. Alte Filtercaches werden nicht weitergeladen. Dienstspezifische YouTube-Ad-Endpunkte entfernt; generische Filter-/Ausnahme-/Chunk-Prüfungen bleiben erhalten.
- Lokale Markenglyphen durch neutrale Symbole ersetzt; Lizenzen sind in der App erreichbar. Rechtsquellen und verbleibende Bedingungen: [COMMERCIAL-USE.md](COMMERCIAL-USE.md).

Keine Behauptung einer vollständigen rechtlichen Freigabe oder eines bestandenen Apple-Gerätetests.
