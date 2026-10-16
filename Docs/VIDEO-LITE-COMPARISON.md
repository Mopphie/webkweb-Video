> Historischer Stand vor dem umfassenden lokalen Audit vom 16.10.2026. Aktuelle Produkt-, Rechte- und Testaussagen: [APP_AUDIT.md](APP_AUDIT.md), [FEATURE_MATRIX.md](FEATURE_MATRIX.md), [TEST_REPORT.md](TEST_REPORT.md), [RELEASE_BLOCKERS.md](RELEASE_BLOCKERS.md). Frühere Build-/Freigabeangaben gelten nicht für den neuen lokalen Stand.

# Video-Lite-Vergleich und kurzer Funktionsaudit

Die Liste enthält Wünsche sowie Beschwerden über eine andere App. Daraus folgen keine bereits beobachteten WebKWeb-Gerätefehler. Umsetzung und Grenzen werden anhand des eigenen Codes eingeordnet. Die minimale Liquid-Glass-Startseite bleibt erhalten; neue Funktionen liegen im Menü/Player/Settings.

| Bereich aus der Liste | Stand in DevnTube | Einordnung |
| --- | --- | --- |
| Instabile PiP / Background / Seek ohne Ton | PiP/AirPlay/AudioSession und Unterbrechungen vorhanden; Auto-PiP-Versuch neu, Seek/Restart erhält Mute/Volume/Rate | iOS/Player können PiP oder Background verhindern; keine Auto-Unmute-Reparatur |
| Schwarzer Player / Buffering | waiting/stalled/error werden nativ angezeigt; expliziter Wiederholversuch mit Stop-Latch | Decoder/DRM/Netz/Website kann die App nicht reparieren; ggf. Webseite neu laden |
| Nur 360p / Cast 1080p / Apple TV | tatsächliche Quelldimension sichtbar; AirPlay behält die aktuelle Quelle | Qualität im Webseitenplayer wählen; ohne passende Quelle kein erzwungenes 1080p oder eigener YouTube-Stream |
| Audio / automatische Synchronfassung | HTML-audioTracks-Auswahl und Original-Präferenz neu | nur ausdrücklich als Original markierte öffentliche Spur; YouTube-interne Dub-Setter werden nicht verwendet |
| Repeat / Shuffle / ganze Playlist | lokale URL-/Favoriten-Queue neu, vollständige Permutation pro Zyklus; Repeat Aus/Ein/Alle; Audio und Video | umfasst sämtliche lokalen Queue-Einträge, liest keine YouTube-Playlist aus |
| Next / Previous / CarPlay / Anrufe | Queue-Next/Previous in UI und MPRemoteCommandCenter, Audio-Reaktivierungs-/Timer-/Revisionguard vorhanden | öffentliche Medienbefehle, keine eigene zertifizierte CarPlay-Oberfläche/Entitlement |
| Musikqueue / Mixing | dieselbe Queue unterstützt primäre HTML-Audioplayer und Videos | keine zuverlässige Crossfade-/Mix-Engine für fremde Webseiten oder YouTube |
| Untertitel im Vollbild / Englisch | Auswahl vorhandener HTML-textTracks, einschließlich englischer Spur, und Aus neu | keine Übersetzung; Webseiten-Overlay-Untertitel und fehlende Tracks bleiben Player-Sache |
| Vollbild separat von PiP | getrennte Buttons/APIs neu | native WebKit-Presentation-/Fullscreen-Unterstützung erforderlich |
| Auto-PiP beim Verlassen | opt-in, nur laufendes Video, kein Timerstop, keine Änderung von Mute/Volume | best effort; Programmatic-PiP/User-Gesture-/Background-Regeln von iOS |
| Shorts abschalten | opt-in DOM-Ausblendung plus echte YouTube-Route-/SPA-Sperre neu | konservative bekannte Elemente; unbekannte Layouts können weitere Kurzvideo-Kacheln zeigen |
| Links im Hintergrund | WK-Link-Longpress und Bibliothekskontextmenü neu | Auswahl bleibt erhalten; neue Hintergrund-Tabs verlangen Medien-Useraktion |
| Downloads | vollständig aus allen Konfigurationen entfernt | keine belegte Drittquellen-Autorisierung; bestehende Nutzerdateien bleiben unangetastet |
| SponsorBlock | vollständig entfernt | kommerziell nicht passende NC-Daten/API-Lizenz; keine verdeckte Alternative |
| Werbung / Abos / Restore-Käufe | Netzwerkfilter bereits vorhanden; keine Abos oder In-App-Käufe in diesem Projekt | keine Restore-Purchases-Funktion nötig; kein Versprechen für vollständige Werbefreiheit |
| Google Cast / TV / Mac | Google-Cast-SDK und Medienlink-Ausleitung vollständig entfernt; Apple AirPlay bleibt | nötige Cast-Registrierungs-/Inhaltsvoraussetzungen nicht belegt; keine native Mac-App |
| AirPlay / Autorotate / Regressionen | native Routen und Portrait/Landscape-Konfiguration vorhanden; bestehende Tests erweitert | tatsächliche Rotation/AirPlay-Hardware offen; kein Softwarebeweis für alle TV-Routen |
| Grau / Crash / hohe CPU | DOM-Caching, Mutationserfassung und gedrosselte Heartbeats neu | weniger Abfragen im Harness bestätigt; reale CPU/Batterie/Crashes benötigen Instruments/Gerät |
| YouTube-Login / Timeout | normaler WKWebView/Cookies, Fehleranzeige/Reload/private Store vorhanden | keine Umgehung von eingebettetem OAuth, Serverlimits oder Service-Login-Richtlinien |
| Support | statische Support-/Privacy-/Betreiberfelder im App-Bundle vorhanden | öffentliche Angaben sind konfiguriert; Abgleich mit finalem Build offen |

