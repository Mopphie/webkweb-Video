# App-Audit — 16.10.2026

Gegenstand ist der vorhandene Quellstand von **DevnTube** (internes Projekt/Schema **WebKWeb**), nicht die auf dem iPhone installierte Version. Der gemeldete Stopp beim Appwechsel gehört zum Prüfauftrag. Aktuelle Ergebnisse und Grenzen stehen in [TEST_REPORT.md](TEST_REPORT.md), alle 31 Featureentscheidungen in [FEATURE_MATRIX.md](FEATURE_MATRIX.md).

## Reproduzierbare Baseline und Umgebung

- Arbeitsverzeichnis: `/workspace/webkweb-Video`, ursprüngliches Repository `Mopphie/webkweb-Video`.
- Übernommener Originalcommit: `40b09287a40e7d51a3f82e07812ef9309814b99a`; ursprünglicher Remotezweig `codex/commercial-use-cleanup`.
- Der bereitgestellte Ordner hatte keine `.git`-Metadaten. 67 Quelldateien wurden außerhalb des Projekts nach `/workspace/scratch/full-audit-baseline-20261016/source.tar.gz` gesichert; SHA-256-Manifest daneben. Die Originalhistorie wurde **lesend** geholt und der Index ohne Überschreiben des Arbeitsbaums aus diesem Commit aufgebaut. Danach war der Arbeitsbaum sauber: keine vorgefundenen uncommitteten Änderungen verloren.
- Lokaler Arbeitsbranch: `local/compliance-features-20261016`. Kein Remote konfiguriert, kein Push/PR. Keine AGENTS.md im Projekt oder übergeordnet gefunden.
- Linux x86_64, kein Xcode/macOS/iOS-SDK. Node 24.19.0, Chromium 154.0.8037.57, Python 3.12, ffmpeg und lokales Docker vorhanden. Zusätzlich offizielles Swift-6.1-Image lokal geladen (Swift 6.1.3); dessen Testcontainer laufen ohne Netzwerk. Kein Cloud-Mac.
- Quelle `project.yml`: XcodeGen-Projekt, Deployment **iOS 17.0**, Xcode-Mindestangabe 26.0, Swift-Sprachmodus 5, iPhone/iPad, Version 0.1.0/Quell-Buildnummer 1. Diese Nummer ist **kein neuer TestFlight-Build**.
- Baseline-Targets: App WebKWeb, FavoritesWidget, WebKWebTests, WebKWebUITests. Neu: ShareExtension als lokales Quelltarget; keine Provisionierung vorgenommen. Das zusätzliche Swift-Package enthält nur eigene Foundation-Modelle für portable Tests, keine Paketabhängigkeit der App.

## Vollständiges Komponenteninventar

