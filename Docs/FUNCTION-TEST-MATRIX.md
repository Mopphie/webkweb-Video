# Funktionsprüfung der bereinigten App

Stand: 16. Oktober 2026. Die Ebenen werden getrennt ausgewiesen: originale Skripte im Node-Harness, reale lokale Videodekodierung in Chromium, native XCTest-Fälle im iOS-Simulator und weiterhin erforderliche Geräte-/Diensteprüfungen. Ein bestandener lokaler Videotest beweist keine Kompatibilität jeder fremden Plattform.

## Automatisierte Abdeckung

| Bereich | Konkrete Prüfung | Ebene / verbleibende Grenze |
| --- | --- | --- |
| Video starten, pausieren und spulen | Tatsächlicher Zeitfortschritt, stabile Pause, begrenzte Seek-Ziele, Geschwindigkeit und dekodierte Dimensionen | Reales Chromium und bestandene WKWebView-Integration im iOS-Simulator |
| Natürliches Ende / Replay | Ende kommt aus echtem Decoder; erneutes Play erhält neue Medien-/End-ID | Reales Chromium, Node und bestandene native WKWebView-Integration |
| Dynamische Player | Unmittelbarer Befehl nach Einfügen, nachträglich geöffneter Shadow DOM, Pointer-Auswahl | Reales Chromium und Node-Regressionen; geschlossene Shadow Roots bleiben Webseitenzuständigkeit |
| Eingebettete Player | Tatsächlich unterschiedliche gleich- und fremd-originäre Frames mit eigenem Dokument und pausierbarem Video | Reales Chromium; native Frame-Koordination benötigt WebKit-/Geräteprüfung |
| Queue / Schleifen | Ursprüngliches `loop` nach Quellenwechsel wiederherstellen; Audioende wird nicht als Video gezählt | Reales Chromium und Node; Permutation/Repeat/Reorder/Persistenz durch native Modelltests |
| Sleep-Timer | Stop-Sperre pausiert neu gestartete Player, expliziter Resume löst Sperre; Deadline-/N-Video-/Tab-/ID-Abgrenzung | Reales Chromium, Node und native Modell-/Integrationstests; keine pünktliche Aktion bei suspendierter App zugesagt |
| Untertitel / Tonspuren | Echte TextTracks ein-/ausschalten; vorhandene öffentliche Audiospuren und Originalspur-Auswahl | Reales Chromium für TextTracks, Node für AudioTracks; webseiteninterne Spuren werden nicht extrahiert |
| Vollbild / PiP | Echte Chromium-API oder verständlicher Fehlerpfad; automatische Übernahme nur bei erfüllten Bedingungen | Chromium/Node; iPhone-/iPad-Presentation und Hintergrundwechsel bleiben Geräteprüfungen |
| AirPlay | Verständlicher Fallback ohne Apple-API | Chromium prüft ausschließlich den Fallback; echte AirPlay-Geräte sind hier nicht vorhanden |
| Medienfehler / Recovery | Nicht vorhandene Quelle liefert echten Decoderfehler und fehlgeschlagener Start einen Hinweis | Reales Chromium; Netzwerk-/DRM-/Loginfehler fremder Dienste zusätzlich am Gerät prüfen |
| SPA / BFCache / Lifecycle | Navigationsmeldung, stabile Identitäten, Disposal/Restore und gedrosselte Hintergrundnachrichten | Chromium und Node; native Redirect-/Session-Prüfung durch XCTest |
| Adresssuche / Deep Links | Schema-/Host-/Zugangsdatenprüfung, Suchparameter und Widget-Link-Roundtrip | Native XCTest; echte Anbieter-/Loginseiten werden nicht als lokale Fixture ausgegeben |
| Tabs / private Daten | Nicht persistenter Store, gemeinsame private Popup-Sitzung, Restore-Useraktion, Ausschluss privater URLs und Zugangsdaten | Native XCTest; vollständige native UI-Bedienung zusätzlich am Gerät prüfen |
| Website-Daten löschen / Dialoge | Commit des leeren Dokuments abwarten; jede Dialogantwort genau einmal | Native XCTest; Cookies/Logout auf realen Diensten zusätzlich prüfen |
| Filter / Quellen | Ausnahmegrenzen, >40k-Regelchunks, vollständige Domainmenge, Preset-Migration | Native XCTest; tatsächliche WK-Regelkompilierung und große Listen am Gerät prüfen |
| Favoriten / Verlauf / Widgets / Siri | Saubere gespeicherte Adressen, App-Group-Snapshot, Intent-Reihenfolge, lokale Queue-/Preferences-Persistenz | Native XCTest; SwiftData-UI, WidgetKit-Konfiguration und Siri am Gerät prüfen |
| iCloud | Standardzustand ohne unprovisionierten Container und übereinstimmende Entitlements | Strukturprüfung; aktivierter CloudKit-Sync benötigt echten Container und zwei angemeldete Geräte |

