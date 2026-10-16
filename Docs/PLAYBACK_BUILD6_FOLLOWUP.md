# Build 6: Pause beim Verlassen der App — 16.10.2026

## Aktuelles Ergebnis — 16.10.2026, 18:45 UTC

**DevnTube 0.1.0 (7) ist für interne TestFlight-Tests aktiv:** Apple `VALID` / `IN_BETA_TESTING`, Build-ID `eef3d57c-bec8-4e6a-ad4c-aca6c081faf0`. Signiertes Archiv/Export/Zwei-Target-IPA/Upload: [38947209143](https://github.com/Mopphie/webkweb-Video/actions/runs/38947209143), Upload **18:38:59 UTC**. Der Uploadlauf ist wegen der anschließenden HTTP-422-Verifikation insgesamt rot; er wird nicht als grüner Gesamtlauf ausgegeben. Unabhängige reine Leseprüfung [38949793940](https://github.com/Mopphie/webkweb-Video/actions/runs/38949793940) bestätigt den aktiven Apple-Status um **18:45:44 UTC**. Keine neue Binärdatei für die Nachprüfung hochgeladen.

**Wichtigster offener Punkt:** Der Nutzer reproduziert den YouTube-Stopp beim Verlassen der App in Build 6. Für YouTube gibt es weiterhin **keinen bestätigten Hintergrund-/automatischen PiP-Fix**. Die behobenen Appfehler und eigenen Mediennachweise sind davon getrennt.

### Abschluss A–J dieser Folgeprüfung

A. **Behoben:** Start/Öffnen eines Tabs entsperrt keine anderen pausierten Tabs mehr. Verspätete `started`-Nachrichten gestoppter Tabs übernehmen die Wiedergabe nicht. Echte Website-Play-Anforderungen werden vor einem verspäteten WebKit-Play-Ereignis bestätigt; das 1,5-s-Fenster für spätere Autoplay-Versuche bleibt erhalten. Private verspätete Startbestätigungen bei gesperrter/verborgener App bleiben blockiert.

B. **Ergänzt:** getrennte begrenzte RAM-Steuerungs-/Statusdiagnose, Millisekunden, App-/Website-Sichtbarkeit und lesender PiP-Modus. Keine großen Medienbedienelemente hinzugefügt. Native vorhandene App-/Widget-/Siri-/Datei-/Mediatheksfunktionen und Notizen bleiben erhalten.

C. **Entfernt/ausgeschlossen:** keine zusätzlichen Produktfunktionen entfernt. Die ausdrücklich entfernte eingehende Teilen-Erweiterung bleibt aus der IPA. Kein Adblock, SponsorBlock, Stream-/MP3-Extraktor, erzwungenes YouTube-PiP/Background, Cast-SDK oder Keep-alive ergänzt. Die nicht installierte Uhr-App wurde ausschließlich als Testbegleitapp durch nachweislich vorhandenes Safari ersetzt.

D. **Rechte:** nur eigener Anwendungscode und bestehende öffentliche Apple-Frameworks; keine neuen Produktionspakete/-assets/-datenlizenzen oder Lizenzgebühren. Bestehende Apple-Vertrags-/Plattformvoraussetzungen und offene formale Rechtekette bleiben im Lizenzregister. Apple-APIs erteilen keine fremden Medienrechte. Keine pauschale kommerzielle/weltweite Rechtsfreigabe.

E. **Offen:** YouTube-Appwechsel/PiP auf echtem Nutzergerät mit Build 7, weitere reale Dienst-/Hardware-/Privacy-/Layoutprüfungen, Betreiberkontakt/öffentliche Datenschutz-/Supportangaben, formale Rechte-/Länder-/Markenklärung. Gewöhnliche Websiteplayerfunktionen bleiben verfügbar; keine Premium-/Zugangsumgehung.

F. **Tatsächlich geprüft:** lokal **63/63 Node**, **31/31 Foundation**, **20/20 echte Chromiumfälle** mit eigenen Loopback-Medien und **17/17 Python-Helfermocks**. Zwei deterministische Startregressionen scheitern mit vorherigem JS. Ein weiterer echter Eingabetest stoppt mit dem Microtask-Zwischenfix bei 1,794 s und besteht mit dem finalen Task-/Frist-Fix. Xcode [38942074355](https://github.com/Mopphie/webkweb-Video/actions/runs/38942074355): **72/72 native**, **3/3 Browser-UI ohne Retry**, iPad-Basisreise bestanden. Bei unverändertem App-/JS-/Widget-/Projektcode bewusst wiederverwendet. Xcode [38947209143](https://github.com/Mopphie/webkweb-Video/actions/runs/38947209143): vollständige eigene PiP-Reise mit echtem Safari-Vordergrund/App-Rückkehr/System-PiP-Rückkehr/Queue/nächstem Video/Suche **bestanden, 147,785 s, kein Skip/Retry**. AVKit-Zähler 0→1, gleiche Medien-ID, Uhr 3,500317583→15,000569333 s. Archiv, Export und IPA mit genau App + Widget und gleicher Version/Build 7 bestanden.

G. **Nicht ausgeführt:** eigener Live-YouTube-/Twitch-/TikTok-/Rumble-Gerätetest, physisches AirPlay/BT/Kopfhörer/Telefonunterbrechung/Gerätesperre/Netzwechsel, echte alte Build-4-Datenmigration/OS-WebContent-Abbruch/VoiceOver/große Schrift/Rotation und vollständige private OS-Spurenprüfung. Keine hörbare Hardware-Audio- oder Performancegarantie aus dem Simulator abgeleitet. Nutzerevidenz Build 6 ist separat dokumentiert.

H. **Dateien/Commits:** Runtime in `App/BrowserSession.swift`, `App/BrowserView.swift`, `App/Resources/Playback.js`; Regressionen in `Tests/BrowserIntegrationTests.swift`, `Tests/MediaPlaybackIntegrationTests.swift`, `Tests/playback.test.cjs`, `Scripts/check-browser.py`. Lokale Runtimecommits `2526831`, `775e4fa`, **`c0a00aa`**. Letzter Appcode bleibt anschließend unverändert; SHA-256 Playback.js **`6c2c3b85abb7342c4fa6ce837bd070903e9f716be5f29936d93ec9d7d336e2a3`**. Signierter Uploadquellbaum: lokaler Harnesscommit **`bed39e3`**, remote **`86e8a17e880d979950a9db56c44e436b2fedad7c`**, gleicher Tree **`35ff5f65f3dff0a0ef0d48cecdcf5e1564746da2`**. CI-/Dokumentationsnachträge ändern das ausgelieferte Appverhalten nicht. Branch `local/playback-tab-ownership-20261016`; `main` unverändert, Nutzeränderungen nicht verworfen.

I. **Externe Aktionen/Kosten:** in dieser Folgeprüfung fünf autorisierte macOS-Actions-Läufe: `38936556842` fehlgeschlagen (71 native/grüner Release-Simulatorbuild/eigene volle PiP-Reise separat bestanden), `38940432893` vor Archiv/Upload abgebrochen und Signiermaterial entfernt, `38942074355` App-/Browser-/iPad-Basistests bestanden, externer Settings-Start blockierte PiP; `38945753919` fehlende Uhr-App; `38947209143` erfolgreicher eigener PiP-/Archiv-/Export-/Uploadteil mit nachgelagerter Verifikationsstörung. Dazu Linux-Leseprüfung `38949793940` erfolgreich; [38950289770](https://github.com/Mopphie/webkweb-Video/actions/runs/38950289770) bestätigt mit dem korrigierten Helfer denselben aktiven Build erneut. Damit **5 macOS- und 2 reine Linux-Leseläufe** in dieser Folgeprüfung. **Genau ein neuer Binär-Upload (Build 7)**, keine App-Store-Einreichung, PR, Force-Push, neuen Tester/Gruppe, Apple-Verträge/Produkte/Cloud-Konfigurationen, Zugangsdatenweitergabe oder neu gebuchten Dienste. Abgerechnete Minuten/Beträge nicht abgefragt; Actions-Minuten ausdrücklich autorisiert. Normale Uploadserialisierung ist wiederhergestellt.

J. **Releasebereitschaft:** interne Beta 7 aktiv. **Keine vollständige öffentliche Releasefreigabe**: insbesondere der gemeldete YouTube-Hintergrundstopp ist nicht nachweislich behoben; R03–R07 bleiben entsprechend offen. Keine Aussage „100 % legal“, „Apple genehmigt alles“, „alle Plattformen werbefrei“ oder „alle Gerätetests bestanden“.

## Tatsächlicher Befund

Der Nutzer meldet DevnTube **0.1.0 (6)**, `m.youtube.com`, und präzisiert: Die Pause passiert **beim Verlassen der App**. Sein freiwillig geteilter Diagnoseauszug vom 16.10.2026, 16:41:32–16:42:27 UTC enthält 315 gezählte Videoframes (Legacy-Feld `decodedFrames`, tatsächlich `getVideoPlaybackQuality().totalVideoFrames`), Medienzeit 25,277 s bei 1669,121 s Dauer, `readyState=4`, `paused=true`, `waiting=false`, Filter aus, globale und JS-Stoppsperre aus, Restore-Suspendierung aus. Zusammen mit den Play-/Zeitwerten spricht dies für zeitweilige Medienverarbeitung mit anschließender Pause. `totalVideoFrames` zählt dargestellte und verworfene Frames; diese Zahl allein beweist weder 315 erfolgreich dargestellte Bilder noch den sichtbaren Bild-/Tonfortschritt oder die Ursache der Pause. Kein eigener Live-YouTube-Gerätetest.

Das Feld `native` bezeichnet im bisherigen Diagnoseformat den Swift-Snapshot der WebView, nicht einen Nachweis einer separaten AVPlayer-Wiedergabe.

Der alte 40-Ereignis-Ring besteht überwiegend aus Ladezuständen unterschiedlicher Medien/Frames. Er enthält keine App-Lebenszyklus-/PiP-Beobachtung und ist kein ausreichender Nachweis dafür, ob Website, System, Nutzereingabe oder App den Hintergrundstopp auslöste.

## Korrigierter unabhängiger Appfehler

`BrowserModel.clearPlaybackStop()` hob bisher beim Start oder Öffnen eines Tabs die JS-Sperren **aller** Tabs auf. `didStartFromWebsite` pausierte zuvor die anderen Tabs und hob unmittelbar danach deren Sperren wieder auf. Ein anderer Autoplay-Player konnte dadurch erneut Audio beanspruchen. Dessen `started`-Nachricht konnte den aktiven Tab erneut pausieren. Diese konkrete Implementierungsschwäche ist unabhängig von der gemeldeten Appwechsel-Ursache korrigiert:

- Stoppsperre pro Tab; Freigabe nur für den tatsächlich geöffneten/gestarteten Tab.
- Andere gestoppte Tabs, neue Dokumente und eingebettete Frames behalten ihre Sperre.
- Eine verspätete `started`-Nachricht eines gestoppten Tabs übernimmt die Wiedergabe nicht. Echte Websiteeingabe und explizites erlaubtes Play können den eigenen Tab wieder freigeben.
- Keine zweite Play-Anweisung beim Beobachten eines Website-Starts. Kein automatisches Resume beim Appwechsel.

## Diagnose und Privatbereich

Der Bericht trennt jetzt bis zu 40 Steuerungs-/Audio-/Lebenszyklusereignisse von 40 Statusereignissen im RAM. Zeitstempel enthalten Millisekunden. App-Pausegründe, Appzustand, beobachtete Medien-/Sichtbarkeitsereignisse, tabbezogene Sperre und lesend ermittelter PiP-Darstellungsmodus werden unterscheidbar. Ein beobachtetes `pause` wird ausdrücklich **nicht** als Beweis für eine Website- oder Nutzerursache bezeichnet. Keine zusätzlichen URLs, Titel, Cookies, Formulardaten, Streams, Uploads oder dauerhaften Diagnosespeicher. Private Berichte und Ereignisse bleiben vollständig deaktiviert.

## YouTube und Hintergrund: offene Grenze

Im bestehenden Produkt startet `attemptAutoPiP()` für Websites absichtlich kein erzwungenes PiP. `WKWebViewConfiguration.allowsPictureInPictureMediaPlayback` erlaubt gewöhnliche, vom Dienst angebotene Systemfunktionen in normalen Tabs; private Tabs bleiben ausgenommen. Normale Webvideos werden durch den App-Lebenszyklus nicht pauschal pausiert. Private Webvideos werden absichtlich pausiert. Eigene/berechtigte native Medien verwenden die öffentliche AVKit-Hintergrund-/PiP-Unterstützung.

Offizielle YouTube-Hilfe am **16.10.2026, 16:59 UTC** erneut abgerufen:

- [Bild im Bild, iOS](https://support.google.com/youtube/answer/7552722?hl=de&co=GENIE.Platform%3DiOS): beschreibt PiP in der **YouTube-App**; Musikinhalte sind Premium vorbehalten. Kein pauschaler Nachweis, dass jedes YouTube-PiP Premium erfordert; keine ausdrückliche Freigabe einer app-eigenen Erweiterung in einem fremden Browser.
- [Premium-Vorteile, iOS](https://support.google.com/youtube/answer/6308116?hl=de&co=GENIE.Platform%3DiOS): beschreibt Hintergrund-Audio in den mobilen YouTube-/Music-/Kids-Apps bei bestehender Premium-Berechtigung. Die ebenfalls beschriebene PiP-Verfügbarkeit für Inhalte ohne Musik darf nicht mit Hintergrund-Audio gleichgesetzt werden.

Apple-Primärdokumentation ebenfalls erneut abgerufen am **16.10.2026, 17:14 UTC**: [WKWebView-PiP-Erlaubnis](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowspictureinpicturemediaplayback.md) beschreibt das Zulassen von HTML5-PiP; [automatischer Inline-Übergang](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/canstartpictureinpictureautomaticallyfrominline.md) ist eine Eigenschaft des **AVPlayerViewController**. Letztere ist im eigenen nativen Player gesetzt; die WebView wird dadurch nicht zu diesem Player. Die Dokumente beschreiben technische APIs, keine YouTube-Rechtefreigabe. Die ergänzende Suche ergab keine ausdrückliche Browser-Integrationsgenehmigung. Communitybeiträge wurden nicht als Freigabe oder Nachweis dieser App verwendet.

Weder eine Plattformpause noch deren Umgehung ist durch diesen Auszug bewiesen. **Der gemeldete YouTube-Hintergrundstopp bleibt offen.** Kein Stream-Extraktions-, Werbe-, Premium-, Sichtbarkeits- oder Keep-alive-Workaround ergänzt. Normale vom Dienst angebotene Playerfunktionen bleiben erhalten. Ein Test mit eigener HTML-Datei ist kein Live-YouTube-Nachweis.

## Prüfungen dieser Änderung

- **63/63 Node-Tests bestanden**; darunter tatsächlicher gebündelter JS-Code, Sichtbarkeitswechsel ohne automatisches Resume, diagnostische Ereignisse und ausschließlich lesender PiP-Zustand.
- **31/31 Foundation-Tests bestanden**, Swift-Parser für App/Shared/Widgets/Tests/UI-Tests erfolgreich; offizieller lokal vorhandener Swift-6.1-Container, ohne Netzwerk. Kein Apple-SDK-Build daraus abgeleitet.
- **14/14 Python-Helfermocks bestanden**.
- **20/20 echte Chromium-Decoderfälle bestanden**, ausschließlich eigene Loopback-Testmedien.
- Neue iOS-Regressionen: Tabfreigabe/verspäteter Start/Navigation, getrennte private Diagnose sowie zwei echte WKWebViews einschließlich Autoplay und Dokumentwechsel. Im ersten Xcode-Lauf **bestanden**; die anschließende Eingabebestätigung und Privatsperr-Regression werden erneut geprüft.
- Build 6 selbst hat bereits einen bestandenen nativen iPad-Simulator-PiP-/Appwechsel-/Rückkehrtest mit eigenem AVPlayer-Film. Diese Quelle ist von YouTube getrennt. Auf dem iPhone des Nutzers ist das aktuelle YouTube-Hintergrundproblem weiterhin reproduziert; kein erfolgreicher Fix dafür behauptet.

Prüfprotokolle lokal unter `build/reports/playback-ownership-*`; keine Zugangsdaten oder Original-Video-URLs gespeichert. Branch `local/playback-tab-ownership-20261016`, Ausgangspunkt `3533e93`.

## Externe Aktionen

Zur Prüfung wurde ausschließlich die neue Branch `codex/playback-tab-ownership-2026-10-16` mit identischem Quellbaum publiziert; `main` und die TestFlight-Branch bleiben unverändert. Ein unsignierter Prüfworkflow [38936556842](https://github.com/Mopphie/webkweb-Video/actions/runs/38936556842) wurde gestartet. Lokaler Codecommit `2526831`, Remote-Codecommit `a6f357864455cf87c65562b398a3d90b3e97d811`, identischer Tree `f36517dd8f6dfc9bdb0d9fe294c163813f953294`. In diesem ersten Prüflauf keine PR, Signierung, neuen Produkte/Konten/Tester, Apple-Konfigurationsänderungen, TestFlight-Uploads oder App-Store-Einreichungen. Tatsächliche abgerechnete Minuten/Kosten nicht abgefragt; autorisierte Actions-Nutzung, keine neuen Dienste gebucht.

## Erster Xcode-Lauf: Ergebnis und weiterer belegter Fehler

Run **38936556842** endete insgesamt **FAILURE**. Der unsignierte Release-Simulator-Build bestand. Alle **71/71 nativen Tests**, darunter echte Zwei-WebView-Regression mit anschließendem Dokumentwechsel (3,952 s), bestanden. Drei Browser-UI-Fälle bestanden letztlich; der unmutierte Pause-/Resume-Fall benötigte jedoch den vorgesehenen zweiten Versuch. Der iPad-Basisfall scheiterte beim ersten `app.launch()` nach kaltem Simulatorstart (83,082 s, XCTest-Launchtimeout). Die danach gestartete **vollständige PiP-/Appwechsel-/Queue-/Suchreise bestand** ohne Skip oder Retry (93,585 s): echter AVKit-Startzähler 0→1, identische Medien-ID, Uhr 4,000→12,512 s. Dies ist weiterhin ein eigener AVPlayer-Film, kein YouTube-Nachweis.

Die neue Steuerungsdiagnose des fehlgeschlagenen unmutierten Browser-UI-Versuchs liefert einen konkreten Appfehler: echte Eingabe um **17:12:52,115 UTC**, erst um **17:12:57,874 UTC** `observed.stop-rejected` und erneute Pause. Das spätere HTML-`play`-Ereignis traf nach dem bisherigen 1,5-s-Intentfenster ein. Der Play-Aufruf kann `paused` bereits synchron ändern, bevor WebKit nach Audioinitialisierung sein Ereignis ausliefert. Die echte Eingabe wurde dadurch fälschlich als Autoplay behandelt.

Finale Korrektur: Ein unmittelbar nach der Eingabe geplanter Task bestätigt innerhalb des unveränderten 1,5-s-Fensters ausschließlich einen bereits angeforderten, nicht pausierten Player. Auch eine frische tatsächliche Startanforderung, die bei der Medienbeobachtung sichtbar wird, wird anerkannt. Ein Microtask aus der Capture-Phase genügt nicht, weil er vor dem Website-Handler laufen kann. Er ruft niemals `play()` auf. Ein neuer Stop verwirft die Intentidentität; spätere unabhängige Autoplay-Versuche erhalten keine längere Freigabe. Die Host-Touch-Beobachtung erfasst ihren Intent vor dem Anbringen der Stopprüfungen, damit ein bereits angeforderter Systemkontrollstart nicht vorzeitig pausiert wird. Private verspätete Startbestätigungen bei gesperrter/verborgener App bleiben abgewiesen. Zwei deterministische neue Regressionen scheitern mit dem gespeicherten bisherigen JS (53/55 bestehen, 2 scheitern) und bestehen mit der Änderung (zusammen mit Compliance und weiterer Fristprüfung **63/63**). Ausdrücklicher Stop, abgelaufene Eingabe und synthetische Klicks bleiben wirksam geprüft.

Der CI-Simulator wird vor dem nächsten iPad-XCTest-Aufruf ausdrücklich mit `simctl bootstatus -b` fertig gebootet. Kein Startfehler wird als bestandener App-Test umgedeutet. Der nächste vollständige signierte TestFlight-Lauf darf nur nach bestandenen Prüfungen hochladen. Er dient den belegten Start-/Tab-Fixes und der Appwechsel-Diagnose; **kein bestätigter YouTube-Hintergrundfix**.

## Zusätzlicher echter Browserfall und Ersetzen des Zwischenkandidaten

Der reale Chromium-Decoderfall `delayed-website-play-event` verwendet einen tatsächlichen Playwright-Klick auf den eigenen nichtsemantischen Website-Startknopf. Nur im Test wird die Auslieferung an den Bridge-`play`-Listener um sechs Sekunden verschoben. Der Microtask-Zwischenfix reicht dabei nicht: Capture-Listener-Microtasks können vor dem Website-Zielhandler laufen. Mit gespeichertem Zwischen-JS stoppt der eigene Film nach **1,794 s** und der Fall scheitert. Mit dem abschließenden Task-/Frist-Fix besteht der Film nach über sechs Sekunden weiter; **20/20** reale Browserfälle bestehen. Normale synthetische Klick-/Autoplay-Prüfungen bleiben unverändert erhalten. **63/63** Nodefälle prüfen zusätzlich, dass ein verspäteter Bestätigungstask das 1,5-s-Fenster nicht verlängert. Kein realer YouTube- oder iOS-Nachweis aus Chromium.

Der TestFlight-Zwischenlauf **38940432893** baut noch den Microtask-Kandidaten (`775e4fa` lokal, `1e71dbb0f2d2e96552eca9867a2ffa71220c6946` remote; Tree `b5e97e4a393fb5227e6f38ca4f178c20fc8b9e0f`). Er wird während der laufenden Vorprüfung durch den abschließenden Kandidaten ersetzt. Archiv/Upload müssen dazu weiterhin ungestartet sein; dies wird direkt vor Aktualisierung geprüft. Die Concurrency wird dafür einmalig auf Ersetzen gestellt und unmittelbar nach bestätigtem Abbruch wieder auf normale Serialisierung zurückgesetzt. Keine parallelen Apple-Uploads und keine neue Stornierungs-API oder zusätzlichen Berechtigungen.

Bestätigung um **17:47 UTC**: Zwischenlauf **CANCELLED**, Archiv und Upload **SKIPPED**, Entfernen des Runner-Signiermaterials **SUCCESS**. Vor der Aktualisierung zweimal geprüft: ausschließlich dieser Uploadworkflow aktiv, Vorprüfung lief, Archiv/Upload noch ungestartet. Die normale Serialisierung (`cancel-in-progress: false`) ist wiederhergestellt; diese Dokumentations-/CI-Korrektur trägt `[skip ci]` und verändert keinen App-/Testcode.

Abschließender Prüfkandidat: lokaler Codecommit **`c0a00aa`**, Remote-Codecommit **`ecf8dac09e2729c74bdccd4b495297068ac041ae`**, identischer Code-/CI-Tree **`d383d5b8cced74de4e9e11438dabded68a4b25d6`**. Vollständiger neuer TestFlight-Lauf **[38942074355](https://github.com/Mopphie/webkweb-Video/actions/runs/38942074355)**; Ergebnis und Apple-Status noch ausstehend. Der abgebrochene Lauf liefert keine Freigabe. Der reale YouTube-Hintergrundstopp bleibt offen.

## Abschließender Appcode unter Xcode geprüft; externe Test-App blockiert PiP-Abnahme

Run **38942074355** endete insgesamt **FAILURE**: **72/72 native Tests**, darunter alle acht echten WK-Medienfälle, **3/3 Browser-UI ohne Wiederholung** und die iPad-Basisreise Vollbild/zurück/Queue/nächstes Video/Suche (89,427 s) bestanden. Der vollständige PiP-Fall meldet öffentliche Frameworkunterstützung und laufenden eigenen 600-s-Film, scheitert dann aber an `Failed to launch com.apple.Preferences: Timed out attempting to launch app`. Kein erfolgreicher PiP-Appwechsel wird aus diesem Versuch abgeleitet. Archiv und Upload blieben **SKIPPED**, Signiermaterial wurde erfolgreich entfernt.

Die Testreise aktiviert nun die unabhängige leichtere **Uhr-App (`com.apple.mobiletimer`)**. Echte andere Vordergrund-App, Home, tatsächlicher AVKit-Startcallback, Zeitfenster/fortlaufende Medienuhr, identische Medien-ID, echte PiP-Rückkehr, Queue/nächstes Video/Suche bleiben unveränderte Anforderungen. Kein Mock, kein Home-only-Fallback und keine automatische Erfolgswertung eines Launchfehlers.

Der folgende Lauf wiederholt gezielt diese eine PiP-Reise. Der Guard erlaubt dies ausschließlich vom exakt protokollierten Parent-Tree **`968ae7458412a74610230d5e7a6f0475047a6c7e`** mit sauberen, begrenzten Harness-/Dokumentationsänderungen. **Kein App-, JS-, Shared-, Widget-, Projekt- oder Packagecode ändert sich** gegenüber dem bereits mit 72 nativen/3 Browser-/iPad-Basistests geprüften Releasecode. Diese bestandenen Prüfungen werden ausdrücklich wiederverwendet, nicht als erneut ausgeführt gezählt. Ein späterer tatsächlicher Releasecode-Unterschied aktiviert wieder die volle Suite. Das frühere positive eigene PiP-Ergebnis aus Run 38936556842 bleibt getrennte Vorgängerevidenz; YouTube-Hintergrund weiterhin offen.

## Installierte andere Test-App verbindlich prüfen

Gezielter Lauf **38945753919** (`755d523` lokal / `df41add2ac10784d5dc05c8ab3e2e695b87c144e` remote, Tree `e49923fba7e50cb8dd4e49616e02843e6ed4986d`) schlug vor dem Video fehl: `Application info provider ... returned nil for com.apple.mobiletimer`. Die Uhr-App ist in diesem Simulator nicht installiert; die vorherige Annahme war falsch. Keine PiP-Abnahme, Archiv/Upload weiterhin übersprungen; Signiermaterial entfernt.

Die andere App wird auf **Safari (`com.apple.mobilesafari`)** geändert. Vor dem XCTest-Start verifiziert der öffentliche Simulatorbefehl `simctl get_app_container ... app` ihre tatsächliche Installation; fehlt sie, endet die Prüfung sichtbar als nicht ausgeführt/fehlgeschlagen. Erst echte Aktivierung/Vordergrundzustand dürfen den Appwechsel bestätigen. Kein alternativer Home-only-Pass. Sämtliche PiP-Start-/Identitäts-/Zeit-/Systemrückkehr-/Queue-/Suchassertionen bleiben gleich. Keine Safari-Seite, Kontoeinstellung oder persönlichen Daten werden im Test bedient.

Für diese reine Harnesskorrektur ist zusätzlich nur der exakt vorherige Parent-Tree `e49923fba7e50cb8dd4e49616e02843e6ed4986d` zugelassen. Produktionscode bleibt bytegleich in den Quelldateien; 72 native/3 Browser-/iPad-Basisprüfungen aus Run 38942074355 werden weiterhin ausdrücklich wiederverwendet. Ein neuer vollständiger PiP-Nachweis steht noch aus. Der reale YouTube-Hintergrundstopp bleibt offen.

## Apple-Status unabhängig bestätigt und Verifikationshelfer korrigiert

Der abschließende Safari-Lauf **38947209143** bestand die vollständige native PiP-Reise und signierte Archivierung/Export/Zwei-Target-IPA; Upload **0.1.0 (7)** um **18:38:59 UTC** erfolgreich. Der Gesamtlauf blieb wegen **HTTP 422 im nachgelagerten Verifikationspfad** rot. Die ursprüngliche Fehlermeldung protokollierte keine Route; daraus werden weder fehlende Schlüsselrechte noch eine konkrete unverifizierte Apple-Parameterursache als gesichert abgeleitet.

Reine Linux-Leseprüfung **38949793940** bestätigte um **18:45:44 UTC**: Build-ID `eef3d57c-bec8-4e6a-ad4c-aca6c081faf0`, `VALID`, `IN_BETA_TESTING`. Kein erneuter Build, keine Binärübertragung, Gruppen-/Tester-/Kontoeinrichtungsänderung. Signierschlüssel verblieben runnerlokal und wurden entfernt.

Der Helfer prüft jetzt zuerst Apples tatsächlichen internen Buildstatus. Ist der Build bereits **IN_BETA_TESTING**, braucht er keinen zusätzlichen Gruppenabgleich und verändert keine Verteilung. Ein lediglich **READY_FOR_BETA_TESTING** gemeldeter Build wird bei fehlgeschlagenem Gruppenabgleich weiterhin nicht als aktiv ausgegeben. API-Fehler enthalten nur HTTP-Status und sichere Methode/Route, niemals Query, Antwortinhalt, JWT oder Schlüssel. **17/17** lokale Python-/Signiermocks einschließlich dieser Grenzfälle bestanden. Reiner Lesecheck **38950289770** bestätigt mit dem korrigierten Helfer um **18:49:40 UTC** erneut denselben aktiven Build; keine Gruppenmitgliedschaft gelesen oder geändert. Die frühere Gruppenabfrage bleibt für noch nicht aktive Builds separat zu prüfen, falls Apple sie dort ablehnt; aktive Beta-Verfügbarkeit wird durch diesen optionalen Pfad nicht mehr verdeckt.

Helfercommits lokal `8c03f93` / `0b61564`, remote Statusbranch `66e4231f3c46aba6b1d5895b7a067dfcfdb5d708` / `e88bd394a6c3cf7a9e8018fb9fdb162d3065a2e5`. Statusworkflow ausschließlich `.github/workflows/testflight-status.yml`, Linux, feste bereits hochgeladene Buildnummer 7, keine neuen App-/API-/Backendabhängigkeiten. Dokumentations-/Helfernachträge werden mit `[skip ci]` auf die Releasebranch übertragen; kein Upload von Build 8 und keine weiteren macOS-Läufe dadurch.
