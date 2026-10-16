# YouTube: Rückweg, PiP und Appwechsel — 16.10.2026

## Ausgangspunkt und Nutzerbefund

Lokaler Ausgangscommit `c832ff80c91b32893f973e101fd6d7585eb67f6f`, sauberer Arbeitsbaum; neuer Branch `local/youtube-watch-return-20261016`. Letzter unabhängig bestätigter TestFlight-Stand ist 0.1.0 (7). Der Nutzer meldet erneut: Herunterwischen stellt die normale YouTube-Ansicht nicht her, PiP funktioniert nicht, Video pausiert beim Verlassen der App. Die Buildnummer dieses neuen Berichts wurde nicht erneut bestätigt. Der frühere erfolgreiche Test mit eigenen AVPlayer-Dateien widerlegt diesen Websitebefund nicht.

## Konkrete Änderungen

- `App/WebView.swift`: Der bisherige Pull-down setzte ein Video bei y=0, eine feste 16:9-Höhe und den Dokumentanfang voraus. Jetzt prüft der gleichzeitige native Pan-Erkenner den tatsächlichen sichtbaren Videobereich im Hauptdokument über einen ausschließlich lesenden Aufruf in der isolierten WebKit-Welt. Scrollposition und Websitekopf sind keine Ausschlussgründe mehr. Koordinaten berücksichtigen den visuellen Viewport. Normales Scrollen außerhalb des Videos ändert die Appansicht nicht. Verzögerte Antworten verfallen; Antworten zu einem anderen Dokument/Tab werden verworfen. Websitegesten werden nicht abgebrochen.
- `App/BrowserView.swift`: Pull-down und sichtbarer Abwärtspfeil rufen `showNormalWebsite()` auf. Sie laden keine andere Seite, springen nicht in der Historie und lösen keine neue Wiedergabe aus. Der ausdrücklich benannte Menüpunkt „Video verlassen“ und die separate YouTube-Startseite bleiben für tatsächliche Navigation verfügbar. Auch die native obere Leiste lässt sich herunterziehen. Keine große Mediensteuerung hinzugefügt.
- `App/BrowserSession.swift`: Öffentliche `WKPreferences.isElementFullscreenEnabled = true` erlaubt den von der Website selbst angeforderten Element-Vollbildmodus. Apples dokumentierter Standardwert ist false. Die bestehende normale HTML-PiP-Erlaubnis bleibt eingeschaltet; für private Tabs bleibt sie ausgeschaltet. Der bisher leere `attemptAutoPiP()`-Aufruf wurde entfernt, weil er überhaupt keine Aktion ausführte.
- Normale, nur lokal erzeugte Diagnosen enthalten zusätzlich die opake Medienkennung, um einen unbeabsichtigten Dokument-/Playerwechsel nachzuweisen. Keine Medienadresse oder Titel hinzugefügt; private Diagnosen bleiben vollständig gesperrt.

## Getrennte Bewertung von PiP und Hintergrund

**Weiter offen für YouTube.** Eine WebKit-Konfigurationsfreigabe startet kein PiP. Die öffentliche native AVPlayer-Option zum automatischen PiP kann nicht auf WebKits internen Player übertragen werden. Kein privater Controllerzugriff, keine Streamextraktion, kein erzwungenes Resume beim Verbergen, keine geänderte Browseridentität oder Anbieterberechtigung.

Die neue Vollbildfreigabe ist eine Korrektur des normalen Browserumfangs, noch kein Nachweis, dass YouTube daraufhin PiP anbietet oder Hintergrundwiedergabe fortsetzt. Anbieter, Konto, Medienart, iOS und der tatsächlich angebotene Playerweg müssen am Gerät geprüft werden. Die konkrete Ursache des gemeldeten Hintergrundstopps ist weiterhin nicht belegt. Das absichtliche Pausieren privater Tabs beim Verlassen bleibt erhalten.

## Primärquellen und Bedingungen

