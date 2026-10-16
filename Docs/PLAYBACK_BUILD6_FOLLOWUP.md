# Build 6: Pause beim Verlassen der App — 16.10.2026

## Tatsächlicher Befund

Der Nutzer meldet DevnTube **0.1.0 (6)**, `m.youtube.com`, und präzisiert: Die Pause passiert **beim Verlassen der App**. Sein freiwillig geteilter Diagnoseauszug vom 16.10.2026, 16:41:32–16:42:27 UTC enthält echte dekodierte Videobilder (315), Medienzeit 25,277 s bei 1669,121 s Dauer, `readyState=4`, `paused=true`, `waiting=false`, Filter aus, globale und JS-Stoppsperre aus, Restore-Suspendierung aus. Dies belegt zeitweilige Wiedergabe mit anschließender Pause; weder ein durchgehend kaputter Decoder noch die Ursache der Pause ist damit bewiesen. Kein eigener Live-YouTube-Gerätetest.

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

Weder eine Plattformpause noch deren Umgehung ist durch diesen Auszug bewiesen. **Der gemeldete YouTube-Hintergrundstopp bleibt offen.** Kein Stream-Extraktions-, Werbe-, Premium-, Sichtbarkeits- oder Keep-alive-Workaround ergänzt. Normale vom Dienst angebotene Playerfunktionen bleiben erhalten. Ein Test mit eigener HTML-Datei ist kein Live-YouTube-Nachweis.

## Prüfungen dieser Änderung

- **58/58 Node-Tests bestanden**; darunter tatsächlicher gebündelter JS-Code, Sichtbarkeitswechsel ohne automatisches Resume, diagnostische Ereignisse und ausschließlich lesender PiP-Zustand.
- **31/31 Foundation-Tests bestanden**, Swift-Parser für App/Shared/Widgets/Tests/UI-Tests erfolgreich; offizieller lokal vorhandener Swift-6.1-Container, ohne Netzwerk. Kein Apple-SDK-Build daraus abgeleitet.
- **14/14 Python-Helfermocks bestanden**.
- **19/19 echte Chromium-Decoderfälle bestanden**, ausschließlich eigene Loopback-Testmedien.
- Neue iOS-Regressionen: Tabfreigabe/verspäteter Start/Navigation, getrennte private Diagnose sowie zwei echte WKWebViews einschließlich Autoplay und Dokumentwechsel. **Noch nicht unter Xcode ausgeführt.**
- Build 6 selbst hat bereits einen bestandenen nativen iPad-Simulator-PiP-/Appwechsel-/Rückkehrtest mit eigenem AVPlayer-Film. Diese Quelle ist von YouTube getrennt. Auf dem iPhone des Nutzers ist das aktuelle YouTube-Hintergrundproblem weiterhin reproduziert; kein erfolgreicher Fix dafür behauptet.

Prüfprotokolle lokal unter `build/reports/playback-ownership-*`; keine Zugangsdaten oder Original-Video-URLs gespeichert. Branch `local/playback-tab-ownership-20261016`, Ausgangspunkt `3533e93`.
