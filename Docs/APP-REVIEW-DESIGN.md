# Design- und App-Review-Prüfung

Stand: 13. Oktober 2026. Prüfung des Quelltexts und der öffentlich abrufbaren Apple-Richtlinien; kein ausgeführter iOS-Build und keine Zusage einer App-Store-Zulassung.

## YouTube-Referenz

Die vom Nutzer vorgegebene Watch-Ansicht zeigt die echte YouTube-Seite mit einem vollbreiten Video, den ein- und ausblendbaren Webseiten-Controls, Titel/Kanal/Aktionen, Kommentaren und Empfehlungen. Als App-Bedienelement bleibt ein roter runder Menüknopf unten rechts. Eine zweite native Playerleiste, Adresszeile und Browser-Fußleiste würden diese Vorlage verändern und werden in dieser Ansicht ausgeblendet. Alle Browserfunktionen bleiben über das Menü erreichbar.

Die App ersetzt die Webseiteninhalte nicht durch nachgebaute Videotitel, Zähler oder Interaktionen. Sprache, Account, Bildschirmgröße, Werbung und YouTube-Experimente können die echte Website verändern. Identische Pixel für beliebige Videos lassen sich deshalb durch WKWebView allein nicht garantieren. Beide Zustände der Webseiten-Controls sowie Wechsel Watch → Suche/Start → Watch, Zurück/Vorwärts, private Tabs, Querformat und iPad müssen auf Geräten geprüft werden.

## Apple Human Interface Guidelines

Quellen: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons).

Liquid Glass gehört zur funktionalen Ebene für Navigation und Controls. Inhalte wie Listen, Kommentare und Videobilder bleiben auf der Inhaltsebene; das Material wird sparsam eingesetzt. Die App verwendet auf unterstütztem SDK/iOS die öffentliche SwiftUI-Glass-API und auf älteren Systemen ein Material-Fallback. Bei reduzierter Transparenz muss der Hintergrund deckend bleiben. Der bewusst rote YouTube-Menüknopf übernimmt die explizite Referenz des Nutzers.

Benutzerdefinierte Buttons benötigen ausreichend große Trefferflächen (44 × 44 pt als Ziel), einen erkennbaren gedrückten Zustand und aussagekräftige VoiceOver-Namen. Große Schrift darf Texte nicht unzugänglich machen; die Startseite nutzt bei Accessibility-Schriftgrößen weniger Spalten. Ein-/Aus-Zustände müssen neben Farbe auch über Symbol/Text beziehungsweise Accessibility-Werte verständlich sein. System-Sheets, Menüs und destruktive Bestätigungen erhalten ihre native Interaktion. Safe Areas schützen die Systemstatusanzeige und die Bedienbarkeit des schwebenden Menüknopfs.

Noch auf Apple-Geräten zu prüfen: Accessibility Inspector, VoiceOver-Reihenfolge einschließlich Webseiteninhalt, Full Keyboard Access, Increase Contrast, Reduce Transparency, größte Dynamic-Type-Stufen und Querformat. Ein Linux-Syntaxparser ersetzt diese Prüfungen nicht.

## App-Store-Anforderungen und aktueller Stand

Quelle: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

