# DevnTube (internes Xcode-Ziel: WebKWeb)

Nativer Video-Browser für iPhone und iPad mit SwiftUI, WKWebView und SwiftData, ab iOS/iPadOS 17. Deutsche Oberfläche; Entwicklungsversion mit noch ausstehenden Apple-Build- und Gerätetests.

Die schwarze Startseite zeigt eine Suchpille, YouTube/Twitch/TikTok/Rumble und Favoriten/Verlauf/Timer/Einstellungen. Alle acht Startseiten-Icons sind schlichte lokale Glyphs ohne Glass-/Materialflächen oder Randblasen. Die transparente Trefferfläche bleibt groß; Suchpille und funktionale Browserbuttons behalten ihr Material. Lokale Icons erzeugen keine Favicon-Anfragen. Mit iOS-26-SDK/Compiler 6.2 nutzt die Oberfläche Liquid Glass, sonst Systemmaterial. Transparenz reduzieren, große Schrift und iPad erhalten eigene Layoutanpassungen.

## Funktionen

- URL oder Suche mit Google, DuckDuckGo oder Bing; `canOpenURL`, Zurück/Vorwärts, Teilen, Popup-Tabs und normale Tab-Wiederherstellung. URLs mit Zugangsdaten werden nicht als Suchbegriff übertragen. Private Tabs verwenden einen eigenen nicht persistenten WebKit-Speicher und erscheinen weder im Verlauf noch im wiederhergestellten Zustand.
- Mobiler oder Desktop-Safari-User-Agent und Seitenzoom. Inline/Autoplay/PiP/AirPlay sind konfiguriert. Eine isolierte Bridge steuert HTML-Medien auch in Frames und offenen Shadow Roots; native Play/Pause/Seek, Systemlautstärke und optionale Gestenfläche.
- Mehrteilige WebKit-Netzwerkfilter ohne alphabetische Domainbegrenzung, unverlierbare Basisregeln und YouTube-Ad-Endpunkte. AdGuard DNS, HaGeZi und StevenBlack sind auswählbare Quellen; HTTPS-Quellen und Textimport, tägliche Vordergrund-/manuelle Updates, Quellcache, Diagnose und Seiten-Ausnahmen sind vorhanden. Unterstützte AdGuard/EasyList-Netzwerkregeln und Ausnahmen werden konservativ übersetzt; unbekannte Ausnahmen verwerfen die Quelle. Keine Scriptlets oder vollständige EasyList-Kompatibilität.
- Optionales SponsorBlock: vier Kategorien, eingebettete YouTube-Player, SPA-Wechsel, Seiten-Ausnahmen sowie Skip und Rückgängig. Standardmäßig aus; native cookie-freie Abfragen.
- Sleep-Timer mit freier Dauer bis 24 Stunden, Anzahl primärer Videos oder Ende des aktuellen Videos. Nach Ablauf verhindert eine lokale Sperre auch Autoplay neu eingefügter Player. Zeit-/Anzahlpläne normaler Tabs werden wiederhergestellt; ein Plan für den alten konkreten Player wird beim Neustart verworfen und gemeldet.
- SwiftData-Verlauf mit abschaltbarer Aufzeichnung und maximal 500 nicht favorisierten Einträgen; Favoriten bearbeiten/sortieren. Geteilte Favoriten werden bei Besuchen, Bearbeitung und iCloud-Änderungen für Siri und das konfigurierbare Widget aktualisiert. Cookie-/Website-Daten-Löschen schließt vorher die aktiven Dokumente.
- Vier App Intents/Siri-Kurzbefehle, Sperrbildschirm-Medienmetadaten, Remote Play/Pause/Stop/Seek und Audio-Unterbrechungsbehandlung. Private Seitentitel erscheinen nicht in Now Playing.
- Echter optionaler Google-Cast-SDK-Build: Geräteauswahl, direkte Medienquelle mit passendem MIME-Typ, Receiver-Status, Fehler, Play/Pause/Seek/Trennen und Übergabe erst nach erfolgreicher Ladeanfrage. Standardbuild ohne Cast-Abhängigkeit.
- Optionales CloudKit für Verlauf/Favoriten mit CloudKit-tauglichem Modell. Erst nach Konfiguration eines echten, provisionierten Containers aktivierbar; Umschalten gilt beim Neustart. Private Tabs und Browsersitzungen werden nicht synchronisiert.

## YouTube-Watch-Ansicht