| Bereich | Baseline / jetzige Verwendung | Tatsächliche Dateien |
|---|---|---|
| Start / Browser / Suche | Drei normale Such-URLs, vier Website-Lesezeichen, URL-Eingabe, Lade-/Fehlerzustände, Verlauf, stabile Aktionsliste, Watch-Rückweg | `App/BrowserView.swift`, `BrowserSheets.swift`, `WebView.swift`, `BrowserModels.swift` |
| Tabs / Sitzungen | WKWebView pro Tab; jetzt Suche, Pins, benannte Gruppen, 20 flüchtige normale geschlossene Tabs, höchstens 12 offene WebViews; keine aktive Wiedergabe zur Speicherbegrenzung schließen | `BrowserSession.swift`, `BrowserPreferences.swift` |
| Wiedergabe im Web | Gebündelte eigene isolierte HTML-Medienbrücke in allen Frames/offenen Shadowroots; keine Stream-URL-Ausleitung. Plattformhosts und deren Einbettungen erhalten keine app-eigenen erweiterten Playeraktionen. Allgemeine HTML-Steuerung bleibt für andere Seiten verfügbar, soweit deren Bedingungen sie erlauben | `App/Resources/Playback.js`, `BrowserSession.swift`, `PlayerViews.swift` |
| Eigene native Medien | Ein AVPlayer/AVPlayerItem, Systemcontroller, Miniplayer, Queue, Position, Wiederholung/A–B, Spuren/Kapitel, System-PiP/AirPlay und Audio; nur eigene Dateien / ausdrücklich berechtigte Direktquellen | `NativePlayer.swift`, `NativePlayerPanel.swift`, `AudioController.swift`, `MediaPolicy.swift` |
| Eigene Mediathek | Versioniertes lokales JSON, benannte Playlists, eigene Notizen/Zeitmarken, Weitersehen, Dateien-Bookmarks, Validierung, atomisches Schreiben, Import-Merge | `LibraryModels.swift`, `LibraryStore.swift`, `LibraryHubView.swift` |
| Persistenz | Vorhandene SwiftData-SavedPage-Daten bleiben; UserDefaults für normale Einstellungen/Tab- und Linkqueue-Snapshots; eigene Mediathek in Application Support; Dateizugriffe über Security-Scoped Bookmarks | `Models.swift`, `BrowserPreferences.swift`, `LibraryStore.swift`, `Shared/*` |
| Privatmodus / Sperre | Nicht persistenter WebKit-Store; kein Verlauf/Resume/Diagnose/Tabrestore; expliziter Austritt beim Favoritenspeichern; private Web-PiP aus und Wiedergabe beim Appwechsel pausiert; Geräteauthentifizierung und separates Fenster über allen App-Sheets | `BrowserSession.swift`, `BrowserView.swift`, `PrivacyShield.swift` |
| Filter | Baseline: eigener Konverter + unversioniert nachgeladene AdGuard-/HaGeZi-Listen, generische Werbedomains, lokaler Listenimport. Jetzt vollständig aus dem aktiven Produkt entfernt. Ersatz ist ausschließlich eine vom Nutzer angelegte Hauptseiten-Sperrliste | `Rules.swift`, `NavigationPolicy.swift`, `FilterSettingsView.swift` |
| Skripte / CSS | Keine nachgeladenen Skripte, Scriptlets oder Skript-CDNs. Frühere YouTube-Layout-/Shorts-Eingriffe entfernt. Nur eigene gebündelte allgemeine Medienbrücke; keine Website-CSS-Injektion | `Resources/Playback.js`; `WatchPresentation.js` entfernt |
| Erweiterungen | Widget liest nur ausdrücklich freigegebene normale Favoriten. ShareExtension nimmt einen bewusst geteilten Link an, ohne Abruf; Übergabe verfällt nach 15 Minuten. Gemeinsame Gruppe ist dieselbe vorhandene App Group | `Widgets/*`, `ShareExtension/*`, `Shared/ShareInbox.swift` |
| Intents / Spotlight | Öffnen, Favorit, Pause, Timer, Link speichern, vorhandene benannte Playlist; keine automatische Donation privater Inhalte, kein Spotlight-Indexer. Gesperrte App verwirft Aktionen vor Zugriff; Favoritenparameter wird gegen aktuelle Freigabe erneut aufgelöst | `App/AppIntents.swift`, `Shared/FavoriteEntity.swift` |
| iCloud / Käufe | Kein provisionierter Cloud-Container, keine Cloud-Entitlements, kein aktiver Cloud-Datenpfad. Kein StoreKit, kein Produkt/Kauf, kein Abo, kein eigener Login oder Server | `WebKWebApp.swift`, Entitlements, `project.yml` |
| Assets / Medien | Systemschrift und SF-Symbolnamen über Apple-APIs; keine externen Icon-/Fontpakete. Vorhandenes Icon ohne belastbaren Herkunftsnachweis ersetzt durch eigenen reproduzierbaren geometrischen RGB-PNG-Generator. Zwei synthetische Testclips nur in Testtargets | `Assets.xcassets`, `Scripts/generate-app-icon.py`, `Tests/Fixtures/README.txt` |
| Entwicklung / CI | XcodeGen, Python/Node, Swift-Foundation-Testpackage, Playwright/Chromium/ffmpeg nur Testwerkzeuge. Vorhandene Signier-/ASC-Skripte und Workflows wurden gelesen, nicht ausgeführt. Historische Build-5-Ergebnisse beweisen den neuen Stand nicht | `Scripts/*`, `.github/workflows/*` |

Keine Swift-Packages externer Anbieter, Pods, Cast-SDKs, eingebetteten Drittframeworks, Bibliotheksbinärdateien oder zusätzlichen Codec-Bibliotheken gefunden. Versteckte alte Filter-, SponsorBlock-, Download- und Cast-Schalter sind im Produkt nicht reaktivierbar. DEBUG-Startwege laden ausschließlich eigene Testmedien; sie stehen nicht im Release zur Verfügung und sind kein YouTube-Nachweis. Die erkennbare Herkunft des bestehenden eigenen Codes beruht auf Git-Historie; eine formale Rechteketten-Erklärung fehlt weiterhin. KI-Erzeugung wird nicht als Lizenznachweis behandelt.

## Netzwerk- und Datenfluss