Die lokalen Laufstände stehen in `build/reports/node-tests.tap`, `browser-check.json`, `portable-check.json` und `swift-tree-sitter.json`. Der native Nachweis ist zusätzlich in `native-verification.json` zusammengefasst und im unten verlinkten Actions-Lauf überprüfbar. Native Ergebnisse werden als `.xcresult` im Actions-Lauf abgelegt. Vorbereitete XCTest-Fälle werden erst nach erfolgreichem Simulatorlauf als bestanden gewertet.

## Plattformen und Werbefreiheit

| Quelle | Was die App technisch anbietet | Was hier nicht behauptet wird |
| --- | --- | --- |
| Eigene/freigegebene HTML-Videos | Direkte Wiedergabe im echten Webseitenplayer; lokale synthetische Testmedien enthalten keine Werbung | Keine Garantie für unbekannte Codecs, Live-/DRM-/Loginbedingungen |
| YouTube | Normale Website und deren eigene Inhalte/Controls; generische öffentliche Mediensteuerung | Keine kostenlose Premium-Ersetzung und keine verbindliche Freigabe für die Verwertung fremder Inhalte |
| Twitch | Normale Website und öffentliche Medienfunktionen, soweit vom Player/iOS angeboten | Kein Entschlüsseln oder Ersetzen von Werbestreams und keine Garantie für Turbo-/Accountfunktionen in WKWebView |
| TikTok | Normale Website; Medienfunktionen soweit öffentlich zugänglich | Keine Garantie bei Regions-, Alters-, Login- oder In-App-Browser-Beschränkungen |
| Rumble | Normale Website und öffentliche Medienfunktionen | Keine Garantie für Premium-/Accountfunktionen oder für jede eingebettete Playerkonfiguration |

Die App enthält keinen eigenen Werbe-SDK und zeigt keine eigenen Werbeeinblendungen. Der allgemeine Netzwerkfilter ist keine Zusage, Werbung innerhalb fremder Videostreams vollständig zu entfernen. Die eigenen Nutzungsrechte am Browser erteilen keine Rechte an fremden Videos oder Diensten.

