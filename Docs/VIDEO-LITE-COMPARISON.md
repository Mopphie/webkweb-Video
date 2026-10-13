# Video-Lite-Vergleich und kurzer Funktionsaudit

Die Liste enthält Wünsche sowie Beschwerden über eine andere App. Daraus folgen keine bereits beobachteten WebKWeb-Gerätefehler. Umsetzung und Grenzen werden anhand des eigenen Codes eingeordnet. Die minimale Liquid-Glass-Startseite bleibt erhalten; neue Funktionen liegen im Menü/Player/Settings.

| Bereich aus der Liste | Stand in WebKWeb | Einordnung |
| --- | --- | --- |
| Instabile PiP / Background / Seek ohne Ton | PiP/AirPlay/AudioSession und Unterbrechungen vorhanden; Auto-PiP-Versuch neu, Seek/Restart erhält Mute/Volume/Rate | iOS/Player können PiP oder Background verhindern; keine Auto-Unmute-Reparatur |
| Schwarzer Player / Buffering | waiting/stalled/error werden nativ angezeigt; expliziter Wiederholversuch mit Stop-Latch | Decoder/DRM/Netz/Website kann die App nicht reparieren; ggf. Webseite neu laden |
| Nur 360p / Cast 1080p / Apple TV | tatsächliche Quelldimension sichtbar; Cast/AirPlay behalten die aktuelle Quelle | Qualität im Webseitenplayer wählen; ohne passende Quelle kein erzwungenes 1080p oder eigener YouTube-Stream |
| Audio / automatische Synchronfassung | HTML-audioTracks-Auswahl und Original-Präferenz neu | nur ausdrücklich als Original markierte öffentliche Spur; YouTube-interne Dub-Setter werden nicht verwendet |
| Repeat / Shuffle / ganze Playlist | lokale URL-/Favoriten-Queue neu, vollständige Permutation pro Zyklus; Repeat Aus/Ein/Alle; Audio und Video | umfasst sämtliche lokalen Queue-Einträge, liest keine YouTube-Playlist aus |
| Next / Previous / CarPlay / Anrufe | Queue-Next/Previous in UI und MPRemoteCommandCenter, Audio-Reaktivierungs-/Timer-/Revisionguard vorhanden | öffentliche Medienbefehle, keine eigene zertifizierte CarPlay-Oberfläche/Entitlement |
| Musikqueue / Mixing | dieselbe Queue unterstützt primäre HTML-Audioplayer und Videos | keine zuverlässige Crossfade-/Mix-Engine für fremde Webseiten oder YouTube |
| Untertitel im Vollbild / Englisch | Auswahl vorhandener HTML-textTracks, einschließlich englischer Spur, und Aus neu | keine Übersetzung; Webseiten-Overlay-Untertitel und fehlende Tracks bleiben Player-Sache |
| Vollbild separat von PiP | getrennte Buttons/APIs neu | native WebKit-Presentation-/Fullscreen-Unterstützung erforderlich |
| Auto-PiP beim Verlassen | opt-in, nur laufendes Video, kein Timerstop/Cast, keine Änderung von Mute/Volume | best effort; Programmatic-PiP/User-Gesture-/Background-Regeln von iOS |
| Shorts abschalten | opt-in DOM-Ausblendung plus echte YouTube-Route-/SPA-Sperre neu | konservative bekannte Elemente; unbekannte Layouts können weitere Kurzvideo-Kacheln zeigen |
| Links im Hintergrund | WK-Link-Longpress und Bibliothekskontextmenü neu | Auswahl bleibt erhalten; neue Hintergrund-Tabs verlangen Medien-Useraktion |
| Downloads | direkte HTTPS-Audio-/Videodateien: Cancel/Retry/Share/Delete, sichere Dateinamen, Status/MIME-Prüfung neu | keine Login-Cookies, DRM/blob/MSE, HLS/DASH-Playlist-Extraktion; foreground, kein garantierter Stop/Kill-Resume |
| SponsorBlock | bereits vorhanden: Kategorien, iframe/SPA, Allowlist, Skip/Undo | Communitydaten und Dienstverfügbarkeit |
| Werbung / Abos / Restore-Käufe | Netzwerkfilter bereits vorhanden; keine Abos oder In-App-Käufe in diesem Projekt | keine Restore-Purchases-Funktion nötig; kein Versprechen für vollständige Werbefreiheit |
| Cast nur Audio / Duration / TV / Mac | echte Session/Remote Controls, Status/Fehler, MIME/currentSrc, Position/Dauer vorhanden | Receiver/Codec/Netz/DRM/Berechtigung prüfen; keine native Mac-App, Mac-Routen nur soweit angeboten |
| AirPlay / Autorotate / Regressionen | native Routen und Portrait/Landscape-Konfiguration vorhanden; bestehende Tests erweitert | tatsächliche Rotation/AirPlay-Hardware offen; kein Softwarebeweis für alle TV-Routen |
| Grau / Crash / hohe CPU | DOM-Caching, Mutationserfassung und gedrosselte Heartbeats neu | weniger Abfragen im Harness bestätigt; reale CPU/Batterie/Crashes benötigen Instruments/Gerät |
| YouTube-Login / Timeout | normaler WKWebView/Cookies, Fehleranzeige/Reload/private Store vorhanden | keine Umgehung von eingebettetem OAuth, Serverlimits oder Service-Login-Richtlinien |
| Support | konfigurierbare echte Support-/Privacy-/Betreiberfelder vorhanden | öffentliche Angaben sind auf Nutzerwunsch noch offen |

