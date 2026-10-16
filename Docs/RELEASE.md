# Prüfung vor einem Release

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

**Status dieser bereinigten Fassung:** Signiertes Gerätearchiv, IPA-Export und TestFlight-Upload 0.1.0 (Build 3) sind oben nachgewiesen. Echte iPhone-/iPad-Screenshots und reale Diensteprüfungen stehen noch aus. Die früheren TestFlight-Builds sind davon getrennt dokumentiert. [APP-STORE-DRAFT.md](APP-STORE-DRAFT.md) enthält vorbereitete Metadaten ohne erfundene Angaben. PR/Dokumentation sind Vorbereitung, keine Einreichungsfreigabe.

Sachliche Beschreibung: „Browser für iPhone und iPad mit Tabs, Favoriten, nativer Video-Steuerung, AirPlay und Sleep-Timer. Unterstützte Webseiten können Inline-Video und Bild-in-Bild nutzen. Ein optionaler Netzwerkfilter reduziert bestimmte Anfragen. Funktionen hängen von Webseite, iOS und Wiedergabequelle ab.“
