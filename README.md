# WebKWeb

Nativer Video-Browser für iPhone und iPad, geschrieben mit SwiftUI, WKWebView und SwiftData. Mindestversion: iOS/iPadOS 17. Die Bedienoberfläche ist deutsch. Dieses Repository ist eine Entwicklungsversion, kein bereits geprüfter App-Store-Release.

Die schwarze Startseite konzentriert sich auf eine Suchpille, vier Seitenlinks (YouTube, Twitch, TikTok, Rumble) und vier Aktionen (Favoriten, Verlauf, Timer, Einstellungen). Suchfeld und Browser-Steuerung verwenden Liquid Glass mit dem iOS-26-SDK/Swift-Compiler 6.2 oder neuer. Auf iOS 17–25 beziehungsweise mit Xcode 16 dient Systemmaterial mit dezentem Randlicht als Fallback. „Transparenz reduzieren“ verwendet deckende Flächen; große Bedienungshilfen-Schrift stellt die Iconreihen auf zwei Spalten um. Alle Startseiten-Icons werden lokal gezeichnet.

## Enthalten

- URL oder Suchbegriff in einer Adresszeile; Suchbegriffe öffnen Google. `canOpenURL` prüft die aufgelöste HTTP(S)-Adresse. Tabs, Zurück/Vorwärts, Teilen, Fehleranzeige und eine zusätzliche Tab-Leiste auf dem iPad.
- Mobiler Safari-User-Agent, Inline-Wiedergabe, Autoplay-Konfiguration, Bild-in-Bild und AirPlay. Eine isolierte JavaScript-Welt erfasst HTML-Medien auch in eingebetteten Frames. Play/Pause und Seek bedienen den aktiven Medienframe; Lautstärke nutzt `MPVolumeView`.
- WebKit-Netzwerkfilter mit eingebauten Basisregeln, YouTube-`pagead`-/Ad-Statistik-Endpunkten und täglichen Updates aus der AdGuard DNS-Liste. Der Konverter unterstützt einen konservativen AdGuard/EasyList-Domainregeln-Teilumfang und respektiert Ausnahmen durch weniger Blockierung. Keine Scriptlets, kosmetischen Filter oder Umdeutung unbekannter Regeln.
- SponsorBlock für Sponsor-, Intro-, Outro- und Eigenwerbungssegmente, einschließlich YouTube-SPA-Navigation. Anfangs ausgeschaltet; Aktivierung mit Datenschutzinfo in den Einstellungen. Die Abfrage läuft nativ, ohne Website-Cookies, nicht als Fetch im Seitenskript.
- Sleep-Timer nach Minuten oder Anzahl beendeter Videos. Die Videozählung ist an den beim Start gewählten Tab gebunden; doppelte Ereignisse werden ignoriert. Nach Ablauf werden Pause und eine lokale Autoplay-Sperre gesetzt.
- Lokaler Verlauf (maximal 500 nicht favorisierte Seiten), Favoriten, Löschfunktionen, Cookie-/Website-Daten-Löschung, Favoriten-Widget und vier App Intents für Siri/Kurzbefehle.
- Optionales Google Cast SDK mit echter Geräteauswahl und `GCKRemoteMediaClient`-Load für direkte HTTP(S)-Medienlinks. Der Standardbuild benötigt keine Drittanbieter-SDKs.
- Privacy-Manifeste, App-Group-Entitlements, App-Icon, XCTest-Tests, Node-Tests und ein lokales macOS-Prüfskript.

## Auf dem Mac starten

Voraussetzung: Xcode 16 oder neuer, Command Line Tools, XcodeGen und für die JS-Tests Node.js 18 oder neuer.

```bash
brew install xcodegen node
xcodegen generate
open WebKWeb.xcodeproj
```