## Im kurzen Audit korrigiert

- Reale Eventfolge pause/timeupdate vor ended konnte den primären Player durch einen Nebenplayer ersetzen. Die Bridge hält die primäre ID bis zum bestätigten Endevent fest. Video-Ende zählt zuerst den Sleep-Timer; erst danach darf die verwaltete Queue weiterlaufen. Audio löst nur Queue-Ende aus.
- Queue-Repeat nutzt Endereignisse statt HTML-loop, damit N-Video-Timer weiter zählen. Die ursprüngliche Loop-Einstellung wird bei Freigabe zurückgesetzt. UUIDs und Verlauf überstehen Entfernen/Verschieben; Shuffle-off nimmt die ursprüngliche Reihenfolge wieder auf. Ein Shuffle-Zyklus enthält alle Queue-Einträge ohne zufällige Nachbar-Auswahl.
- Manuelles Pause/Stop und Audio-Routenunterbrechungen setzen die Autoplay-Sperre und verhindern unerwartetes Queue-Fortsetzen. Queue-Ende wird nur im verwalteten Tab verarbeitet.
- Hintergrund-Tabs wechseln die Auswahl nicht und verlangen eine Player-Useraktion. Die Bridge durchsucht nicht bei jedem State/Tick das gesamte Dokument; Mutationen ergänzen den Node-Cache, entfernte Elemente werden bereinigt. Sichtbare offene Shadow Roots erhalten eine seltene Nachsuche.
- In-App-Datenschutztext wurde auf gewählte Suchmaschine, mehrere Quellen, Queue aktualisiert; entfernte Integrationen werden nicht mehr als Datenempfänger geführt.

## Validierung

Ausgeführt am 15.10.2026 in Linux: 40/40 Node-Tests mit originaler Playback.js/WatchPresentation.js, darunter primäre End-Reihenfolge, Audio/N-Video-Abgrenzung, Replay, Mute/Volume/Rate, Loop/Quellenwechsel, Caption/AudioTrack-Auswahl, Auto-PiP-Gates, Shorts-Hostprüfung, Buffering und DOM-/Background-Abfragezahl. Das ist ein DOM-Harness, kein WebKit-/Gerätetest. 24 Swift-Dateien mit Tree-sitter syntaxgeprüft; Plists/Entitlements/Manifeste/JSON/YAML/Ressourcen/Shell/Python geprüft.

Vorbereitet, nicht ausgeführt: 34 XCTest-Definitionen einschließlich Queue-Permutation/Repeat/Shuffle-off/Reorder/Persistenz, Filterchunking/Ausnahmen, Quellenmigration, Timer, Datenlöschung, Dialoge und Favoriten. Mac: `./Scripts/check-macos.sh`.

Offen: Apple-SDK-Typprüfung/XcodeGen, XCTest, Simulator-UI, echte Media/Background/PiP/AirPlay/Rotation/Remote-Befehle sowie Instruments. Signierung/App Groups/CloudKit und Abgleich der öffentlichen Rechteseite bleiben gesondert erforderlich. [Kommerzielle Prüfung](COMMERCIAL-USE.md). Keine garantierte App-Store-Zulassung.

Keine Actions gestartet, keine Actions-Minuten und kein Merge. Der vorhandene Workflow bleibt manuell auslösbar und wird nicht ausgeführt.
