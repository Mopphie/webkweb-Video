# Prüfung vor einem Release

## TestFlight 0.1.0 (Build 5), 16.10.2026

Der Nutzer bestätigt den Fehler in **Build 4**: Dasselbe YouTube-Video läuft in Safari, bleibt in der App nach kurzem Start stehen. Die Aufnahme zeigt Stillstand um 2:18 und eine Ladeanzeige. Die tatsächliche YouTube-Wiedergabe auf diesem iPhone ist deshalb weiterhin gesondert zu bestätigen; bestandene lokale Fixtures ersetzen diesen Nachweis nicht.

Der neue Stand behebt mehrere nachgewiesene Fehler der App-Steuerung:

- Eine Audio-Unterbrechungsnachricht setzt keine dauerhafte globale Timer-/Autoplay-Sperre mehr. WebKit verarbeitet seine Systemunterbrechung. Eine neue Nutzerpause oder abgelaufene Deadline verhindert weiterhin automatisches Resume.
- Die Audiokategorie wird vor dem Start vorbereitet. Die App übernimmt die Audiositzung bei einem ausdrücklichen nativen Play-Befehl; sie aktiviert sie nicht nachträglich aufgrund bloßer Webseiten-Play-Meldungen. Eine verspätete Pausebestätigung deaktiviert die für Play angeforderte Sitzung nicht sofort. Ruhiges Freigeben erfolgt nach erneutem Zustandsabgleich. Apples [Hinweise zu `setActive`](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:)) erläutern die Wirkung einer Deaktivierung auf laufende Audioobjekte.
- Die Ladeanzeige berücksichtigt Pause, Ende und Bereitschaft. Ein `stalled`-Ereignis bedeutet bei vorhandenem Puffer keinen Wiedergabestillstand. Beide neuen Pufferfälle scheitern gegen die unveränderte Build-4-Bridge und bestehen nach der Korrektur.
- „Playerdiagnose kopieren“ liefert nach bewusstem Antippen einen lokalen Bericht mit höchstens 40 Ereignissen. Er nennt bei normalen Tabs nur den Host, bei privaten Tabs keinen Host; keine vollständigen Webseiten-/Medienadressen, Parameter, Titel, Cookies oder Inhalte. Keine automatische Übertragung; lokale Zwischenablage mit fünf Minuten Ablaufzeit. [Technische Datenschutzhinweise](../PRIVACY.md).

