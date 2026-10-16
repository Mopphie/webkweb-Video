> Neuer Nutzerauftrag: Teilen-Erweiterung entfernen und TestFlight hochladen. Target, eingehende Inbox, Provisionierungshelfer und Share-Profilanforderungen sind entfernt; Signier- und IPA-Prüfung erwarten App + Widget. Früherer Share-Signierblocker gilt für diesen neuen Stand nicht mehr. Neuer Lauf und Ergebnis werden unten ergänzt; bisherige Runs bleiben historische Nachweise.

# TestFlight-Auftrag — Ausführungsstand 16.10.2026

Stand: 13:23 UTC. **Noch kein neuer TestFlight-Upload.**
Dieser Bericht ergänzt das frühere lokale Audit. Die ausdrücklichen späteren Freigaben erlauben für diesen Auftrag CI, den separaten Releasebranch und die notwendige Apple-Einrichtung der Teilen-Erweiterung. Keine App-Store-Einreichung oder Preis-/Vertragsänderung.

## Nachgewiesen

- Projekt `WebKWeb`, Produkt DevnTube, iOS 17+, App/Widget/ShareExtension, vorhandenes Team HUN9MS832X.
- macOS-CI mit Xcode 26.6, iPhone-17-Pro-Simulator/iOS 26.5. App und beide Erweiterungen kompilieren im Debug-Testbuild.
- Run 38900857919: **65/65 native XCTestfälle bestanden**, darunter echte AVPlayer-/WebKit-Wiedergabe eigener Testdateien. Kein Nachweis aktueller YouTube-Wiedergabe, echter AirPlay-Geräte oder Rechte aller Websitequellen.
- Die UI-Suite ist noch nicht erfolgreich: Run 2 spielte den nativen Clip tatsächlich ab, fand aber die ausgeblendeten AVKit-Controls nicht. Run 3: zwei Browserfälle bestanden; dritter Browserfall überschritt nach langem Appstart sein Zeitlimit, native Pflichtreise scheiterte bereits am Wiedergabestart.
- Buildfehler in `LibraryHubView` behoben. AVKit-Steuerung wird im UI-Test vor Benutzung mit echter Berührung eingeblendet. Kalter WebContent-Start erhält in der Fixture begrenzte zusätzliche Startzeit; funktionale Assertions bleiben bestehen.
- Weiterer Playerfix: nie geladene Home-WebViews blockieren den nativen Player nicht mehr. Geladene Webseiten müssen weiterhin ihre Pause bestätigen; bei ausbleibender Bestätigung nach 5 Sekunden kein nativer Tonstart, sichtbarer Fehler und bewusster Retry. Zwei zusätzliche native Regressionstests implementiert; Run 38904042462 bestätigt **67/67 native Tests bestanden**, einschließlich beider neuer Regressionen. Dort außerdem **3/3 Browser-UI-Tests bestanden**. Die native Reise startet und findet Vollbild, verliert den auto-ausgeblendeten Systembutton jedoch vor dem Tipp. Der folgende Run 38905329201 bestätigt erneut **67/67 native Tests und 3/3 Browser-UI-Tests**, erreicht tatsächlich AVKit-Vollbild und scheitert dort am Test-Locator: Er sucht zum Einblenden der Vollbildsteuerung die nun verdeckte Inline-View `native.player`. PiP, Appwechsel und die weitere Reise wurden in diesem Fall **nicht erreicht**. Die anschließende Locator-Korrektur verwendet im Vollbild eine reale Berührung im Appfenster; nur Swift-Syntax geprüft, noch **kein erneuter iOS-Lauf**. Kein Test übersprungen oder als bestanden umgedeutet.
- Lokaler Swift-6.1-Parser akzeptiert die sechs geänderten Swiftdateien. **20/20** aktuelle Python-Helfertests mit Mockprofilen/-API bestanden; kein Apple-/Signiernachweis durch diese Mocks.
- Apple hat die neue Bundle-ID `de.mopphie.devntube.share` tatsächlich registriert. Ein erzeugtes Share-App-Store-Profil wurde von der strikten Validierung abgewiesen. Es wird nicht ausgeliefert; App-Group-Zuordnung/Profil weiterhin offen. Xcode-Setup scheitert konkret an „Authentication failed: Make sure a bearer token was provided…“. Der REST-Schlüssel kann Bundle-IDs/Profile bearbeiten, die Xcode-Authentifizierung für die Entwicklerportal-Einrichtung ist damit nicht nachgewiesen. Bestehende App-/Widget-Profile und Zertifikate wurden nicht widerrufen.