## Im kurzen Audit korrigiert

- Reale Eventfolge pause/timeupdate vor ended konnte den primären Player durch einen Nebenplayer ersetzen. Die Bridge hält die primäre ID bis zum bestätigten Endevent fest. Video-Ende zählt zuerst den Sleep-Timer; erst danach darf die verwaltete Queue weiterlaufen. Audio löst nur Queue-Ende aus.
- Queue-Repeat nutzt Endereignisse statt HTML-loop, damit N-Video-Timer weiter zählen. Die ursprüngliche Loop-Einstellung wird bei Freigabe zurückgesetzt. UUIDs und Verlauf überstehen Entfernen/Verschieben; Shuffle-off nimmt die ursprüngliche Reihenfolge wieder auf. Ein Shuffle-Zyklus enthält alle Queue-Einträge ohne zufällige Nachbar-Auswahl.
- Manuelles Pause/Stop und Audio-Routenunterbrechungen setzen die Autoplay-Sperre und verhindern unerwartetes Queue-Fortsetzen. Queue-Ende wird nur im verwalteten Tab verarbeitet; bei Cast werden Browserqueue-Next/Previous deaktiviert.
- Downloads verschieben URLSession-Tempdateien noch im Callback nach UUID-Staging. Attempt-IDs verhindern alte Cancel/Retry-Callbacks; MIME/Status und sichere Namen verhindern Login-HTML und Pfad-Traversal als vermeintlichen Download. Kein FileTimestamp-API-Aufruf nur für Größenmessung.
- Hintergrund-Tabs wechseln die Auswahl nicht und verlangen eine Player-Useraktion. Die Bridge durchsucht nicht bei jedem State/Tick das gesamte Dokument; Mutationen ergänzen den Node-Cache, entfernte Elemente werden bereinigt. Sichtbare offene Shadow Roots erhalten eine seltene Nachsuche.
- ATS bleibt für native Requests aktiv. HTTP wird nur in WebKit erlaubt; Downloadoptionen werden deshalb nur für HTTPS-Dateien angeboten, ohne bekannten HTTP-ATS-Fehlschlag.
- In-App-Datenschutztext wurde auf gewählte Suchmaschine, mehrere Quellen, Queue und ausdrücklich gespeicherte Downloads aktualisiert.

## Validierung

Ausgeführt in Linux: 35/35 Node-Tests mit originaler Playback.js, darunter primäre End-Reihenfolge, Audio/N-Video-Abgrenzung, Replay, Mute/Volume/Rate, Loop, Caption/AudioTrack-Auswahl, Auto-PiP-Gates, Shorts-Hostprüfung, Buffering und DOM-/Background-Abfragezahl. Das ist ein DOM-Harness, kein WebKit-/Geräte-Test. 23 Swift-Dateien syntaxgeprüft; Plists/Manifeste/YAML/Ressourcen/Shell/Python geprüft.

Vorbereitet, nicht hier ausgeführt: 29 XCTest-Definitionen einschließlich vollständiger Queue-Permutation/Repeat/Shuffle-off/Reorder/Persistenz sowie MIME-/Filename-Validierung. Mac-Prüfpfade bleiben `./Scripts/check-macos.sh` und `./Scripts/check-macos.sh --cast`.

Offen: Swift-Typprüfung/XcodeGen/Apple-SDK, XCTest, Simulator-UI, echter Download-/Retry-/Suspend-Verlauf, Media/Background/PiP/AirPlay/Rotation/CarPlay-Befehle und Cast/TV sowie Instruments. Signierung/App Groups/CloudKit-Provisionierung und echte öffentliche Betreiberangaben bleiben extern erforderlich. Keine garantierte App-Store-Zulassung.

Keine GitHub Actions oder Workflows eingerichtet/ausgeführt, keine Actions-Minuten, kein Merge in main.
