# DevnTube (internes Xcode-Ziel: WebKWeb)

Nativer Video-Browser für iPhone und iPad mit SwiftUI, WKWebView und SwiftData, ab iOS/iPadOS 17. Deutsche Oberfläche; Debug/XCTest und Release-Simulatorbuild geprüft, reale Geräte-/Diensteprüfungen stehen noch aus.

Die schwarze Startseite zeigt eine Suchpille, YouTube/Twitch/TikTok/Rumble und Favoriten/Verlauf/Timer/Einstellungen. Alle acht Startseiten-Icons sind schlichte lokale Glyphs ohne Glass-/Materialflächen oder Randblasen. Die transparente Trefferfläche bleibt groß; Suchpille und funktionale Browserbuttons behalten ihr Material. Lokale Icons erzeugen keine Favicon-Anfragen. Mit iOS-26-SDK/Compiler 6.2 nutzt die Oberfläche Liquid Glass, sonst Systemmaterial. Transparenz reduzieren, große Schrift und iPad erhalten eigene Layoutanpassungen.

## Funktionen

- URL oder Suche mit Google, DuckDuckGo oder Bing; `canOpenURL`, Zurück/Vorwärts, Teilen, Popup-Tabs und normale Tab-Wiederherstellung. URLs mit Zugangsdaten werden nicht als Suchbegriff übertragen. Private Tabs verwenden einen eigenen nicht persistenten WebKit-Speicher und erscheinen weder im Verlauf noch im wiederhergestellten Zustand.
- Öffentliche mobile/Desktop-WebKit-Inhaltspräferenz mit echter aktueller Browserkennung und Seitenzoom. Inline/Autoplay/PiP/AirPlay sind konfiguriert. Eine isolierte Bridge steuert HTML-Medien auch in Frames und offenen Shadow Roots; native Play/Pause/Seek, Systemlautstärke und optionale Gestenfläche.
- Mehrteilige WebKit-Netzwerkfilter ohne alphabetische Domainbegrenzung, unverlierbare Basisregeln ohne dienstspezifische YouTube-Ad-Endpunkte. AdGuard DNS und HaGeZi sind auswählbare Quellen; HTTPS-Quellen und Textimport, tägliche Vordergrund-/manuelle Updates, Quellcache, Diagnose und Seiten-Ausnahmen sind vorhanden. Unterstützte AdGuard/EasyList-Netzwerkregeln und Ausnahmen werden konservativ übersetzt; unbekannte Ausnahmen verwerfen die Quelle. Keine Scriptlets oder vollständige EasyList-Kompatibilität.
- Sleep-Timer mit freier Dauer bis 24 Stunden, Anzahl primärer Videos oder Ende des aktuellen Videos. Nach Ablauf verhindert eine lokale Sperre auch Autoplay neu eingefügter Player. Zeit-/Anzahlpläne normaler Tabs werden wiederhergestellt; ein Plan für den alten konkreten Player wird beim Neustart verworfen und gemeldet.
- SwiftData-Verlauf mit abschaltbarer Aufzeichnung und maximal 500 nicht favorisierten Einträgen; Favoriten bearbeiten/sortieren. Geteilte Favoriten werden bei Besuchen, Bearbeitung und iCloud-Änderungen für Siri und das konfigurierbare Widget aktualisiert. Cookie-/Website-Daten-Löschen schließt vorher die aktiven Dokumente.
- Vier App Intents/Siri-Kurzbefehle, Sperrbildschirm-Medienmetadaten, Remote Play/Pause/Stop/Seek und Audio-Unterbrechungsbehandlung. Private Seitentitel erscheinen nicht in Now Playing.
- Optionales CloudKit für Verlauf/Favoriten mit CloudKit-tauglichem Modell. Erst nach Konfiguration eines echten, provisionierten Containers aktivierbar; Umschalten gilt beim Neustart. Private Tabs und Browsersitzungen werden nicht synchronisiert.

## YouTube-Watch-Ansicht

Auf echten YouTube-`/watch?v=...`-Seiten entfällt die App-Adress-/Tab-/Player-/Timer-/Fußleiste. Der echte WKWebView zeigt YouTubes Player, ein-/ausblendbare Controls, Titel, Kanal, Abos, Aktionen, Kommentare und Empfehlungen. Ein deckend roter 44-pt-Menübutton liegt unten rechts innerhalb der Safe Area (14 pt rechts/18 pt unten); Navigation, Adresse, Tabs und App-Funktionen liegen im Menü. Masthead und Playerrahmen werden über begrenzte öffentliche DOM/CSS-Anpassungen gestaltet; die App erzeugt keine eigenen YouTube-Inhaltskarten. Routewechsel per SPA/History/BFCache entfernen oder erneuern die Anpassung. Andere Webseiten behalten ihre Browseroberfläche. YouTube-Layout/A/B-Varianten und reale Apple-Darstellung müssen auf Geräten geprüft werden; keine pixelgenaue Zusage.