## Ausgelöste GitHub-Actions-Läufe

Repository: [Mopphie/webkweb-Video](https://github.com/Mopphie/webkweb-Video), ausschließlich dedizierter Branch `codex/testflight-2026-10-16`. Lokale Arbeit bleibt auf `local/testflight-upload-20261016`; ursprüngliche lokale Historie erhalten.

| Run | Zweck | Tatsächlicher Stand |
|---|---|---|
| [38898212603](https://github.com/Mopphie/webkweb-Video/actions/runs/38898212603) | Vollständiger TestFlight-Preflight | SwiftUI-Typprüffehler, anschließend korrigiert; kein Upload |
| [38898817409](https://github.com/Mopphie/webkweb-Video/actions/runs/38898817409) | Vollständiger Preflight | App/Erweiterungen bauen; ein nativer Fixture-Start und die native UI-Reise fehlgeschlagen; Browser-UI 3/3 bestanden; kein Upload |
| [38900857919](https://github.com/Mopphie/webkweb-Video/actions/runs/38900857919) | Vollständiger Preflight | Native Tests 65/65 bestanden; UI 2/4 bestanden, zwei Fehler; kein Upload |
| [38901467319](https://github.com/Mopphie/webkweb-Video/actions/runs/38901467319) | Ubuntu-Signierkonfiguration | Nur Secret-Vorhandensein geprüft: Shareprofil fehlt; keine Secretwerte ausgegeben |
| [38901816891](https://github.com/Mopphie/webkweb-Video/actions/runs/38901816891) | Read-only Apple-Prüfung | Share-ID fehlte tatsächlich, bestehender ASC-Schlüssel kann Registrierung lesen |
| [38903663497](https://github.com/Mopphie/webkweb-Video/actions/runs/38903663497) | Autorisierte Share-Einrichtung | Bundle-ID registriert; folgender Capability-REST-Leseaufruf HTTP 400; kein Upload |
| [38903898981](https://github.com/Mopphie/webkweb-Video/actions/runs/38903898981) | Share-Einrichtung | Derselbe Capability-Leseaufruf scheitert; keine Profilfreigabe |
| [38904042462](https://github.com/Mopphie/webkweb-Video/actions/runs/38904042462) | Neuer vollständiger Preflight | Abgeschlossen: 67/67 native Tests, 3/3 Browser-UI bestanden; native Reise scheitert am verschwundenen Vollbildbutton vor dem Tipp. Kein Upload |
| [38904184426](https://github.com/Mopphie/webkweb-Video/actions/runs/38904184426) | Xcode-Share-Einrichtung | Xcode Status 65; erzeugtes Distributionsprofil erfüllt strikte Entitlement-/Zertifikatsprüfung nicht; verworfen |
| [38904472698](https://github.com/Mopphie/webkweb-Video/actions/runs/38904472698) | Xcode-Signierdiagnose | Fehlgeschlagen: Xcode-Authentifizierung abgewiesen; kein aktives Shareprofil enthält die bestehende App Group. Kein weiteres ungültiges Profil erzeugt |
| [38905329201](https://github.com/Mopphie/webkweb-Video/actions/runs/38905329201) | Vollständiger Preflight mit stabilisiertem System-UI-Test | Abgeschlossen: 67/67 native Tests und 3/3 Browser-UI bestanden. AVKit-Vollbild erreicht; Test-Locator sucht dort die verdeckte Inline-View und scheitert. PiP/Restreise nicht erreicht. Upload übersprungen |

Die abschließende ausschließliche UI-Test-/Dokumentationskorrektur verwendet `[skip ci]`; damit kein weiterer blinder Voll-Lauf während des bestätigten externen Signierblockers. Ein erneuter iOS-Nachweis des Test-Locators steht ausdrücklich aus.

**Elf tatsächlich gestartete Läufe**, davon fünf volle macOS-Preflights, vier kurze macOS-Signiereinrichtungen und zwei Ubuntu-Prüfungen. Abgerechnete Minuten/Geldbetrag wurden nicht aus dem GitHub-Billing abgerufen und sind damit nicht belegt. Kein zusätzlicher Cloud-Mac-Dienst, keine neuen SDKs/Abos/APIs gebucht. Remotecommits per autorisierter GitHub-Verbindung; keine PR und keine Änderungen am Hauptbranch. Keine Tester-Einladungen. Temporäre Signiermaterialien werden im jeweiligen Runner bereinigt und nicht als Artefakt veröffentlicht; Testergebnisse enthalten ausschließlich eigene synthetische Testmedien.

## Noch erforderlich

1. Korrigierten Vollbild-Test-Locator unter iOS erneut ausführen und die gesamte Vollbild-/PiP-/Rückkehr-/Queue-Reise nachweisen. Im letzten vollständigen Lauf wurden PiP/Appwechsel/Queue/Suche nicht erreicht. Native 67er-Suite und alle drei Browser-UI-Tests sind im letzten vollständigen Lauf bestanden. Keine erfolgreichen AirPlay-, physischen iPhone-/iPad-, Bluetooth- oder echten YouTube-Gerätetests dieses Standes.
2. **Externer Signierblocker:** Im Apple-Developer-Portal unter Certificates, Identifiers & Profiles → Identifiers → `de.mopphie.devntube.share` die bereits bestehende App Group `group.de.mopphie.devntube` zuordnen und speichern. Dafür eine berechtigte Apple-Anmeldung/Xcode-Sitzung verwenden; der vorhandene REST-Schlüssel funktioniert für Registrierung/Profile, Xcode weist ihn für automatische Einrichtung zurück. Danach ein passendes App-Store-Profil mit dem vorhandenen Distributionszertifikat erstellen/validieren. Kein neuer Gruppenname, keine Löschung/Widerruf bestehender Zertifikate und keine Entfernung der Erweiterung. Ein gültiges Profil kann bei einem späteren Upload auf dem Runner gelesen werden, ohne seine Inhalte in Logs/Repository zu schreiben.
3. Signiertes Releasearchiv/IPA aller drei Targets prüfen, dann Upload; Apple-Verarbeitung und interne TestFlight-Verfügbarkeit explizit prüfen. Bisher keine dieser Prüfungen als erfolgreich behauptet.
4. Releaseblocker R03–R07 des Audits bleiben unabhängig davon bestehen, insbesondere echter YouTube-Gerätetest, fehlender Betreiberkontakt, öffentliche Datenschutz-/Support-URLs (bei Audit HTTP 404) und Rechte-/Vertriebsfragen. Kein werbefreies YouTube oder garantierter Website-PiP versprochen.

## Dateien und nachvollziehbare Codecommits

- `b6e01fb`: `App/LibraryHubView.swift` — konkrete NavigationLink-Destination/Callbacks, SwiftUI-Typprüffehler korrigiert.
- `acfb358`: `Tests/MediaPlaybackIntegrationTests.swift`, `UITests/NativePlaybackJourneyUITests.swift` — begrenzter Fixture-Kaltstart und echte Berührung zum Anzeigen der AVKit-Controls.
- `b201316`: `App/BrowserSession.swift`, `NativePlayer.swift`, `NativePlayerPanel.swift`, `Tests/NativePlayerTests.swift` — sichere Audioübergabe, kein Warten auf nie geladene WebViews, begrenztes echtes Pause-Acknowledgement, Fehler/Retry und Regressionstests. Außerdem explizites UI-Test-Teardown und serieller Simulatorlauf.
- `f43dc91`: nativer AVKit-PiP-Start-/Stopstatus und UI-Pflichtreise mit echten Pause-/Play-Gesten; der Test fordert jetzt den tatsächlichen System-PiP-Callback.
- `1d3439f`, `0c53485`, `00fa0f4`, `dbf3f6c`, `a29727a`: runner-lokaler öffentlicher Apple-Signierweg und Mocktests für genaue Bundle-/Zertifikatszuordnung sowie Ablehnung ungültiger Profile ohne weitere unnütze Erzeugung.
- Remote-Quellstand des letzten vollständigen Laufs: `60ee98fb6c4b978e993fb1dee8353aa8cf21efcb`, exakt derselbe Git-Tree `f0f6ba2425dae7fc1fd9c176b18a7677c236bf8f` wie lokaler Codecommit `f43dc910559e5697c109cdf14cc8e280f85419dd`. Unterschiedliche lokale/Remote-Commit-IDs entstehen durch die GitHub-Commit-API; die ursprüngliche lokale Historie wurde erhalten.
- `0e761bb`: nur UI-Test-Locator nach tatsächlich beobachtetem Vollbildeintritt korrigiert; Swift-6.1-Syntaxprüfung bestanden, iOS-Wiederholung noch NICHT AUSGEFÜHRT.
- Berichte und Baseline-Kennzeichnung: `Docs/TESTFLIGHT_STATUS.md`, `TEST_REPORT.md`, `RELEASE_BLOCKERS.md`, `APP_AUDIT.md`, `FEATURE_MATRIX.md`, `APP_REVIEW_NOTES.md`.

Rohdaten der CI-Läufe sind die verlinkten GitHub-Logs/xcresult-Artefakte; heruntergeladene eigene Fixture-Aufzeichnungen und Hilfsdateien bleiben ausschließlich im ignorierten lokalen `build/reports/`. Keine Nutzeraufnahme, Signierprofile oder Zugangsdaten in Commits.

## Folgeauftrag: Teilen entfernen und hochladen

Eingehende ShareExtension vollständig aus Produkt/Build/Empfang entfernt. App und Favoriten-Widget behalten ihre vorhandene App Group und getrennte Profile. Der IPA-Helfer weist fehlende Widgets und unerwartete zusätzliche Extensions ab. Der alte Inbox-Key wird gezielt bereinigt; unabhängige Favoritendaten/Zustimmung bleiben erhalten.

Aktuelle lokale Prüfungen: Foundation **31/31**, Node **53/53**, Python-Signier/ASC-Mocks **14/14** bestanden; sämtliche verbliebenen Swiftdateien syntaxgeprüft. Plists/Privacy-Manifests und Workflow-Shellblöcke parsebar. Dies ersetzt keinen iOS-Lauf. Vollständiger nativer Lauf und tatsächlicher Upload folgen auf dem autorisierten Releasebranch; Ergebnis wird ergänzt. Keine neue Apple-ID-/Profilregistrierung vorgesehen.

### Erster Lauf ohne Teilen-Erweiterung

[38910333671](https://github.com/Mopphie/webkweb-Video/actions/runs/38910333671), Remote-Code `e08280cda1dd2014a79dd17b6f3ca2192714d1cb`, lokaler Code `e264a24`, gleicher Tree `35ce490da919b0c7ba4afd1362bb16b06e6e6042`: **67/67 native Tests und 3/3 Browser-UI bestanden**. Native Reise erreicht Vollbild und Rückkehr, scheitert dann am im iPhone-Simulator nicht angebotenen PiP-Button. Kein Signing/Upload ausgeführt; keine Aussage über die Ursache fehlender PiP-Unterstützung aus der bloßen Button-Abwesenheit.

Folgekorrektur: iPhone behält alle 67 nativen und drei Browser-UI-Tests. Die native adaptive Vollbild-/Queue-/Suchreise und die vollständige PiP-Reise laufen separat auf einem tatsächlich verfügbaren iPad-Simulator. Der PiP-Test liest `AVPictureInPictureController.isPictureInPictureSupported()` über eine ausschließlich im DEBUG-Fixturemodus sichtbare Diagnose. Ausschließlich ein explizites `false` darf den geräteabhängigen PiP-Fall als **NICHT AUSGEFÜHRT / SKIPPED** markieren; fehlende Controls/Callbacks oder Medienfortschritt bei `true` bleiben echte Fehler. Die unabhängige Vollbild-/Queue-/Suchreise läuft trotzdem und verlangt echte Wiedergabe des nächsten Queueeintrags. Wiederaufnahme erfolgt vor dem PiP-Versuch wie bei einer normalen laufenden Wiedergabe. Keine Funktion entfernt oder ein Test als erfolgreich vorgetäuscht.

Primärquelle, abgerufen 16.10.2026: [Apple AVPictureInPictureController](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller) verlangt die Prüfung der tatsächlichen Geräte-/Kontextunterstützung. Daraus folgt keine pauschale Behauptung, jeder Simulator unterstütze oder unterstütze PiP nicht. Ein übersprungener Lauf ersetzt keine Geräteabnahme; der öffentliche Releaseblocker bleibt bestehen. Der ausdrücklich gewünschte TestFlight-Build dient auch diesen noch offenen Gerätetests.

### Zweiter Lauf ohne Teilen-Erweiterung

[38912187784](https://github.com/Mopphie/webkweb-Video/actions/runs/38912187784), Remote `d43c2cbc57ffd34541277a38847520968f4c08fa`, lokaler Code `2627fab`, Tree `0261419fd396c2cb67b2868755fb82a9f6616bf2`: iPhone **67/67 native Tests und 3/3 Browser-UI bestanden**. iPad **Vollbild → zurück → Queue → tatsächlich spielendes nächstes Video → Suche bestanden**. iPad meldet ausdrücklich `pip_supported=true`; daher wurde PiP nicht übersprungen. Die PiP-Reise scheitert an der automatisch ausgeblendeten Systembedienung; keine Aussage „PiP nicht unterstützt“ oder „PiP bestanden“. Kein Archiv/Upload.

Nächster gezielter Prüfschritt: vorhandenen öffentlichen automatischen Inline-PiP-Start bei echtem Wechsel in die iOS-Einstellungen testen. Zähler/Zeitpunkt werden ausschließlich vom realen AVKit-DidStart-Callback gesetzt, flüchtig gehalten und nur im DEBUG-Fixturemodus als Testdiagnose sichtbar. Der Test verlangt einen neuen Start innerhalb des Appwechsel-Zeitfensters, fortgesetzte Medienzeit, dieselbe Medien-ID und anschließende Rückkehr/Queue/Suche. Keine private API, kein erzwungener Website-PiP und kein Ersatzplayer. CI gibt nach der iPhonephase deren Simulatorressourcen frei. Die Profilvalidierung wird vor den langen Tests ausgeführt; Archiv/Upload bleiben an erfolgreich abgeschlossene Tests gebunden.

### Dritter Lauf ohne Teilen-Erweiterung

[38915439692](https://github.com/Mopphie/webkweb-Video/actions/runs/38915439692), Remote `4ec49d214f1a9e85469dbb2e235b2899b14eab10`, lokal `bb94a9e`, Tree `ddfae003a8e77f043397c144e3eae6380fe235f9`: **Signierprüfung für App und Widget bestanden** (vorhandene Profile, App Group, Team, Distributionszertifikat). Der entfernte Share-Profilblocker besteht nicht mehr. Buildnummer 6 wurde von App Store Connect ermittelt, aber noch nicht hochgeladen.

iPhone: 66 von 67 nativen Fällen bestanden; Watch-Fixture blieb beim 12-Sekunden-Kaltstart auf `about:blank` (Timeout plus Folgefehler). Zwei von drei Browser-UI-Fällen bestanden; der erste Touch nach App-Pause wurde im dritten Fall nicht als fortgesetzte Wiedergabe bestätigt. iPad/PiP, Archiv und Upload wegen dieser Fehler **NICHT AUSGEFÜHRT**.

Folgekorrektur: Auch die Watch-Dokumentfixture bekommt das bereits für andere neue WebContent-Prozesse verwendete separate 45-Sekunden-Startbudget. Reale DOM-Eingaben auf einem Overlay im Videorechteck registrieren die Wiedergabeabsicht jetzt synchron vor dessen `play()`; die asynchrone UIKit-Beobachtung konnte sonst erst nach dem verworfenen Play-Ereignis eintreffen. Synthetische, außerhalb liegende und bloße Tastaturkoordinaten dürfen keinen Stop lösen. Zwei zusätzliche Node-Regressionstests dafür bestanden (**55/55** gesamt), Python-Helfer **14/14**; geänderte Swift-Testdateien unter Swift 6.1 syntaxgeprüft. Browser-UI erfasst bei erneutem Fehler den echten Playerzustand. iOS-Wiederholung dieses Fixes steht noch aus.
