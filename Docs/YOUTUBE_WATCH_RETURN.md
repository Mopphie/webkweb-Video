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

**iOS-Ausführung dieses Stands: NOCH AUSSTEHEND.** Eigene HTML-/H.264-Testmedien sind kein YouTube-Test. Echte YouTube-Gesten, Website-PiP, Appwechsel, Sperrbildschirm, Account-/Regional-/Inhaltsgrenzen sowie AirPlay/BT bleiben gesonderte Geräteprüfungen.

## Externe Aktionen und Release

Ein autorisierter TestFlight-Lauf wird erst mit dem lokalen Commit gestartet. Upload erst nach den vorgeschalteten iOS-Prüfungen. Tatsächliche Lauf-, Commit- und Buildnummern werden nach Ausführung ergänzt. Keine App-Store-Einreichung, neuen Produkte, Verträge oder Dienste. Die App ist damit noch nicht vollständig technisch releasebereit; insbesondere bleibt R03 offen.
