# Build 6: Pause beim Verlassen der App — 16.10.2026

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

- **62/62 Node-Tests bestanden**; darunter tatsächlicher gebündelter JS-Code, Sichtbarkeitswechsel ohne automatisches Resume, diagnostische Ereignisse und ausschließlich lesender PiP-Zustand.
- **31/31 Foundation-Tests bestanden**, Swift-Parser für App/Shared/Widgets/Tests/UI-Tests erfolgreich; offizieller lokal vorhandener Swift-6.1-Container, ohne Netzwerk. Kein Apple-SDK-Build daraus abgeleitet.
- **14/14 Python-Helfermocks bestanden**.
- **19/19 echte Chromium-Decoderfälle bestanden**, ausschließlich eigene Loopback-Testmedien.
- Neue iOS-Regressionen: Tabfreigabe/verspäteter Start/Navigation, getrennte private Diagnose sowie zwei echte WKWebViews einschließlich Autoplay und Dokumentwechsel. Im ersten Xcode-Lauf **bestanden**; die anschließende Eingabebestätigung und Privatsperr-Regression werden erneut geprüft.
- Build 6 selbst hat bereits einen bestandenen nativen iPad-Simulator-PiP-/Appwechsel-/Rückkehrtest mit eigenem AVPlayer-Film. Diese Quelle ist von YouTube getrennt. Auf dem iPhone des Nutzers ist das aktuelle YouTube-Hintergrundproblem weiterhin reproduziert; kein erfolgreicher Fix dafür behauptet.

Prüfprotokolle lokal unter `build/reports/playback-ownership-*`; keine Zugangsdaten oder Original-Video-URLs gespeichert. Branch `local/playback-tab-ownership-20261016`, Ausgangspunkt `3533e93`.

## Externe Aktionen

Zur Prüfung wurde ausschließlich die neue Branch `codex/playback-tab-ownership-2026-10-16` mit identischem Quellbaum publiziert; `main` und die TestFlight-Branch bleiben unverändert. Ein unsignierter Prüfworkflow [38936556842](https://github.com/Mopphie/webkweb-Video/actions/runs/38936556842) wurde gestartet. Lokaler Codecommit `2526831`, Remote-Codecommit `a6f357864455cf87c65562b398a3d90b3e97d811`, identischer Tree `f36517dd8f6dfc9bdb0d9fe294c163813f953294`. In diesem ersten Prüflauf keine PR, Signierung, neuen Produkte/Konten/Tester, Apple-Konfigurationsänderungen, TestFlight-Uploads oder App-Store-Einreichungen. Tatsächliche abgerechnete Minuten/Kosten nicht abgefragt; autorisierte Actions-Nutzung, keine neuen Dienste gebucht.

## Erster Xcode-Lauf: Ergebnis und weiterer belegter Fehler

Run **38936556842** endete insgesamt **FAILURE**. Der unsignierte Release-Simulator-Build bestand. Alle **71/71 nativen Tests**, darunter echte Zwei-WebView-Regression mit anschließendem Dokumentwechsel (3,952 s), bestanden. Drei Browser-UI-Fälle bestanden letztlich; der unmutierte Pause-/Resume-Fall benötigte jedoch den vorgesehenen zweiten Versuch. Der iPad-Basisfall scheiterte beim ersten `app.launch()` nach kaltem Simulatorstart (83,082 s, XCTest-Launchtimeout). Die danach gestartete **vollständige PiP-/Appwechsel-/Queue-/Suchreise bestand** ohne Skip oder Retry (93,585 s): echter AVKit-Startzähler 0→1, identische Medien-ID, Uhr 4,000→12,512 s. Dies ist weiterhin ein eigener AVPlayer-Film, kein YouTube-Nachweis.

Die neue Steuerungsdiagnose des fehlgeschlagenen unmutierten Browser-UI-Versuchs liefert einen konkreten Appfehler: echte Eingabe um **17:12:52,115 UTC**, erst um **17:12:57,874 UTC** `observed.stop-rejected` und erneute Pause. Das spätere HTML-`play`-Ereignis traf nach dem bisherigen 1,5-s-Intentfenster ein. Der Play-Aufruf kann `paused` bereits synchron ändern, bevor WebKit nach Audioinitialisierung sein Ereignis ausliefert. Die echte Eingabe wurde dadurch fälschlich als Autoplay behandelt.

Korrektur: Am Ende desselben echten Eingabe-Event-Turns bestätigt ein Microtask ausschließlich einen bereits angeforderten, nicht pausierten Player. Er ruft niemals `play()` auf. Ein neuer Stop verwirft die Intentidentität; spätere unabhängige Autoplay-Versuche erhalten keine längere Freigabe. Die Host-Touch-Beobachtung erfasst ihren Intent vor dem Anbringen der Stopprüfungen, damit ein bereits angeforderter Systemkontrollstart nicht vorzeitig pausiert wird. Private verspätete Startbestätigungen bei gesperrter/verborgener App bleiben abgewiesen. Zwei deterministische neue Regressionen scheitern mit dem gespeicherten bisherigen JS (53/55 bestehen, 2 scheitern) und bestehen mit der Änderung (zusammen mit Compliance **62/62**). Ausdrücklicher Stop, abgelaufene Eingabe und synthetische Klicks bleiben wirksam geprüft.

Der CI-Simulator wird vor dem nächsten iPad-XCTest-Aufruf ausdrücklich mit `simctl bootstatus -b` fertig gebootet. Kein Startfehler wird als bestandener App-Test umgedeutet. Der nächste vollständige signierte TestFlight-Lauf darf nur nach bestandenen Prüfungen hochladen. Er dient den belegten Start-/Tab-Fixes und der Appwechsel-Diagnose; **kein bestätigter YouTube-Hintergrundfix**.