| Anforderung | Befund und Konsequenz |
| --- | --- |
| 2.1 Vollständigkeit / 2.3 korrekte Beschreibung | Xcode-Build, Laufzeittests und echte Screenshots fehlen noch. Konzeptbilder sind keine App-Store-Screenshots. Optionales Cast und nicht provisioniertes iCloud dürfen nicht als im Standardbuild verfügbar beworben werden. |
| 2.5.1 öffentliche APIs / 2.5.6 WebKit | WKWebView, öffentliche Media-/DOM-Funktionen, AVAudioSession, WidgetKit und App Intents sind die vorgesehenen Integrationen. Keine privaten YouTube-APIs, DRM-Umgehung oder alternativer Browserengine. Der fertige SDK-Build ist zusätzlich zu prüfen. |
| 2.5.4 Hintergrunddienste | Hintergrund-Audio dient tatsächlicher Wiedergabe. Keine Silent-Audio-Schleife, kein Keep-alive-Trick. WebKit-Suspension und Clock-Stop bleiben Gerätegrenzen; keine unbedingte Hintergrundgarantie. |
| 4.1 eigenständige App / 4.2 Mindestfunktionalität | Native Tabs, private Stores, Favoritenbearbeitung, Widgets, Kurzbefehle, Timer, Queue und System-Mediensteuerung bieten zusätzliche Funktionen. Die echten fremden Seiten werden als Browserinhalt angezeigt. Das garantiert keine positive Bewertung durch App Review. Fremde App-Identität, Namen oder Icons dürfen nicht als eigene Marke übernommen werden. |
| 5.1.1 Datenschutz | Die öffentliche Policy muss sowohl in App Store Connect als auch leicht erreichbar in der App verlinkt sein. Betreiber, Kontakt, Policy-URL und Support-URL sind ausdrücklich noch offen und bleiben eine Release-Voraussetzung. Diese Angaben gehören in die Bundle-Konfiguration, nicht in vom App-Nutzer frei änderbare Einstellungen. |
| 5.1 Datenverarbeitung | Verlauf/Session/Queue/Favoriten bleiben lokal; private Tabs werden nicht wiederhergestellt. SponsorBlock und iCloud sind opt-in. SponsorBlock überträgt Video-ID/IP; optionale SDKs und besuchte Seiten sind gesondert zu berücksichtigen. Privacy-Manifest und App-Store-Datenschutzauskunft müssen dem tatsächlich ausgelieferten Build entsprechen. |
| 5.2.1 / 5.2.2 Rechte und Dienste | Für verlinkte Dienste und ihre Inhalte müssen deren Bedingungen und erforderliche Genehmigungen geprüft werden. Der Browserkontext allein beweist keine Erlaubnis für sämtliche zusätzlichen Funktionen. Rechte an Marken, Icon, Demonstrationsinhalten und Release-Screenshots sind zu klären. |
| 5.2.3 Audio-/Video-Downloads | Der vorhandene direkte HTTPS-Dateidownload ist eine technische Einschränkung, kein Nachweis einer Quellen-Autorisierung. Apple verlangt ausdrückliche Autorisierung von Drittquellen für solche Downloads. Es liegen im Projekt keine Nachweise vor. Vor Einreichung entweder belegbar autorisierte Quellen technisch begrenzen oder diese Downloadfunktion vollständig aus dem ausgelieferten Produkt entfernen. Eine Nutzer-Rechtecheckbox oder ein Review-only-Schalter löst diesen Punkt nicht. |
| 1.2 Nutzerinhalte / 2.3.6 Altersfreigabe | Die App betreibt keine eigene Upload-/Kommentarplattform. Melde-/Blockierfunktionen der besuchten Dienste dürfen nicht entfernt werden. Altersangaben müssen den unbeschränkten Webzugang und tatsächlich sichtbare Inhalte berücksichtigen; kein unbelegtes Kids-Category-Versprechen. |
| 3.1 Zahlungen / 4.8 Login | Aktuell keine eigenen In-App-Käufe, Abos oder App-Konten. Daher kein erfundener Restore-Purchases- oder Account-Deletion-Flow. Login und Käufe besuchter Dienste bleiben Webseiteninteraktionen; bei späterer eigener Monetarisierung erneut prüfen. |

## Release-Entscheidung

Diese Änderungen liefern einen überprüfbaren Entwicklungsentwurf. Eine Einreichung bleibt offen, bis der echte Betreiber seine Angaben und gegebenenfalls Dienste-/Download-Genehmigungen vorlegt und die Mac-/Geräteprüfungen aus [RELEASE.md](RELEASE.md) bestanden sind. Es gibt keinen versteckten Modus für Reviewer. Keine Veröffentlichung, kein Merge und keine GitHub-Actions-Minuten ohne die entsprechende Nutzeranweisung.