In Xcode für **WebKWeb** und **FavoritesWidget** dasselbe Development Team auswählen. Beide Bundle-IDs sowie die App Group `group.de.mopphie.webkweb` müssen zum eigenen Apple-Developer-Konto passen. Falls du sie änderst, aktualisiere `project.yml`, beide Entitlements und `Shared/FavoriteSnapshot.swift`. Aktiviere die App Group für beide App-IDs im Developer-Portal. Simulator-Builds können ohne Signierung laufen; Widgets auf echten Geräten benötigen korrekt provisionierte App Groups.

Der XcodeGen-Quellplan ist `project.yml`; generierte Xcode-Projekte werden nicht eingecheckt. SwiftData verwendet explizit `.none` für CloudKit. iCloud-Synchronisierung ist noch nicht implementiert.

## Lokal prüfen – keine GitHub Actions

Es gibt **keinen GitHub-Actions-Workflow**. Pushes/PRs sollen keine Actions-Minuten verbrauchen. Checks werden nur lokal und bewusst ausgeführt.

```bash
node --test Tests/playback.test.cjs
./Scripts/check-macos.sh
```

Das macOS-Skript generiert das Xcode-Projekt, findet einen vorhandenen iPhone-Simulator und führt `xcodebuild test` aus. Einen Simulator kannst du ausdrücklich auswählen:

```bash
WEBKWEB_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 16' ./Scripts/check-macos.sh
```

Oder direkt:

```bash
xcodebuild -project WebKWeb.xcodeproj -scheme WebKWeb \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

Die Simulatorbezeichnung muss auf deinem Mac vorhanden sein. Für iPad den vorhandenen iPad-Simulator wählen. Geräteprüfung und Release-Aufgaben stehen in [Docs/RELEASE.md](Docs/RELEASE.md).

## Grenzen

WebKit und Webseiten entscheiden über Autoplay, PiP, AirPlay, Login, DRM und Hintergrundwiedergabe. `AVAudioSession.playback` und der Audio-Hintergrundmodus sind eingerichtet; sie garantieren keine dauerhaft laufende WKWebView im Hintergrund. Ein Sleep-Timer kann während einer von iOS suspendierten App erst beim Fortsetzen ausgeführt werden. Videozählung benötigt HTML-Medien-`ended`-Events und gilt nicht für Live-Streams oder den Cast-Empfänger.

Netzwerkfilter können serverseitig in den Stream eingefügte Werbung nicht zuverlässig entfernen. Es gibt keine Zusage für werbefreies YouTube oder ein unverändertes YouTube-Verhalten. SponsorBlock-Communitydaten können fehlen oder ungenau sein.

Cast braucht einen vom Empfänger erreichbaren direkten Medienlink, unterstützte Codecs und ggf. CORS. Browser-Cookies, Login-Tokens, DRM-Lizenzen und besondere Header werden nicht übertragen. `blob:`-/MSE-Player und YouTube-Watch-URLs sind keine direkt castbaren Dateien. Einrichtung: [Docs/CAST.md](Docs/CAST.md).

Eine App-Store-Zulassung wird nicht zugesagt. Datenschutz, Signierung, Plattformbedingungen und tatsächliches Verhalten müssen vor einem Release geprüft werden.

## Architektur und Datenschutz

`BrowserModel` verwaltet Tabs und Timer; `BrowserTab` besitzt die WebKit-Delegates, Beobachter und Bridge während der gesamten Lebensdauer des Tabs. SwiftUI zeigt nur den jeweils ausgewählten WebView. `RuleStore` kompiliert und aktualisiert Content Rule Lists; `SponsorBlockService` lädt und cached Segmentdaten. `SavedPage` speichert lokale Daten mit SwiftData; App Group und Widget enthalten nur Favoriten-Snapshots.

Datenschutzerklärung für die Entwicklungsversion: [PRIVACY.md](PRIVACY.md). Vor Veröffentlichung fehlen noch die öffentlich erreichbare Policy-URL und die Verantwortlichen-/Kontaktangaben.