Offizielle Wege und Bedingungen: [YouTube-Bedingungen](https://www.youtube.com/static?template=terms), [YouTube Premium auf unterstützten Geräten](https://support.google.com/youtube/answer/6308244), [YouTube: Werbung und Mitgliedschaft](https://support.google.com/youtube/answer/7437519), [Twitch Turbo](https://help.twitch.tv/s/article/twitch-turbo-guide), [TikTok-Bedingungen](https://www.tiktok.com/legal/page/global/terms-of-service/en), [Rumble Premium](https://rumble.com/premium) und [Rumble-Bedingungen](https://rumble.com/s/terms). Verfügbarkeit und Umfang werden von den Anbietern festgelegt. Ein universelles, kostenloses und rechtssicheres Werbefreiheitsversprechen für alle diese Plattformen ergibt sich daraus nicht.

## Buildpfad

Der Nutzer hat GitHub Actions am 16.10.2026 ausdrücklich freigegeben. `validate.yml` prüft ausschließlich den Entwicklungsbranch: Debug mit iPhone-Simulator/XCTest sowie einen unsigned Release-Simulatorbuild. Es verwendet keine Signing-Secrets und führt keinen TestFlight-/Store-Upload aus. Der erste manuelle Dispatch des älteren Workflows wurde mit HTTP 403 abgelehnt; das ist ein Zugriffsproblem, kein Compilergebnis. Nur ein tatsächlich gestarteter und erfolgreicher neuer Lauf zählt als Buildnachweis.

Lokal auf einem Mac mit Xcode 26+, XcodeGen und Node: `./Scripts/check-macos.sh`, danach ein Release-Build. Die echten Dienste müssen zusätzlich mit zulässiger normaler Nutzung, den erforderlichen Accounts und iPhone/iPad geprüft werden; lokale Fixtures sind keine angeblichen YouTube-/Twitch-/TikTok-/Rumble-Livetests.

## Erster echter Simulatorlauf

[Lauf38858954054](https://github.com/Mopphie/webkweb-Video/actions/runs/38858954054), Code3f6e435: Der Apple-SDK-Build kompilierte. 38 XCTest-Methoden liefen; 35 bestanden, drei schlugen fehl. Zwei Medientests verwendeten versehentlich den synchronen Content-World-Overload mit Rückgabe `Void` statt des Result-Callbacks; ein UA-Test erwartete `nil`, obwohl WebKit eine leere Kennung zurückgibt. Das sind echte rote Testergebnisse und keine bestandenen Wiedergabenachweise. Die Abfragen wurden korrigiert; die Medientests blieben aktiv und prüfen weiter tatsächliche Dekodierung und Wiedergabe. Der nachfolgende erfolgreiche Lauf bestätigt die Korrekturen.

## Erfolgreicher nativer Folgelauf

[Lauf 38860463443](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443), Code `24d961f`: **38/38 XCTest-Methoden bestanden, keine Fehler**, darunter beide realen WKWebView-Medientests. Xcode 26.6, iPhone 17 Pro / iOS 26.5 im Simulator. Geprüft wurden tatsächlicher Zeitfortschritt, Pause, Seek, Rate und Resume sowie natürliches Decoderende, nativer N-Video-Timer und Stopp eines neu eingefügten Autoplay-Players nach dessen tatsächlichem Play-Ereignis. Debug/Test und Release-Simulatorbuild sind grün.

[Unsigned Release-Simulator-App](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029370391) und [native `.xcresult`-Resultate](https://github.com/Mopphie/webkweb-Video/actions/runs/38860463443/artifacts/12029320581) werden sieben Tage gespeichert. Der Download ist keine signierte Geräte-IPA. Die 44 lokalen Node- und 15 Chromium-Tests bestanden separat. Native Prüfung verwendet die originalen App-/Bridgepfade und selbst erzeugte Medien; Livetests auf YouTube, Twitch, TikTok und Rumble sowie reale AirPlay-/PiP-/Hintergrund-/DRM-/Account-Prüfungen werden dadurch nicht behauptet.

## Signierter TestFlight-Build

[Lauf 38862276281](https://github.com/Mopphie/webkweb-Video/actions/runs/38862276281), Code `ff827ff`: erneut **38/38 native Tests**, **44/44 Node-Tests** und **10/10 Release-Helper-Tests** bestanden. Signiertes Gerätearchiv, IPA-Export und Upload für Version **0.1.0 (Build 3)** erfolgreich. Apple bestätigt **VALID** sowie **IN_BETA_TESTING**. Die App-/Widget-/Bridgequellen entsprechen dem erfolgreichen vorherigen Stand. Einzelne Testgruppenzuordnungen konnte der API-Schlüssel wegen HTTP 403 nicht prüfen; daraus wird keine Bestätigung jedes Testerzugangs abgeleitet. [Details](RELEASE.md).