Erneuter Funktionsaudit vom 14.10.2026: [AUDIT-FIXES.md](Docs/AUDIT-FIXES.md). HIG-/App-Review-Prüfung und konkrete offene Release-Bedingungen: [APP-REVIEW-DESIGN.md](Docs/APP-REVIEW-DESIGN.md). Öffentlich erreichbare Privacy-/Support-URL und Betreiberkontakt sind statisch über die historisch benannten Schlüssel `WebKWebPrivacyURL`, `WebKWebSupportURL`, `WebKWebOperatorContact` in `App/Info.plist` hinterlegt. Diese Angaben sind nicht vom App-Endnutzer editierbar. Die In-App-Datenschutzhinweise bleiben verfügbar.

## Ergänzungen aus dem Video-Lite-Vergleich

Im Menü erreichbar: lokale URL-/Favoriten-Queue mit vollständigem Shuffle und Repeat Aus/Ein/Alle, Next/Previous über RemoteCommands; Hintergrund-Linköffnung per Longpress. Playeroptionen bieten getrenntes Vollbild/PiP, Geschwindigkeit, verfügbare HTML-Untertitel-/Audiospuren und Buffering-/Fehleranzeige. Auto-PiP, Shorts-Ausblenden und Original-Audio sind optionale Einstellungen. Kein interner YouTube-API-Zugriff oder erfundener 1080p-Schalter.

Native Medien-Downloads, SponsorBlock und Google Cast wurden vollständig aus allen Konfigurationen entfernt. Bereits früher lokal gespeicherte Nutzerdateien bleiben unangetastet. [Entfernung und Prüfpfad](Docs/NO-DOWNLOAD-VARIANT.md); [Kommerzielle Nutzung und Lizenzbedingungen](Docs/COMMERCIAL-USE.md).

Die Bridge verwaltet Medien über Mutationserfassung und cached Nodes; offene Shadow Roots werden sichtbar höchstens alle 15 Sekunden zusätzlich gesucht. Nicht sichtbare Frames senden nur alle fünf Sekunden einen Heartbeat. Diese DOM-/Nachrichtenreduktion wurde im Harness geprüft; tatsächliche CPU/Batterie/CarPlay/TV/Rotation bleiben Gerätetests. Vergleich und kurzer Funktionsaudit: [VIDEO-LITE-COMPARISON.md](Docs/VIDEO-LITE-COMPARISON.md).

## Auf dem Mac starten

Für den aktuellen App-Store-Upload: macOS mit Xcode 26+, iOS-26-SDK, Command Line Tools, XcodeGen und Node.js 18+. Das Mindestziel der App bleibt iOS 17:

```bash
brew install xcodegen node
xcodegen generate
open WebKWeb.xcodeproj
```

Für App und Widget dasselbe Development Team setzen. Die expliziten IDs `de.mopphie.devntube` und `de.mopphie.devntube.favorites` sowie die Gruppe `group.de.mopphie.devntube` sind im Apple-Portal unter Team `HUN9MS832X` registriert; die App-Group-Zuordnung beider Kennungen wurde nach erneutem Öffnen geprüft. Bundle-IDs, beide Entitlements und `FavoriteStorage.groupID` stimmen damit im Quellcode überein. Die App-Store-Profile wurden laut aktuellem Release-Protokoll bereits für den vorherigen TestFlight-Build genutzt. Signierung dieser geänderten Fassung und echte Gerätetests stehen aus.

Für CloudKit eine bereits im eigenen Apple-Konto angelegte Container-ID konfigurieren:

```bash
./Scripts/configure-cloudkit.py --container DEINE_BEREITS_PROVISIONIERTE_ICLOUD_CONTAINER_ID
xcodegen generate
```

Der Parameter muss eine echte `iCloud.*`-ID sein. Das Skript setzt Plist/Entitlements; iCloud-, Push- und App-Group-Capabilities sowie Signierung bleiben im Apple-Portal einzurichten. In den App-Einstellungen anschließend iCloud aktivieren und neu starten. Derselbe lokale SwiftData-Store wird verwendet; beim Ausfall startet die App lokal mit einer Meldung. Vor Produktivnutzung Migration und Zwei-Geräte-Sync prüfen.

## Lokal prüfen

Der TestFlight-Workflow unterstützt manuellen Dispatch und den ausdrücklich beauftragten Release-Branch `codex/testflight-2026-10-16`; normale Entwicklungs-/Main-Pushes laden nichts zu Apple hoch. **Seit 16.10.2026 sind GitHub Actions für Builds und Tests ausdrücklich jederzeit freigegeben.** Der Validierungsworkflow prüft den Entwicklungsbranch ohne Signing oder Upload.

```bash
node --test Tests/*.test.cjs
./Scripts/check-macos.sh
```

Das macOS-Skript generiert das Projekt, wählt einen vorhandenen iPhone-Simulator und führt `xcodebuild test` aus. Ein Simulator lässt sich über `WEBKWEB_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 16'` wählen.