| Auslöser | Empfänger / Inhalt | Speicherung / Grenze |
|---|---|---|
| Frischer Start ohne wiederhergestellte Seite | Kein eigener App-HTTP-Aufruf | Keine Filter-/Metadaten-/Analytics-Anfrage. Apple/OS-interne Kommunikation nicht mitgeschnitten |
| Normaler Tabrestore | Gespeicherte normale Websites und deren Unterressourcen über WebKit | Website-Cookies/Cache im normalen WebKit-Store; quiet Start verhindert ungefragte Wiedergabe. Maximal 12 |
| Suche / Link / Redirect / Popup | Nutzergewählte HTTP(S)-Website bzw. Google/DuckDuckGo/Bing mit Suchbegriff | Keine versteckte Such-API oder Scraping. Credentials-/Schemeprüfung, Popup erbt Privatbereich, externe mailto/tel-Aktion nur nach Nutzerlink |
| Websitevideo | Website und ihre CDN-/Werbe-/Trackingressourcen | Kein eigener Proxy/Extractor, keine app-eigene Adblock-Manipulation. Browser liefert übliche IP-/HTTP-/Cookieinformationen |
| Autorisierte Direktquelle | Vom Nutzer bestätigter HTTPS-Medienhost, Systemdecoder folgt nötigen Medienabrufen/Redirects | Kein Herunterladen in eine Medienbibliothek. Bekannte Plattformhosts sowie gängige signierte/tokenhaltige Links werden nicht als dauerhafte Direktquelle angenommen |
| Dateien-App | Ausgewählte Datei bzw. deren Dateianbieter | Zugriff nur mit Bookmark/aktiver Security Scope. Ein Dateianbieter kann selbst Netzwerk/iCloud nutzen; kein App-CloudKit-Dienst |
| Hintergrund / PiP / AirPlay | Nur tatsächliche Medienwiedergabe / Systemrouten | Keine stillen Audio-Loops, Tasks als Keep-alive, Filterupdates oder Segment-APIs. Gerätezustände noch ungetestet |
| Diagnose | Ausschließlich ausdrückliches lokales Kopieren normaler numerischer Playerzustände | 40 RAM-Ereignisse, Clipboard localOnly/5 Minuten; keine URL/Titel/Cookies; private Diagnose vollständig aus |
| Widget / Siri / Sharing | Lokale App Group, OS-Funktionen nach ausdrücklicher Auswahl | Keine privaten Sessions; Freigabe normaler Favoriten standardmäßig aus. Share-Inbox nur bestätigte Links und begrenzte Haltbarkeit |
| Export | Vom Nutzer gewähltes Ziel | Keine Cookies, Credentials, privaten Tabs, Dateiberechtigungen, Locks, Cloud-Identität, Diagnose oder Wiedergabehistorie |

Normaler Verlauf wird auf 500 nicht favorisierte Seiten begrenzt. Verlaufslöschung entfernt außerdem Weitersehen-Werte und geschlossene Tabs; Favoriten bleiben und verlieren ihren Besuchszeitpunkt. Eigene Notizen/Listen/Dateien bleiben unabhängig erhalten. Normale lokale Daten können durch reguläre OS-Gerätesicherungen erfasst sein. Private Sitzungen haben keinen app-eigenen dauerhaften Datensatz. OS-Caches/Backups/Website-Logs können damit nicht weltweit oder vollständig ausgeschlossen werden.

## Berechtigungen und Sicherheit

Nur vorhandene App Group und Audio-Hintergrundmodus; neue ShareExtension nutzt dieselbe Gruppe. Face-ID-Zwecktext für optionale Geräteauthentifizierung hinzugefügt. Keine Kamera-, Mikrofon-, Foto-, Tracking-, VPN-, Bonjour- oder pauschale Local-Network-Berechtigung. Die allgemeine ATS-Web-Ausnahme wurde entfernt: unsichere/alte HTTP-Seiten können dadurch scheitern, statt pauschal unsichere Verbindungen freizugeben.

Native Bridge: benannte isolierte Content World, begrenzte Nachrichtentypen/-größen und 32 Frames, Document-/Media-ID-Zuordnung, Abgleich von Protokoll/Host/Port mit WKSecurityOrigin, endliche Zahlen. Keine Passwort-, Cookie-, Formular- oder Mediendatei-Ausleitung. Keine privaten Apple-APIs gefunden. Quelleabhängige Fähigkeiten sind getrennt von technischen Laufzeittests.

## Offene Grenzen

Keine Paketliste allein beweist alle Rechte. Keine Codeinspektion beweist Netzverkehr zur Laufzeit, Gerätelaufzeit, Apple-Zulassung oder Rechte aller aufgerufenen Websites. Vertrags-/Länderfragen, Betreiberangaben, Signierung der neuen Erweiterung sowie alle aktuellen iOS-Gerätetests bleiben exakt in [RELEASE_BLOCKERS.md](RELEASE_BLOCKERS.md) aufgeführt.

## Lokale Änderungen und Abschluss

Implementierung/Test-/Signierquellvorbereitung: Commit `8ebb88e` — `Implement native media library and enforce source and privacy boundaries`. Der folgende Dokumentationscommit ergänzt alle acht Abschlussdokumente, Primärquellen-/Datei-/Testregister, aktuelle Datenschutz-/Storetexte, historische Kennzeichnungen und zwei reine EOF-Formatkorrekturen. Die vollständigen lokalen Commit-IDs sind mit `git log -2` abrufbar; kein Remote wurde geschrieben.

Die Nachprüfung bestätigt 31 Featurezeilen F01–F31, erreichbare relative Dokumentlinks, Syntax/Mockprüfungen und unveränderte Herkunft der eigenen Testmedien. Ergebnis: unabhängige zulässige Quelländerungen umgesetzt; kein aktueller iOS-/Dienst-/Geräte-Abnahmebeleg. Release bleibt aus den konkret dokumentierten Gründen blockiert.
