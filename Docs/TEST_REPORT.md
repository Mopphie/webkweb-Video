# Testbericht — 16.10.2026

**Aktueller TestFlight-Auftrag:** Teilen-Erweiterung entfernt; signiertes App-/Widget-Release **0.1.0 (6)** erfolgreich archiviert/exportiert/geprüft/hochgeladen und von Apple mit **VALID / IN_BETA_TESTING** bestätigt. Run [38919948219](https://github.com/Mopphie/webkweb-Video/actions/runs/38919948219): **67/67 native, 3/3 Browser-UI ohne Wiederholung und unabhängige iPad Vollbild/Queue/Suche bestanden**. Bei technisch geprüfter Releasegleichheit wiederverwendet. Run [38932003655](https://github.com/Mopphie/webkweb-Video/actions/runs/38932003655): **vollständige native Vollbild/PiP/echter Appwechsel/Systemrückkehr/Queue/nächstes Video/Suche bestanden**, kein Skip/Retry, eigener endlicher 600-s-Film. Kein aktueller Plattform-/physischer Gerätetest. Chronologie, konkrete Fehlversuche, SHA-/Tree-Zuordnung und Abschluss A–J: [TESTFLIGHT_STATUS.md](TESTFLIGHT_STATUS.md).

Aktuelle lokale Prüfungen nach Share-Entfernung und Tipp-Fix: **31/31 Foundation**, **55/55 Node**, **14/14 Python-Helfermocks**, **19/19 echte Chromium-Mediendecoderfälle** (nur eigene Loopback-Testmedien). Neuer Overlay-Tipp-Fall scheitert mit dem alten und besteht mit dem korrigierten JS. Keine YouTube-/AirPlay-/physischen Gerätetests daraus ableiten.

**Die folgenden Tabellen und „nicht ausgeführt“-Angaben sind die historische lokale Audit-Baseline vor den späteren CI-Aufträgen.** Damals waren kein iOS-Build/Simulatorlauf/signiertes Archiv/Upload dieses neuen Standes ausgeführt. Historische Build-5-/49-Simulatortests sind kein Nachweis späterer Änderungen. `Evidence/file-inventory.json` dokumentiert die damalige Inventarisierung; aktuelle CI-Nachweise siehe oben. Lokale Rohberichte bleiben unter ignoriertem `build/reports`.

## Tatsächlich ausgeführt

| Prüfung | Ergebnis / echte Aussage | Reproduktion / Rohdatei |
|---|---|---|
| Swift-Foundation-Modelle mit echtem Compiler/XCTest | **31/31 bestanden**, 0 Fehler. Swift 6.1.3 Linux, Sprachmodus 5. URL-/Token-/Fragment-/OAuth-Schranken, Such- und Deeplinks, Fähigkeiten/Plattformframes, Navigationsgrenzen, Queueordnung/Shuffle/Repeat/Duplikate, Sleep-Deadline/Overflow/End-Dedupe, JSON-Version/IDs/Playlist-Merge/Notizenreferenzen/Settings, Snapshotfreigabe und Share-Inbox-Verfall | `./Scripts/check-core.sh`, `swift-core-tests.log` / `audit-core.log`. Offizielles Image `swift:6.1@sha256:6e43114610e161e38ad41636ebcafd6940dc67dfab355eace3a0ca100b2263db`; `--network none`, keine Paketabhängigkeiten |
| Swift-Parser über sämtliche App-/Shared-/Widget-/Share-/Unit-/UI-Swiftdateien | **42 Dateien syntaxgeprüft**, keine Parsefehler. Keine SwiftUI-/Apple-SDK-Typprüfung oder Verlinkung! `Package.swift` zusätzlich als SwiftPM-Manifest tatsächlich kompiliert | Compiler-Parser im Corehelfer; letzte zusätzliche Syntaxprüfung `swift-syntax-final.log` nach Ergänzung der iOS-Testfälle |
| Node-Tests der tatsächlichen gebündelten JS-Brücke + Sicherheits-/Entfernungsschranken | **52/52 bestanden**, 0 Fehler. Play-/Stop-/Input-/Frame-/Shadow-/End-/State-/Bufferingverhalten sowie Abwesenheit der entfernten Netzwerk-/CSS-/PiP-/SDK-Pfade | `python3 Scripts/check-portable.py`, `node-tests.tap`, `audit-portable.log` |
| Echter HTML-Mediendecoder Chromium 154.0.8037.57 | **18/18 bestanden** mit eigenen lokal erzeugten H.264/AAC-Medien, Loopbackserver. Play/Pause/Seek/Rate/Spuren, Shadow-/Frame-/SPA-/Sourcewechsel, Fehler/Ende, Stoplatch, Fullscreen oder klarer Fehler, keine erzwungenen Webrouten, gepufferter Stall und echte segmentierte Streamstarvation/Pause/Resume | `python3 Scripts/check-browser.py`; `browser-check.json`, `audit-browser.log`. Aktuelle `Playback.js`-SHA-256 entspricht exakt dem Testbericht |
| Plists / Privacy-Manifests / Projekt | 6 plist/xcprivacy-Dateien parsebar, App-/Widget-/Share-App-Groups gleich, keine Cloud-Entitlements, YAML/IDs/Deployment parsebar, alte Downloader/SponsorBlock/Cast-Quellen und Flags fehlen | `portable-check.json`; XcodeGen/Provisionierung dadurch **nicht** nachgewiesen |
| Signier-/ASC-Helferlogik | **14/14 Mocktests bestanden**, keine Apple-Anfrage, kein Signieren/Upload. Drei getrennte Profile, Bundle-/Build-/Versionsübereinstimmung und fehlende ShareExtension werden mit Mock-Profilen/-IPAs geprüft. Dies prüft keine echte ShareExtension-Provisionierung und rechtfertigt keinen Upload | `python3 -m unittest discover -s Scripts/Tests -v`; `audit-release-helper-tests.log` |
| Eigenes Icon / Git-Hygiene | Geometrischen Generator ausgeführt: 1024×1024 RGB-PNG, 7.496 Bytes, keine fremden Eingabebilder/Fonts. `git diff --check` nach Whitespacekorrektur sauber; keine Buildberichte/Useraufnahmen gestaged | `Scripts/generate-app-icon.py`; Inventar mit Dateihashes, lokaler Gitstatus |
| Kontakt-/Releasekonfiguration | **BLOCKIERT**, nicht „bestanden“: `WebKWebOperatorContact` bewusst leer, weil Betreiber noch unbestätigt. Öffentliche URL-Inhalte nicht aktualisiert | Portable-Check und R05 |

Portable-Check meldet „Swift syntax NOT_RUN“, wenn lokal kein `swift-frontend` im PATH liegt. Die getrennte tatsächliche Container-Parserprüfung oben ergänzt diesen Befund; sie macht daraus keinen iOS-SDK-Build. Ebenso ist „0 Tests“ am Ende des Swift-Testing-Runners keine Gesamtsumme: die XCTest-Suite davor führte 31 Tests erfolgreich aus.

## Relevante Fehlerversuche und Korrekturen

- Erster Node-Lauf nach gezielter Entfernung hatte vier veraltete Erwartungen an Auto-Originalaudio, Forced-PiP und Shorts-Umleitung. Diese Funktionsprüfungen wurden durch Tests der tatsächlich beabsichtigten manuellen Trackwahl/Abwesenheit der ausgeschlossenen Wege ersetzt; keine weiterhin nötigen Tests heimlich deaktiviert.
- Erste Swift-Compilation fand eine alte `allowlist`-Testreferenz. Danach erwarteten zwei Assertions noch die frühere stille Entfernung von URL-Credentials. Neue Grenze weist solche URLs ausdrücklich ab; Test auf Ablehnung und sichere Snapshots korrigiert.
- Wiederverwendung eines SwiftPM-Buildverzeichnisses in frischen Wegwerfcontainern lieferte „unknown build description“. Reproduzierbarer Helfer bereinigt ausschließlich sein eigenes generiertes Scratch-Verzeichnis vor dem Lauf. Anschließender aktueller 31er-Lauf erfolgreich. Keine Repository-/Nutzerdateien zurückgesetzt.
- Eine kleine echte Swift-Typprüfung eines isolierten Sprachbeispiels fand einen MainActor-Zugriff auf einen `@Published`-Getter im Deinitializer. NativePlayer verwendet für die Observerbereinigung nun eine direkte gespeicherte Referenz auf denselben Player; das ersetzt weiterhin keine Apple-SDK-Typprüfung.
- Whitespaceprüfung fand eine Leerraumzeile und zwei zusätzliche EOF-Leerzeilen; behoben.

## Baseline vor dem TestFlight-Auftrag — damaliger nativer Teststand

**65 Unit-/WK-/AV-/Persistenztestdefinitionen** im iOS-Testtarget, davon 31 reine Foundationfälle auch unter Linux ausgeführt; **0/65 unter iOS ausgeführt**. Dazu **4 XCUITest-Fälle**, ebenfalls nicht ausgeführt.

- `BrowserIntegrationTests`: nicht persistente Stores/Popupidentität, private Diagnose, normale Session ohne private/credential Daten, ruhiger Restore, committed URL/Reload, Dialogqueue, Wipe/Blank-Commit, Intents/Sleep.
- `MediaPlaybackIntegrationTests`: echte eigene WK-Clipwiedergabe, Stop/Resume/Buffering, eingefügte Player, Unterbrechungs-/Timerzustände und unveränderter Watch-DOM/Rückweg. Eingespritzte AV-Benachrichtigungen sind keine Telefon-/Bluetooth-Gerätetests.
- `LibraryPersistenceTests`: echte atomische Dateien/Importfehler, unveränderte defekte Originaldaten, kein Bookmark-/History-/Lockexport, gezieltes Fortschrittlöschen mit Erhalt eigener Notizen/Listen.
- `NativePlayerTests`: eigener echter AV-Clip mit Medienzeitfortschritt, Miniplayer/Pause/Resume ohne Playerkopie, fehlende Datei/Queuefehler, Dedupe/Websiteausschluss, öffentliche Hintergrundrichtlinie und definierter Media-Services-Reset. Der Resetfall prüft den Codepfad, keinen echten OS-Reset.
- `ComplianceMigrationTests`: echte eigene WK-Regel kompilieren, Upgradebereinigung abwarten, alte Preferences entfernen und unabhängigen Nutzerimport erhalten; **nur Testcode** kompiliert Regeln.
- `WorkspacePrivacyTests`: neuer Favorit ohne erfundenen Historybesuch, Privatende ohne geschlossene private Tabs/Snapshot, Tablimit/Startausweg, normale Pins/Gruppenwiederherstellung, privater Popup mit persistentem Fremdkonfigurationsversuch, WebContent-Fehlerzustand und Plattformkontrollen.
- `BrowserActionsUITests`: Aktions-Sheet im laufenden eigenen WK-Video, normaler sichtbarer Watch-Rückweg, erster realer UIKit-Touch nach Stop, hörbarer eigener Clip mit tatsächlicher Medienzeitmessung.
- `NativePlaybackJourneyUITests`: **Pflichtreise** eigenes Video → Vollbild → zurück → System-PiP → Home/andere App → zurück → Queue → nächstes Video → Suchfeld. Echte PiP-Unterstützung und fortschreitende Zeit erforderlich; kein Fallback-Pass, kein YouTube-Beleg.

Die Pflichtreise und ihre System-Accessibility-Labels müssen auf einem tatsächlich unterstützten Gerät/Simulator abgenommen werden. Ohne ausgeführten Test werden weder Lautsprecherwiedergabe noch PiP-Zuordnung, AirPlay oder zuverlässige Hintergrundlaufzeit als bestanden bezeichnet.

## Verbindliche zusätzliche Geräte-/Fehlermatrix

Alle folgenden Fälle **NICHT AUSGEFÜHRT**; Erwartung ist reproduzierbar definiert:

| Fall | Erwarteter Nachweis |
|---|---|
| Schnelle Tabwechsel / aktiven Tab schließen / ohne Historie / Tablimit | Navigation bleibt erreichbar; geschlossener Player endet, keine zweite Tonquelle; nur normale geschlossene Tabs wiederherstellbar |
| Privatende / Appneustart / normale/private Popups | Keine private URL/Titel/Position in SwiftData, eigener JSON-Datei, UserDefaults, Group, Widget, Intent, Export oder Diagnose; nicht persistenter Store; keine private Wiederherstellung |
| WLAN↔Mobilfunk / offline / Serverfehler | Verständlicher Fehler, bedienbarer Retry/Abbruch, kein stiller Filter-/Schutzwechsel oder Endlosschleifen-Weiterlauf |
| Kopfhörer/Bluetooth abziehen / echte Unterbrechung / Audio-Service-Reset | Pause nach Routenverlust, passende Wiederaufnahme nur ohne neuen Nutzerstop/abgelaufenen Timer; bei Reset bewusster Retry mit ersetztem ungültigem AVPlayer |
| Gerätesperre / andere App / PiP / AirPlay | Eigene native berechtigte Medien nach Systemmöglichkeiten; Quelle/Medienzeit/Route korrekt, Timer tatsächlich prüfen. Private Websites pausieren und publizieren keine App-Metadaten |
| WebContent-Abbruch | Zustandswerte/Frames leeren, klare Reloadmöglichkeit, Browsernavigation bleibt |
| Alte Installation / WK-Regeln / SwiftData-Migration | Alte Integrationskeys/-caches/-WK-Listen weg oder sichtbarer Retry bei Fehler, niemals erneut angewendet. Neues isHistory-Default migriert ohne Verlust normaler Favoriten; importierte eigene Dateien erhalten |
| Import / beschädigter Speicher / Storage full / verschobene Datei | Validierung vor Merge, vorhandene Daten erhalten/Rollback, keine Cookies/privaten Daten; Datei neu verknüpfen; kein unechter Speichererfolg |
| Widgets / Siri / ShareExtension / Sperre | Opt-in und aktuelle Freigabe respektiert, gesperrte Appaktion blockiert, kein Privatinhalt, abgelaufene Sharelinks weg; Extension-Provisionierung gesondert |
| iPhone / iPad / Rotation / kleine Fenster / große Schrift | Player/Queue/Tabs und sichtbare Rückwege bedienbar; VoiceOver-/Keyboard-/Kontrast-/Reduce-Transparency-/Reduce-Motion-Abnahme ohne Videofarbänderung |
| Aktuelles YouTube / Twitch / TikTok / Rumble | Echte Website unter realem Account/Region testen. Lokaler HTML-Player und Safari-Build-4-Beobachtung sind kein Beleg des aktuellen Dienstbetriebs |

## Historische lokale Audit-Baseline: Externe Aktionen / Kosten

0 neue GitHub-Actions-Läufe/CI-Minuten, keine Cloud-Macs, keine Remote-Pushes/PRs, keine Apple-Konto-/Produkt-/Vertragsänderungen, kein TestFlight-/Storeupload, keine bezahlten API-/Lizenz-/Abo-Buchungen. Nur lesender Git-Fetch, öffentliche Primärquellen/Webrecherche, öffentlicher Swift-Toolchain-Download und lokale Tests/Commits. Nachträgliche CI-Minutenfreigabe wurde nicht für einen alten, den lokalen Code nicht prüfenden Uploadworkflow missbraucht.

## UI-Nachtrag: schmale Website-Medienleiste (2026-10-16)

- `App/BrowserView.swift`: mehrzeiliges Zusatzpanel durch eine 44 pt hohe Zeile mit kleinen Play/Pause-/Optionssymbolen und einer 2 pt starken Fortschrittslinie ersetzt. Keine sichtbaren Text-, Lautstärke- oder Gestenflächen in dieser Leiste. Die Symbole behalten 44 × 44 pt große Tippflächen.
- Weitere Funktionen bleiben im Browsermenü beziehungsweise Player-Sheet. Ladezustand und Fehler belegen keine zusätzliche Zeile; das Optionssymbol zeigt sie an und öffnet die vorhandene Fehlerhilfe. Die Quellenbeschränkungen bleiben erhalten, insbesondere keine eigene Zusatzsteuerung bei YouTube. WebView, Player und Wiedergabelogik wurden nicht geändert.
- **Ausgeführt:** Swift-6.1-Syntaxprüfung der geänderten Datei im bereits vorhandenen lokalen Container (`swiftc -frontend -parse App/BrowserView.swift`, Netzwerk deaktiviert): Exit 0. `git diff --check`: Exit 0. Quellprüfung der weiterhin erreichbaren erweiterten Bedienelemente und der unveränderten Quellenbeschränkung.
- **Nicht ausgeführt:** SwiftUI-Typprüfung, iOS-Build und visuelle/VoiceOver-/Rotationstests auf Simulator oder Gerät; weiterhin kein Xcode verfügbar. Dieser Nachtrag behauptet keine erneute Ausführung der vorherigen Testsuiten. Keine CI, kein Push und kein TestFlight-Upload für diese UI-Änderung.