**Verifizierter Release-Lauf:** [38880644099](https://github.com/Mopphie/webkweb-Video/actions/runs/38880644099), geprüfter und hochgeladener Commit `9b9f6c301cc464570e1ba7d7fd084e53c367e337`:

- **46/46 native Unit-/WK-Methoden und 3/3 XCUITests bestanden**, keine Fehler. Der UI-Test mit Ton bestand in 81,842 Sekunden. Er startet ein selbst erzeugtes 60-Sekunden-H.264/AAC-Medium mit echtem Nutzertipp, verlangt vor und nach nativer Pause jeweils drei echte Medienzeit-Fortschritte und prüft laufende Wiedergabe ohne Lade-/Stop-Sperre. Start/Resume bleiben auf 15/8 Sekunden begrenzt. Framezähler sind nur optionale Diagnose: Das Simulatorbackend meldete zuvor trotz Zeitfortschritt 0.
- Die native Audio-Integration prüft mehr als fünf Sekunden realen Zeitfortschritt ohne Stummschaltung. Gezielt injizierte Unterbrechungsnachrichten prüfen die App-Reaktion sowie Nutzerpause und Timergrenzen; sie simulieren keine echte Telefon-/Hardware-Unterbrechung.
- **55/55 Node-Tests und 10/10 Release-Helper-Tests** bestanden im selben Mac-Lauf. Separat bestanden **19/19 Chromium-Medientests** gegen dieselbe Playback.js-Prüfsumme. Der MSE-Fall puffert bei tatsächlich fehlenden Fragmenten, pausiert und läuft nach weiterem Anhängen mit Ton fort. Der gepufferte `stalled`-Hinweis wird gezielt injiziert. 26 Swift-Dateien wurden zusätzlich unter Linux syntaktisch geprüft; das ist kein weiterer SDK-Build.
- Zertifikat und beide Profile geprüft; signiertes Gerätearchiv und IPA-Export erfolgreich. Die exportierten App-/Widget-Plists bestätigen übereinstimmend **0.1.0 / Build 5**. Apple meldete **`UPLOAD SUCCEEDED with no errors`**, danach **`processing_state=VALID`**, **`internal_state=READY_FOR_BETA_TESTING`**. Build-ID: `5f82928b-c304-4e5a-9067-7e04ea9274f6`.

[App Store Connect / TestFlight](https://appstoreconnect.apple.com/apps/6822711093/testflight): Der Build ist verarbeitet und für internes Beta-Testen bereit. **Eine aktive Testgruppenzuordnung oder jeder einzelne Testerzugang ist nicht bestätigt.** Der API-Schlüssel kann Beta-Gruppen nicht lesen/verwalten (HTTP 403); die Übernahme der bisherigen internen Gruppe konnte deshalb nicht durchgeführt oder geprüft werden. Falls Build 5 nicht in TestFlight erscheint, muss er in App Store Connect der bestehenden internen Gruppe hinzugefügt werden. Keine Gruppen erstellt, keine Tester eingeladen, keine App-Store-Einreichung.

Vorherige rote Versuche führten zu keinem Upload:

| Lauf / Code | Tatsächliches Ergebnis |
| --- | --- |
| `38872425343`, `0db77f3`, Versuch 1 | 46 native Methoden bestanden; erster UI-App-Start lief in ein Xcode-Timeout, zwei weitere UI-Tests bestanden. |
| Derselbe Lauf, Versuch 2 | Wieder 46 native Methoden bestanden; echter Resume-Fehler im UI-Test mit Ton. Der Menütest führte seine Assertions aus, überschritt einschließlich Start/Quiescence aber die 120-Sekunden-Grenze. |
| `38875399452`, `e08c265` | 46 native Methoden und zwei UI-Tests bestanden; der hörbare Test erreichte die Resume-Prüfung wegen seiner Autoplay-Setup-Annahme nicht. |
| `38877034822`, `bc4c556` | Start und Resume mit echtem Tipp bestanden, eine spätere Zustandstext-Abfrage scheiterte bei der kurzen Schleife. |
| `38879063872`, `bf2f8a3` | 46 native Methoden und zwei UI-Tests bestanden; der verpflichtende Framevergleich scheiterte am vom Simulator gemeldeten Nullzähler. |

Der aktuelle grüne Lauf prüft deshalb tatsächlichen Medienzeit-Fortschritt mit langer eigener Fixture; er überspringt keinen Play-/Pause-/Resume-Fall. UI-Gesamtlaufzeit maximal 180 Sekunden, Preflight maximal 20 Minuten. Diagnose-Hooks und Testmedien werden nicht in die Release-App aufgenommen; die freiwillige Playerdiagnose bleibt Teil der App. Nachfolgende reine Ergebnisdokumentation ändert keine App-/Widget-/Bridgequellen des getesteten Commits. Die konkrete YouTube-Ursache, der Filtereinfluss, echte Telefon-/Routenwechsel sowie die Wiedergabe auf dem Nutzergerät bleiben offen.


## Nachbesserung nach TestFlight-Build 3

Der Nutzer meldete YouTube mit Vorschaubild/Ladekreis, fehlenden Swipe-Rückweg und ein springendes, unbedienbares ⋯-Popup. Ein erfolgreicher Fixture-/Uploadtest wird deshalb ausdrücklich nicht als Bestätigung dieser realen Gerätefunktionen gewertet.

- Das Popup wird durch ein modales Bedienfeld mit festen, großen Aktionen ersetzt. Zurück und YouTube-Start sind im Videomodus direkt erreichbar; ein Abwärtsswipe aus dem oberen Videobereich verlässt die Ansicht. Die normale Website derselben URL lässt sich wiederherstellen.
- Ein echter Play-Tipp darf eine vorherige native Pause-/Timer-Sperre lösen. Script-Autoplay und synthetische Klicks bleiben blockiert. WebKit-eigene Controls werden über eine echte UIKit-Berührung und die isolierte Medien-Bridge erfasst.
- Wiederhergestellte Tabs erhalten dieselbe WebKit-Wiedergabepolicy wie neue Tabs. Öffentliche Laufzeit-Suspension und ein isolierter Start-Pause-Bootstrap halten passive Tabs bis zu einer bewussten Nutzeraktion still. Explizites Öffnen/Play hängt nicht mehr dauerhaft an der strengeren Startkonfiguration.
- „Ohne Filter neu laden“ ist als gezielte Wiederherstellung erreichbar. Ein genereller CDN-Block der aktuellen Standardliste wurde nicht nachgewiesen.

**Lokaler Prüfstand:** 53/53 Node-Tests und 17/17 Chromium-Medientests bestanden. Der Webseiten-Play-Regressionstest war mit der unveränderten Build-3-Bridge rot. Der Chromiumtest für native Mediencontrols emuliert nur den Host-Callback; die echte UIKit-Eingabe wird zusätzlich durch XCUITest geprüft. Die konkrete YouTube-Wiedergabe am Gerät bleibt gesondert zu bestätigen.

Der erste [native Nachbesserungslauf 38865583384](https://github.com/Mopphie/webkweb-Video/actions/runs/38865583384) kompilierte und bestand beide XCUITests: Bedienfeld/Filter/Normalansicht bei laufendem Video sowie erster tatsächlicher UIKit-Tipp nach nativer Pause. Zwei der 42 Unit-/WK-Testmethoden scheiterten mit drei Assertions: Der `@Published`-Auswahlbeobachter gab während der Session-Initialisierung den ersten wiederhergestellten Tab versehentlich frei. Ein expliziter Initialisierungszustand verhindert das jetzt; die beiden Regressionstests bleiben unverändert. Signierung und Upload wurden wegen des roten Preflights übersprungen. Der unten dokumentierte Folgelauf bestätigt den vollständig korrigierten Stand.

## TestFlight 0.1.0 (Build 4), 16.10.2026

Der [korrigierte Release-Lauf 38867655473](https://github.com/Mopphie/webkweb-Video/actions/runs/38867655473) für Commit `2a64965b8a0704ae4e4d63d8d9b860bba41424c4` ist vollständig erfolgreich. Dies war der geprüfte Beta-Stand; die spätere Gerätemeldung zeigte weiterhin einen YouTube-Fehler.

- **42/42 native Unit-/WK-Tests und 2/2 XCUITests**, keine Fehler. Beide zuvor roten Restore-Tests bestehen unverändert. Der Menü-/Normalansichtstest bestand in 43,946 Sekunden, der erste echte UIKit-Tipp nach Pause in 31,574 Sekunden. Die Medien sind selbst erzeugte H.264/AAC-Fixtures.
- **53/53 Node-Tests und 10/10 Release-Helper-Tests** bestanden im selben Mac-Lauf. Separat bestanden lokal 17/17 Chromium-Medientests gegen dieselbe Playback.js-Prüfsumme.
- Zertifikat und beide Profile geprüft; signiertes Gerätearchiv und IPA-Export erfolgreich. Die exportierten App-/Widget-Plists bestätigen **0.1.0 / Build 4**. Apple meldete **`UPLOAD SUCCEEDED with no errors`** und anschließend **`processing_state=VALID`**, **`internal_state=IN_BETA_TESTING`**. Build-ID: `71afbba6-068a-47b2-959c-499ad5f9f552`.
- [App Store Connect / TestFlight](https://appstoreconnect.apple.com/apps/6822711093/testflight). Der API-Schlüssel kann einzelne Beta-Gruppen weiterhin nicht lesen/verwalten; konkrete Gruppenmitgliedschaft und jeder einzelne Testerzugang sind damit nicht bestätigt. Es wurden keine Tester eingeladen oder Gruppen erstellt.

Der überholte Zwischenlauf `38865836570` wurde vor Signierung und Upload abgebrochen. Nach Abschluss des erfolgreichen Laufs sind künftige Uploads wieder serialisiert; der Preflight bleibt auf 20 Minuten und einzelne XCTest-Fälle auf 120/maximal 180 Sekunden begrenzt. Nachfolgende Dokumentations-/Workflowänderungen ändern keine App-/Widget-/Bridgequellen des geprüften und hochgeladenen Commits.

Die konkrete YouTube-Wiedergabe ist aus dieser Umgebung wegen Netzwerk-403 nicht live geprüft. Der Swipe-Rückweg ist implementiert; die UI-Tests bestätigen Bedienfeld, Normalansicht und erreichbare direkte Navigationsknöpfe, keinen Live-YouTube-Swipetest. Echte iPhone-/iPad-/Diensteprüfungen bleiben erforderlich. Es erfolgte keine App-Store-Einreichung oder Veröffentlichung.

## TestFlight 0.1.0 (Build 3), 16.10.2026

Der [freigegebene TestFlight-Lauf 38862276281](https://github.com/Mopphie/webkweb-Video/actions/runs/38862276281) für Release-Commit `ff827ff` ist erfolgreich abgeschlossen. Die App-/Widget-/Bridgequellen entsprechen dem zuvor geprüften Stand; geändert wurden ausschließlich Releasepipeline und Dokumentation.

- 10/10 Pipeline-Helper-Tests, 44/44 Node-Tests und erneut **38/38 native Simulator-XCTests** bestanden.
- App Store Connect bestimmte Buildnummer **3**. Beide Distribution-Profile und das Zertifikat wurden geprüft; signiertes Gerätearchiv und IPA-Export bestanden. Die exportierten App-/Widget-Plists bestätigen übereinstimmend Version **0.1.0 / Build 3**.
- Apple meldete **`UPLOAD SUCCEEDED with no errors`** und danach **`processingState=VALID`**, **`internalBuildState=IN_BETA_TESTING`**. Build-ID: `7a7fe28c-9dbe-4fd6-9f4a-9b480522cda2`.
- [Build in App Store Connect / TestFlight öffnen](https://appstoreconnect.apple.com/apps/6822711093/testflight). Einzelne Beta-Gruppen konnte der API-Schlüssel wegen HTTP 403 nicht lesen oder verwalten. Eine konkrete Testgruppenzuordnung oder jeder einzelne Testerzugang wird deshalb nicht als geprüft bezeichnet; der Apple-Buildstatus ist bestätigt. Es wurden keine Gruppen erstellt oder Tester eingeladen.

Signierungsmaterial wurde anschließend vom Runner entfernt. Der Upload ist eine TestFlight-Beta und keine App-Store-Veröffentlichung. Reale iPhone-/iPad-/Diensteprüfungen und Release-Metadaten bleiben getrennt vom erfolgreichen Build-/Uploadnachweis.

## Wiedergabeprüfung ab 16.10.2026

Actions sind seit der ausdrücklichen Nutzerfreigabe am 16.10.2026 für Builds und Tests jederzeit erlaubt. Der [native Lauf 38860463443](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443) für Code `24d961f` ist erfolgreich abgeschlossen:

- **38/38 native XCTest-Fälle**, keine Fehler, mit Xcode 26.6 auf iPhone 17 Pro / iOS 26.5 im Simulator.
- Beide realen WKWebView-Medientests bestanden: Start/Zeitfortschritt/Pause/Seek/Rate/Resume sowie natürliches Ende, N-Video-Timer und Stopp eines tatsächlich gestarteten neuen Autoplay-Players. Das synthetische H.264/AAC-MP4 ist selbst erzeugt.
- **Debug/Test und unsigned Release-Simulatorbuild erfolgreich**, einschließlich Widget-Target. [Simulator-App](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029370391) und [`.xcresult`](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029320581) liegen als GitHub-Artefakte mit sieben Tagen Aufbewahrung vor. Das ist keine signierte iPhone-IPA.
- **44/44 Node-Tests**, **15/15 lokale Chromium-Medientests** mit tatsächlicher Dekodierung sowie portable Struktur-/Plistprüfungen bestanden. 25 Swift-Dateien wurden zusätzlich mit Tree-sitter syntaktisch geprüft; dieser Linux-Parserlauf ist kein zweiter SDK-Build.

Die App- und Testquellen dieses Laufs entsprechen dem veröffentlichten Stand. Nachfolgende reine Dokumentationsänderungen ändern den geprüften Code nicht. Der neue Validierungsworkflow verwendet keine Signing-Secrets und führt keine Apple-Uploads aus. Der frühere rote Lauf ist in der Funktionsmatrix mit Ursache und erfolgreichem Folgelauf dokumentiert.

[Funktionsmatrix](FUNCTION-TEST-MATRIX.md) mit klar getrennten Ebenen und offenen Geräte-/Providerprüfungen.

## Historischer Prüfstand vor den Wiedergabefixes

Linux (15.10.2026): **40/40 Node-Tests** der verbleibenden originalen Seitenskripte bestanden. **24 Swift-Dateien** wurden mit Tree-sitter nur syntaktisch geprüft; Plist-/Privacy-/Entitlement-Dateien, YAML, JSON, Python und Shell geprüft. Lokale Berichte: `build/reports/portable-check.json` und `build/reports/node-tests.tap` (ignoriert, nicht im PR). **34 vorbereitete XCTest-Definitionen**, Apple-SDK-Typprüfung, Simulator, Geräte, Signierung und Archive bleiben **nicht ausgeführt**. Der native Downloader, SponsorBlock und Google Cast sind vollständig entfernt; keine Release-only-Flags oder internen Ersatzpfade. Details: [NO-DOWNLOAD-VARIANT.md](NO-DOWNLOAD-VARIANT.md), [COMMERCIAL-USE.md](COMMERCIAL-USE.md).

Apple verlangt seit 28.04.2026 für App-Store-Connect-Uploads Xcode 26+ und iOS-/iPadOS-26-SDK ([offizielle Anforderungen](https://developer.apple.com/news/upcoming-requirements/)). Das Mindestziel der App bleibt iOS 17; die Upload-SDK-Version ist davon unabhängig. Die Syntaxprüfung ersetzt keinen Apple-SDK-Build.

**Historischer Stand vom 15.10.2026:** Bis dahin wurden für diese Bereinigung keine Actions oder Uploads gestartet. Im bisherigen `main` ist ein früher ausdrücklich freigegebener [Mac-/TestFlight-Lauf 38565407837](https://github.com/Mopphie/webkweb-Video/actions/runs/38565407837) mit 38 nativen XCTest-Fällen, signiertem Archiv/IPA und TestFlight-Build 0.1.0 (1) dokumentiert. Dieser frühere Build enthält die jetzige Bereinigung nicht und ersetzt deren erneuten Apple-SDK-/Gerätetest nicht. Die frühere Einschränkung für Actions-Minuten wurde am 16.10.2026 durch die ausdrückliche Freigabe für Builds und Tests aufgehoben. Der aktuelle Auftrag „Testflight“ autorisiert zusätzlich den signierten Upload des geprüften Stands über einen separaten Release-Branch; eine App-Store-Veröffentlichung wurde damit nicht beauftragt. Lokaler Einstieg: `./Scripts/check-macos.sh`.

## Mac und Geräte

Auf einem autorisierten Mac: vollständiges Xcode 26+ auswählen, iOS-26-SDK und verfügbare iPhone-Simulator-Runtime installieren; Command Line Tools, Python 3, XcodeGen und Node.js 18+ bereitstellen. `./Scripts/check-macos.sh` führt lokale Node- und Xcode-Tests aus. Für Archive/TestFlight danach Apple-Team, App-Group-Provisionierung sowie App- und Widget-Signierung mit echten Profilen prüfen. Alternativ prüft der freigegebene Actions-Validierungsworkflow Debug/XCTest und unsigned Release für den Simulator.

1. Standardprojekt in Debug und Release bauen, XCTest ausführen. iPhone/iPad, kleine Breite, große Schrift, VoiceOver, Transparenz reduzieren und beide Glass-SDK-Pfade testen.
2. App/Widget mit echtem Team und provisionierter App Group signieren. Widget-Auswahl, Favoritenbesuch/-edit/-reorder/-löschung, Siri/Kurzbefehle und Home-Deep-Link bei warmem und kaltem Start prüfen.
3. Suche aller drei Anbieter, Desktop-Inhaltsmodus/Zoom, Popup/opener/close, Zurück/Vorwärts einschließlich BFCache, gleiche iframe-URLs, normale Wiederherstellung und private Tabs prüfen. Private Tabs nie persistieren/aufzeichnen; History-off gesondert von Session-Restore testen.
4. Pending-Navigation während Website-Wipe, mehrere Tabs/Stores, Logout und Fehler-/Timeoutpfad testen. Löschen wird erst nach Abschluss der leeren Dokumente als erfolgreich gemeldet.
5. Autoplay/PiP/AirPlay/Seek/Lautstärke, offener Shadow DOM, primärer Player plus Nebenplayer, Audio, Replays, recycelte DRM-Player und Videozählung prüfen. Geschlossene Shadow Roots und DRM bleiben Plattformgrenzen.
6. Alle Quellen einzeln/gemeinsam, Import, Ausnahmen, Quelle deaktivieren bei Ausfall einer anderen, >40k Regeln, Offlinecache und tägliche Foreground-Updates prüfen. WebKit-RegEx-Kompilierung und Geräteperformance mit großen Listen beobachten; bei Kompilierungsfehler bleibt die letzte funktionierende Version mit Diagnose erhalten.
7. Freie Dauer, N Videos, aktuelles Video, Cancel/Resume, neue Autoplay-Player und persistierte Deadline testen. Sperrbildschirm, PiP, Bluetooth, AirPlay, Anrufunterbrechung, Clock-Stop und Suspension beobachten; keine Background-/Clock-Zeitgarantie versprechen.
8. Für optionales CloudKit echten Container über `configure-cloudkit.py` setzen; iCloud/Push provisionieren. Lokalen Store vor Migration sichern, opt-in/neustart/offline/fallback und Zwei-Geräte-Sync mit Favoriten-Snapshot-Aktualisierung prüfen. Schema erst nach erfolgreichem Development-Test in Production bereitstellen.

## Noch offene Release-Angaben

Öffentliche [Datenschutzerklärung](https://mopphie.github.io/webkweb-privacy/), [Support](https://mopphie.github.io/webkweb-privacy/support/) und [Impressum](https://mopphie.github.io/webkweb-privacy/impressum/) wurden mit dem bereits für Printatops öffentlich verwendeten Betreiberkontakt veröffentlicht und per HTTP geprüft. Der Betreiber hat Impressum und veröffentlichte Datenschutzerklärung in der schrittweisen Durchsicht bestätigt. Das DevnTube-Rebranding der Website wurde per gesondert freigegebenem GitHub-Pages-Deploy veröffentlicht; alle drei Live-Seiten zeigten nach dem Deploy DevnTube (HTTP 200). `App/Info.plist` enthält die echten URLs und den Kontakt; in der App sind die Links sichtbar. Inhalt und App-Privacy-Angaben müssen **am finalen Release-Build** fachlich/rechtlich geprüft werden. Die Projekt-IDs und die App Group wurden im Apple-Portal unter Team `HUN9MS832X` registriert; beide App-Store-Profile wurden gegen Kennungen, Gruppe und Zertifikat geprüft und beim erfolgreichen Mac-Lauf für eine signierte IPA eingesetzt. Optionales CloudKit ohne echten Container deaktiviert lassen. Die sieben DevnTube-Secret-Namen und der manuelle Signing-Pfad stehen in [TESTFLIGHT-SECRETS.md](TESTFLIGHT-SECRETS.md).

Vor Veröffentlichung: App-Store-Datenschutzauskunft einschließlich optionalem iCloud mit dem finalen Build abgleichen, Signierung/Icons/**echte Gerätescreenshots**/Altersfreigabe nach Apples aktualisiertem Fragebogen prüfen und Dienstbedingungen/Rechte beachten. Die frühere native Medien-Downloadfunktion sowie SponsorBlock und Google Cast wurden vollständig entfernt, einschließlich Debug und Tests nur für diese Integrationen. Vorhandene Nutzerdateien bleiben unangetastet. Die verbleibenden Filterquellen sind unter ihren Lizenzbedingungen zu verwenden; Hinweise stehen in der App und [COMMERCIAL-USE.md](COMMERCIAL-USE.md). `ITSAppUsesNonExemptEncryption=false` setzt übliche ausgenommene System-/TLS-Verschlüsselung voraus. Keine Zugehörigkeit zu den verlinkten Diensten oder garantierte App-Store-Zulassung behaupten.

**Status dieser bereinigten Fassung:** Signiertes Gerätearchiv, IPA-Export und TestFlight-Upload **0.1.0 (Build 5)** sind oben nachgewiesen. Die interne Testgruppenzuordnung ist API-bedingt nicht bestätigt. Echte iPhone-/iPad-Screenshots und reale Diensteprüfungen stehen noch aus. Die früheren TestFlight-Builds sind davon getrennt dokumentiert. [APP-STORE-DRAFT.md](APP-STORE-DRAFT.md) enthält vorbereitete Metadaten ohne erfundene Angaben. PR/Dokumentation sind Vorbereitung, keine Einreichungsfreigabe.

Sachliche Beschreibung: „Browser für iPhone und iPad mit Tabs, Favoriten, nativer Video-Steuerung, AirPlay und Sleep-Timer. Unterstützte Webseiten können Inline-Video und Bild-in-Bild nutzen. Ein optionaler Netzwerkfilter reduziert bestimmte Anfragen. Funktionen hängen von Webseite, iOS und Wiedergabequelle ab.“