Auf echten YouTube-`/watch?v=...`-Seiten entfällt die App-Adress-/Tab-/Player-/Timer-/Fußleiste. Der echte WKWebView zeigt YouTubes Player, ein-/ausblendbare Controls, Titel, Kanal, Abos, Aktionen, Kommentare und Empfehlungen. Ein deckend roter 44-pt-Menübutton liegt unten rechts innerhalb der Safe Area (14 pt rechts/18 pt unten); Navigation, Adresse, Tabs und App-Funktionen liegen im Menü. Masthead und Playerrahmen werden über begrenzte öffentliche DOM/CSS-Anpassungen gestaltet; die App erzeugt keine eigenen YouTube-Inhaltskarten. Routewechsel per SPA/History/BFCache entfernen oder erneuern die Anpassung. Andere Webseiten behalten ihre Browseroberfläche. YouTube-Layout/A/B-Varianten und reale Apple-Darstellung müssen auf Geräten geprüft werden; keine pixelgenaue Zusage.

Erneuter Funktionsaudit vom 14.10.2026: [AUDIT-FIXES.md](Docs/AUDIT-FIXES.md). HIG-/App-Review-Prüfung und konkrete offene Release-Bedingungen: [APP-REVIEW-DESIGN.md](Docs/APP-REVIEW-DESIGN.md). Öffentlich erreichbare Privacy-/Support-URL und Betreiberkontakt sind statisch über die historisch benannten Schlüssel `WebKWebPrivacyURL`, `WebKWebSupportURL`, `WebKWebOperatorContact` in `App/Info.plist` hinterlegt. Diese Angaben sind nicht vom App-Endnutzer editierbar. Die In-App-Datenschutzhinweise bleiben verfügbar.

## Ergänzungen aus dem Video-Lite-Vergleich

Im Menü erreichbar: lokale URL-/Favoriten-Queue mit vollständigem Shuffle und Repeat Aus/Ein/Alle, Next/Previous über RemoteCommands; Hintergrund-Linköffnung per Longpress. Playeroptionen bieten getrenntes Vollbild/PiP, Geschwindigkeit, verfügbare HTML-Untertitel-/Audiospuren und Buffering-/Fehleranzeige. Auto-PiP, Shorts-Ausblenden und Original-Audio sind optionale Einstellungen. Kein interner YouTube-API-Zugriff oder erfundener 1080p-Schalter.

**Nur Entwicklungsbuild:** Direkte HTTPS-Audio-/Videodateien lassen sich in Debug herunterladen, abbrechen, erneut laden, teilen und löschen. Der Vordergrunddownload nutzt keine Browser-Cookies, prüft HTTP/MIME und lehnt Streaming-Manifeste ab. Mangels belegter Drittquellenrechte ist der Downloader im einheitlichen Release-Build für alle Nutzer per `WEBKWEB_NO_DOWNLOADS` aus dem kompilierten Produkt ausgeschlossen; die Mac-Binärprüfung steht noch aus. [Variante und Prüfpfad](Docs/NO-DOWNLOAD-VARIANT.md). Keine Stream-/DRM-Extraktion und kein garantierter Hintergrunddownload.

Die Bridge verwaltet Medien über Mutationserfassung und cached Nodes; offene Shadow Roots werden sichtbar höchstens alle 15 Sekunden zusätzlich gesucht. Nicht sichtbare Frames senden nur alle fünf Sekunden einen Heartbeat. Diese DOM-/Nachrichtenreduktion wurde im Harness geprüft; tatsächliche CPU/Batterie/CarPlay/TV/Rotation bleiben Gerätetests. Vergleich und kurzer Funktionsaudit: [VIDEO-LITE-COMPARISON.md](Docs/VIDEO-LITE-COMPARISON.md).

## Auf dem Mac starten

Für den aktuellen App-Store-Upload: macOS mit Xcode 26+, iOS-26-SDK, Command Line Tools, XcodeGen und Node.js 18+. Das Mindestziel der App bleibt iOS 17:

```bash
brew install xcodegen node
xcodegen generate
open WebKWeb.xcodeproj
```

Für App und Widget dasselbe Development Team setzen. Die expliziten IDs `de.mopphie.devntube` und `de.mopphie.devntube.favorites` sowie die Gruppe `group.de.mopphie.devntube` sind im Apple-Portal unter Team `HUN9MS832X` registriert; die App-Group-Zuordnung beider Kennungen wurde nach erneutem Öffnen geprüft. Bundle-IDs, beide Entitlements und `FavoriteStorage.groupID` stimmen damit im Quellcode überein. App-Store-Profile und echte Geräte-Signierung stehen noch aus.