Direkter Standardbuild:

```bash
xcodebuild -project WebKWeb.xcodeproj -scheme WebKWeb -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

Die Simulatorbezeichnung muss auf dem Mac vorhanden sein. Im aktuellen Linux-Prüflauf bestanden 44 Node-Tests mit den originalen Seitenskripten sowie Projekt-/Plistprüfungen und Tree-sitter-Syntaxprüfungen von 25 Swift-Dateien. Zusätzlich bestanden [38/38 native XCTest-Fälle und der Release-Simulatorbuild](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443) mit Xcode 26.6 auf einem iPhone-17-Pro-Simulator (iOS 26.5). Die Syntaxprüfung unter Linux wird separat vom echten Apple-SDK-Build ausgewiesen. Lokaler Bericht: `build/reports/portable-check.json` nach `python Scripts/check-portable.py`; ein vorhandenes Swift-Frontend lässt sich mit `--swift-frontend` angeben. [AUDIT-FIXES.md](Docs/AUDIT-FIXES.md) ordnet die Änderungen zu; [RELEASE.md](Docs/RELEASE.md) nennt offene Prüfungen.

## Grenzen und Datenschutz

WebKit und Webseiten entscheiden über Autoplay, PiP, AirPlay, DRM und Hintergrundwiedergabe. `AVAudioSession.playback` und Audio-Hintergrundmodus garantieren keine dauerhaft laufende WKWebView. Während iOS die App suspendiert, kann ein Timer erst beim Fortsetzen pausieren. Die Clock-Aktion „Wiedergabe stoppen“ wird über öffentliche Remote-Stop-/Pause-Befehle behandelt, sofern iOS sie zustellt; keine garantierte Clock-Steuerung. Videozählung benötigt primäre HTML-video-Endereignisse und gilt nicht für Audio/Live-Streams.

Serverseitig in Streams eingefügte Werbung wird nicht zuverlässig entfernt. Webseiten und iOS entscheiden über Medienfunktionen; die App extrahiert keine Medienlinks zum Speichern oder zur Übergabe an ein Drittanbieter-SDK. Die Lizenzen der verbleibenden Filterquellen sind in der App und im Repository dokumentiert.

[PRIVACY.md](PRIVACY.md) beschreibt die Datenflüsse. Öffentliche [Datenschutzerklärung](https://mopphie.github.io/webkweb-privacy/), [Supportseite](https://mopphie.github.io/webkweb-privacy/support/) und [Impressum](https://mopphie.github.io/webkweb-privacy/impressum/) sind online und in `App/Info.plist` hinterlegt. Eine App-Store-Zulassung wird nicht zugesagt; die rechtlichen Texte müssen mit dem finalen Build abgeglichen werden. [TestFlight-Secrets und offene Signierung](Docs/TESTFLIGHT-SECRETS.md).

## Wiedergabefixes und echte Medienprüfung (16.10.2026)

Explizite Medienbefehle und Pointer-Auswahl erkennen neu eingefügte offene Shadow-Player sofort. Hintergrund-Zeitmeldungen werden gedrosselt; normale Pausemeldungen bleiben sofort sichtbar. Die App verwendet die echte WebKit-Kennung statt einer fest eingebauten Safari-17-Version; Desktop-/Mobilmodus nutzt öffentliche Navigationseinstellungen. Private Popups übernehmen ihre vorhandene Sitzung. Reload/Session verwenden nach Redirects die tatsächlich bestätigte Adresse.

`python Scripts/check-browser.py` prüft originale Playback.js mit echter lokaler Chromium-Dekodierung und selbst erzeugtem Testvideo. Python Playwright, Chromium und ffmpeg müssen installiert sein; keine fremden Accounts/Videos oder Werbesysteme werden automatisiert. 15 Fälle bestanden lokal. Neue native Medientests verwenden `Tests/Fixtures/sample.mp4` in einem sichtbaren WKWebView und prüfen tatsächlichen Fortschritt, Pause/Seek, natürliches Ende und Timerstop. Beide Medientests bestanden im [nativen Simulatorlauf](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443); es wurden echte HTML-Videos dekodiert, keine Medien-APIs gemockt. [Funktionsmatrix und Plattformgrenzen](Docs/FUNCTION-TEST-MATRIX.md).

Der Nutzer hat Actions am 16.10.2026 ausdrücklich freigegeben. `validate.yml` startet auf dem Entwicklungsbranch Debug/XCTest und unsigned Release-Build; kein Signing oder Upload. Der frühere manuelle Dispatchzugriff lieferte HTTP 403; Push-CI startete erfolgreich. [Erfolgreicher Lauf](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443), [unsigned Release-Simulator-App](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029370391) und [native .xcresult-Testresultate](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029320581) für Code `24d961f`. Das App-Artefakt ist für den Mac-Simulator, keine auf einem iPhone installierbare IPA; GitHub bewahrt die Artefakte sieben Tage auf.