Am 16.10.2026 erneut abgerufen:

- [Apple: isElementFullscreenEnabled](https://developer.apple.com/documentation/webkit/wkpreferences/iselementfullscreenenabled): öffentlich ab iOS 15.4, Standard false; bei Vollbild entfernt WebKit die WebView vorübergehend aus der App-Viewhierarchie. Deshalb ein echter Ein-/Austrittstest, nicht nur ein Konfigurationsvergleich.
- [Apple: allowsPictureInPictureMediaPlayback](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowspictureinpicturemediaplayback): erlaubt HTML5-PiP, Standard true; kein Startversprechen.
- [YouTube: Bild im Bild, iPhone/iPad](https://support.google.com/youtube/answer/7552722?hl=de&co=GENIE.Platform%3DiOS): beschreibt ausdrücklich die YouTube-App und Einschränkungen für Musikinhalte. Daraus folgt weder eine pauschale Premium-Pflicht für jedes PiP noch eine besondere Freigabe für eigene Drittanbieter-WebView-Erweiterungen.

Keine neue Komponente, Datenlizenz, API oder Drittanbieter-SDK. Öffentliche Apple-Frameworks unterliegen weiter den Apple-Verträgen. Die Änderung erweitert keine Mediennutzungsrechte und umgeht keine YouTube-Beschränkung.

## Prüfungen

Lokal unter Linux tatsächlich ausgeführt: 63/63 Node-Regressionen, 31/31 Foundation-Tests im bereits vorhandenen offiziellen Swift-6.1.3-Container ohne Netzwerk, Swift-Syntaxprüfung sowie 17/17 Python-Tests. Keine lokalen Apple-SDK-/Simulator-/Gerätetests möglich.

Neue iOS-Tests: Pull-down auf tatsächlich gescrolltem Video, gleicher opaker Medienkennung und fortlaufender Medienzeit; sichtbarer Rückweg mit gleicher Kennung; Kommentar-Pull ohne Ansichtswechsel und anschließender Pull auf der nativen Leiste; tatsächlicher Website-Element-Vollbild-Ein-/Austritt mit `fullscreenchange`/`document.fullscreenElement`. Zusätzlich Konfigurationsprüfung für normale und private Tabs.

Zusätzlicher eigener WebKit-Test in `UITests/BrowserWebPlaybackJourneyUITests.swift` / `Scripts/check-webkit-playback.sh` (`1d286df`): hörbares HTML-Video innerhalb derselben WKWebView → vom Fixture selbst aufgerufener öffentlicher Website-Systemvollbildplayer → tatsächlicher System-PiP-Knopf → Safari im Vordergrund → Rückkehr, gleiche Medienkennung, beobachteter HTML-PiP-Modus und zur Wandzeit passende Medienzeit → echter SpringBoard-PiP-Rückkehrknopf → normale Browseransicht. Ein Framework-Ergebnis „PiP nicht unterstützt“ darf nur als nicht ausgeführte Pflichtreise protokolliert werden. Fehlende Knöpfe, falscher Modus oder stockende Zeit sind Fehler. Ausschließlich Debug-Testfixture erweitert; das Release enthält diesen Startpfad nicht.

**iOS-Ausführung dieses Stands: NOCH AUSSTEHEND.** Eigene HTML-/H.264-Testmedien sind kein YouTube-Test. Echte YouTube-Gesten, Website-PiP, Appwechsel, Sperrbildschirm, Account-/Regional-/Inhaltsgrenzen sowie AirPlay/BT bleiben gesonderte Geräteprüfungen.

## Externe Aktionen und Release

Ein autorisierter TestFlight-Lauf wird erst mit dem lokalen Commit gestartet. Upload erst nach den vorgeschalteten iOS-Prüfungen. Tatsächliche Lauf-, Commit- und Buildnummern werden nach Ausführung ergänzt. Keine App-Store-Einreichung, neuen Produkte, Verträge oder Dienste. Die App ist damit noch nicht vollständig technisch releasebereit; insbesondere bleibt R03 offen.

Gestartet: [Release-Prüfung 38964934031](https://github.com/Mopphie/webkweb-Video/actions/runs/38964934031), Remote `5d348f5eb65fe553a46afd6b65055ba97a03ccaf`, Baum `735b10076e018abd02fb8b2390dfe42efe410833` identisch zu lokal `bbe2d49`. Unabhängiger, unsignierter [WebKit-Test 38965491481](https://github.com/Mopphie/webkweb-Video/actions/runs/38965491481), Remote `c6f0d811fbc5afd52165ebb80e7919ebbe1e409d`, Baum `de3402a93fc0dd352527f0d8c2f7b30ab081c667` identisch zu lokal `1d286df`. Kein Upload im WebKit-Testworkflow. Ergebnisse beim Start noch nicht bekannt; keine neue Buildnummer als verfügbar behauptet.

### Erster iOS-Durchlauf: fehlgeschlagene Tests, kein Upload

- Release-Lauf 38964934031: **73/73 native Tests bestanden**, alle Swift-/UIKit-/WebKit-Testtargets kompiliert. Die drei bisherigen Browser-UI-Tests bestanden. Drei neue Navigationstests erreichten erfolgreich die wiederhergestellte Browseransicht und Medienidentität, scheiterten anschließend an einer falschen Testannahme: `sample.mp4` dauert 4 Sekunden, der wiederverwendete Langzeitprüfer verlangt über 59 Sekunden. Statt seine Aussagen abzuschwächen verwenden diese Fälle nun den vorhandenen 60-Sekunden-Clip `audible.mp4` mit tatsächlichem Play-Tipp. Der Element-Vollbildtest erreichte auf dem iPhone nicht den eigenen HTML-Exit; native Video-Vollbildrückkehr wird dort gesondert geprüft. Element-API-Verfügbarkeit wird im tatsächlichen Dokument ermittelt und auf dem iPad separat getestet. Keine nachträgliche Erfolgsbehauptung für die fehlgeschlagenen Fälle.
- WebKit-Lauf 38965491481: **fehlgeschlagen, kein erfolgreicher PiP-/Hintergrundnachweis**. Der Test fand den real vorhandenen Systemknopf nicht: Die aufgezeichnete Oberfläche enthält `identifier: 'PIP Button', label: 'Video minimieren'`; der Test suchte ausschließlich nach Bild-in-Bild-/Picture-in-Picture-Text. Der Selektor verwendet nun zusätzlich die tatsächlich beobachtete Kennung. Das ist ein Testfehler, kein Nachweis einer fehlenden PiP-Fähigkeit und noch kein erfolgreicher PiP-Eintritt.
- Beide Läufe sind insgesamt fehlgeschlagen. Kein Archiv/Export/Upload in diesem Reparaturversuch, bestehender Beta-Build 7 bleibt der letzte bestätigte Stand. Der nächste Release-Lauf prüft außerdem beide WebKit-Fälle zusammen mit den bestehenden iPad-Nativfällen. Keine Produktions-PiP-Erzwingung hinzugefügt.

Erneuter vollständiger Lauf: [38967317130](https://github.com/Mopphie/webkweb-Video/actions/runs/38967317130), Remote `03d7700e614889055648a2dcaa355dd5bc7a1561`, Baum `3268a4db63ab3cb1f09346b3f7562f2967d63ed2` exakt wie lokaler Commit `361c36b`. Enthält 73 native, 7 iPhone-Browser- und die beiden bestehenden nativen plus zwei getrennte Websitefälle auf dem iPad. Beim Eintragen noch laufend. Keine weitere Änderung am Release-Anwendungscode gegenüber `bbe2d49`; spätere App-Differenzen betreffen ausschließlich die Debug-Testfixture.

## A–J: nachvollziehbarer Stand dieses Reparaturauftrags

A. Rückweg im Code korrigiert: keine Dokumentanfangs-/16:9-Annahme, kein Seitenwechsel beim Pull/Pfeil, sichtbare Alternative und native Leiste. Vollständige neue iOS-Freigabe noch in Prüfung.

B. Normale öffentliche Website-Element-Vollbildfreigabe ergänzt; tatsächliche Systemvideo-/PiP-/Safari-Tests implementiert. Kein YouTube-PiP-/Hintergrundfix als bewiesen ausgegeben.

C. Der leere `attemptAutoPiP()`-Aufruf wurde entfernt. Keine funktionierende Websitefunktion, Nutzermedien, Favoriten oder Notizen entfernt. Keine entfernte Werbe-/SponsorBlock-/Extraktionsintegration reaktiviert.

D. Bestehende öffentliche Apple-Frameworks und eigener Code, keine neue SDK-/Datenlizenz. Technische Primärquellen oben/Abrufregister; Apple-Verträge und getrennte Medien-/Dienstrechte gelten weiter. Keine pauschale weltweite Nutzungsfreigabe.

E. Aktuelle YouTube-Diagnose vom iPhone angefragt (Video starten → Home → zurück → Playerdiagnose kopieren); noch nicht eingegangen. Echte YouTube-Wiedergabe, angebotener PiP-Weg, Account-/Inhalts-/iOS-Grenzen und Ursache des Hintergrundstopps bleiben offen. Bestehende R05/R06 bleiben unverändert.

F. 63 Node-, 31 Foundation- und 17 Python-Tests lokal erfolgreich, Swift-Syntaxprüfung erfolgreich. Erster iOS-Lauf: 73 native Tests und 3 bestehende Browserfälle erfolgreich; 4 neue Fälle fehlgeschlagen, Details oben. Separater erster WebKit-PiP-Test fehlgeschlagen am Selektor. Erneuter Lauf noch nicht abgeschlossen.

G. Keine physischen iPhone-/iPad-, YouTube-, AirPlay-/BT-/Headset-/Sperrbildschirm-/Netzwechseltests dieses Stands ausgeführt. Keine lokale Xcode-Umgebung; iOS-Prüfungen ausschließlich auf den genannten autorisierten macOS-Runners.

H. Lokale Commits `bbe2d49` (Anwendung), `1d286df` (WebKit-Nachweis), `30a65af` (Register/Matrix), `361c36b` (Testkorrekturen und gemeinsame Prüfkette); separater lokaler Branch, Nutzerhistorie und vorhandene Daten erhalten. Remotequellen/Läufe oben.

I. Drei autorisierte macOS-Actions-Läufe gestartet; zwei fehlgeschlagen, dritter noch laufend. Zu diesem Zwischenstand kein neuer Upload. Keine App-Store-Einreichung, Kontoregistrierung, neuen Tester/Gruppen/Produkte, Verträge oder gebuchten Dienste. Tatsächliche Abrechnung/CI-Minuten nicht abgerufen, daher keine Kostenfreiheit behauptet.

J. **Noch nicht vollständig technisch releasebereit:** neue iOS-Abnahme läuft; YouTube-PiP und Hintergrundverhalten am Nutzergerät bleiben R03, weitere Geräte-/Betreiber-/Rechtenachweise R04–R06. Ein interner Beta-Test ersetzt diese Freigaben nicht.

## Zweiter iOS-Durchlauf und nachgewiesener weiterer Startfehler

Run 38967317130 insgesamt **fehlgeschlagen, kein Upload**. 73/73 native Tests erneut bestanden. Auf dem iPhone bestanden Kommentar-/Leisten-Pull (21,530 s), Pull auf dem gescrollten Video mit gleicher Medienkennung und weiterlaufender Zeit (18,073 s) und sichtbarer Rückweg (16,534 s), jeweils erster Versuch. Die bisherigen Menü- und Stop/Touch-Fälle bestanden. Der hörbare Stop-/Resume-Fall scheiterte im ersten Versuch und bestand erst im Retry (kein fehlerfreier Gesamtnachweis). Der zusätzliche native Website-Vollbildfall fand die vom iPad übernommene `Close Button`-Kennung auf dem iPhone nicht. Die danach angeordneten iPad-Fälle wurden wegen des frühen Scriptabbruchs nicht ausgeführt.

Die hörbare Diagnose enthält echte Eingaben um 21:15:39,647/39,705 UTC und `observed.stop-rejected` erst um 21:15:47,018 UTC, ohne zwischenzeitlichen neuen Nutzungsstopp. Deshalb weitere Anwendungskorrektur:

- Nicht nur eine einzelne Nullverzögerungsaufgabe: kurze, auf höchstens 30 Folgeproben begrenzte Beobachtung desselben Eingabeversuchs. Die normale Frist bleibt 1,5 Sekunden. Kein Aufruf von `play()` und kein Wiederaufnehmen wegen Sichtbarkeitswechsel.
- Ein noch tatsächlich laufender, vertrauenswürdiger DOM-Eingabedispatch kann durch Audioinitialisierung blockiert sein. Seine reale `eventPhase` und Ereignisidentität bleiben als Eingabenachweis für höchstens 15 Sekunden gültig; ein abgeschlossenes Ereignis berechtigt keinen späteren Autoplay. Eine Bubble-Beobachtung bestätigt nur bereits angeforderte Wiedergabe.
- Jede solche Bestätigung transportiert den **ursprünglichen** Eingabezeitpunkt. Swift prüft ihn gegen den neuesten nativen Stopzeitpunkt, plausible Uhrzeit und Alter (`MediaPolicy.acceptsPlaybackInput`). Ein neuerer Stop/Timer gewinnt auch dann, wenn der WebContent-Prozess den Stopbefehl noch nicht verarbeitet hat. Private Hintergrund-/Sperrgrenzen bleiben zusätzlich bestehen.
- Tests suchen den tatsächlichen Vollbild-Rückweg auch über vorhandene Systembezeichnungen wie Fertig/Done/Schließen und zeigen bei Fehlern die eigene Fixture-Hierarchie. Ein iPhone-Browserfehler lässt künftig die unabhängigen iPad-Prüfungen weiterlaufen; der Gesamtfehler blockiert den Upload weiterhin.

### Lokale Gegenproben

Vorheriger Skripthash `6c2c3b85abb7342c4fa6ce837bd070903e9f716be5f29936d93ec9d7d336e2a3`:

- Neuer Node-Fall „angeforderter Start wird erst nach der ersten Aufgabe sichtbar“ zunächst fehlgeschlagen (64/65); neuer Fall „vertrauenswürdiger Dispatch blockiert während Audiostart“ vor der zweiten Korrektur fehlgeschlagen (66/67).
- Realer Chromium-Fall `blocked-trusted-dispatch`: mit vorherigem Skript **FAIL**, echtes Video pausiert bei 0,005088 s trotz vertrauenswürdigem Klick. Eine lediglich um 100 ms verzögerte Startanforderung bestand auch mit dem alten Skript; sie ist **kein** positiver Fehlerreproduktionsnachweis.
- Aktueller Skripthash `cd2c0d9b0b0c012329269c38e8636d6686f92e174ad3138e6afb9277a01c9cf1`: **68/68 Node**, **22/22 echte Chromium-Medienfälle** inklusive blockiertem Eingabedispatch, **32/32 Foundation**, Swift-Syntax und **17/17 Python** erfolgreich. UIKit/YouTube werden dadurch nicht getestet. Die neue Stopzeitprüfung wurde lokal gegen ältere Eingaben, neueren Stop, fehlende/ungültige/zukünftige Zeitwerte geprüft.

Diese Änderung ist eine echte neue Release-Anwendungskorrektur und benötigt daher erneut die vollständigen iOS-Prüfungen. Kein Wiederverwenden eines alten SDK-/Geräteergebnisses für den veränderten Skript-/Bridgepfad.