Optionales Cast benötigt CocoaPods und den vorhandenen `Podfile`; [CAST.md](Docs/CAST.md) enthält den Workspace-Build. Für CloudKit eine bereits im eigenen Apple-Konto angelegte Container-ID konfigurieren:

```bash
./Scripts/configure-cloudkit.py --container DEINE_BEREITS_PROVISIONIERTE_ICLOUD_CONTAINER_ID
xcodegen generate
```

Der Parameter muss eine echte `iCloud.*`-ID sein. Das Skript setzt Plist/Entitlements; iCloud-, Push- und App-Group-Capabilities sowie Signierung bleiben im Apple-Portal einzurichten. In den App-Einstellungen anschließend iCloud aktivieren und neu starten. Derselbe lokale SwiftData-Store wird verwendet; beim Ausfall startet die App lokal mit einer Meldung. Vor Produktivnutzung Migration und Zwei-Geräte-Sync prüfen.

## Lokal prüfen – keine GitHub Actions

Es gibt keine Workflows. **GitHub Actions dürfen nur mit ausdrücklichem OK des Nutzers eingerichtet oder ausgeführt werden.**

```bash
node --test Tests/*.test.cjs
./Scripts/check-macos.sh
./Scripts/check-macos.sh --cast
```

Das macOS-Skript generiert das Projekt, wählt einen vorhandenen iPhone-Simulator und führt `xcodebuild test` aus. `--cast` installiert die Pods und prüft den Workspace. Ein Simulator lässt sich über `WEBKWEB_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 16'` wählen. Nach erneuter Projektgenerierung einen bestehenden Cast-Workspace erneut mit `pod install` aktualisieren.

Direkter Standardbuild:

```bash
xcodebuild -project WebKWeb.xcodeproj -scheme WebKWeb -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

Die Simulatorbezeichnung muss auf dem Mac vorhanden sein. Auf Windows wurden 50 Node-Bridge-Tests ausgeführt und Swift-Syntax/Projekt-/Pliststruktur geprüft. Die 38 XCTest-Definitionen sind für den Mac vorbereitet, hier nicht ausgeführt. Swift-Syntaxprüfung ersetzt keinen Apple-SDK-Build. Lokaler Prüfbericht: `build/reports/portable-check.json` nach `python Scripts/check-portable.py --swift-frontend <Pfad zum Swift-Frontend>`. [AUDIT-FIXES.md](Docs/AUDIT-FIXES.md) ordnet ältere Änderungen zu; [RELEASE.md](Docs/RELEASE.md) nennt die offenen Prüfungen.

## Grenzen und Datenschutz

WebKit und Webseiten entscheiden über Autoplay, PiP, AirPlay, DRM und Hintergrundwiedergabe. `AVAudioSession.playback` und Audio-Hintergrundmodus garantieren keine dauerhaft laufende WKWebView. Während iOS die App suspendiert, kann ein Timer erst beim Fortsetzen pausieren. Die Clock-Aktion „Wiedergabe stoppen“ wird über öffentliche Remote-Stop-/Pause-Befehle behandelt, sofern iOS sie zustellt; keine garantierte Clock-Steuerung. Videozählung benötigt primäre HTML-video-Endereignisse und gilt weder für Audio/Live-Streams noch den Cast-Empfänger.

Serverseitig in Streams eingefügte Werbung wird nicht zuverlässig entfernt. SponsorBlock-Daten können fehlen oder falsch sein. Cast braucht einen vom Empfänger erreichbaren HTTP(S)-Medienlink und passende Codecs; Cookies, besondere Header und DRM-Lizenzen werden nicht übertragen. `blob:`/MSE und YouTube-Watch-URLs sind keine direkten Dateien.

[PRIVACY.md](PRIVACY.md) beschreibt die Datenflüsse. Öffentliche [Datenschutzerklärung](https://mopphie.github.io/webkweb-privacy/), [Supportseite](https://mopphie.github.io/webkweb-privacy/support/) und [Impressum](https://mopphie.github.io/webkweb-privacy/impressum/) sind online und in `App/Info.plist` hinterlegt. Eine App-Store-Zulassung wird nicht zugesagt; die rechtlichen Texte müssen mit dem finalen Build abgeglichen werden. [TestFlight-Secrets und offene Signierung](Docs/TESTFLIGHT-SECRETS.md).
