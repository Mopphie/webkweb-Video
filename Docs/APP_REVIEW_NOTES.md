> TestFlight-Nachtrag: Dieser Stand wurde vor den später autorisierten CI-Läufen verfasst. Aktuelle native/UI-Testergebnisse, tatsächliche Apple-Einrichtung und verbleibende Uploadblocker: [TESTFLIGHT_STATUS.md](TESTFLIGHT_STATUS.md). Die CI-Suite ist kein Nachweis sämtlicher dienst-, geräte- oder länderabhängiger Funktionen.

# App-Review-Notizen — lokaler Entwurf, keine Einreichung

16.10.2026. Dieser neue Quellstand wurde **nicht** signiert/hochgeladen oder im App Store Connect geändert. Frühere TestFlight-Builds sind historische Vorgänger und kein Nachweis dieses Standes. [Aktuelle Blocker](RELEASE_BLOCKERS.md).

## Tatsächlicher App-Nutzen

DevnTube kombiniert einen offenen WebKit-Browser mit einer eigenen nativen Mediathek für rechtmäßig nutzbare Dateien und Direktquellen: lokale benannte Playlists, Queue, eigene Zeitmarken/Notizen, Weitersehen, Systemplayer, Sleep-Timer, Datenexport/-import, Widget-/Siri-Schnellzugriff und bewusstes Teilen. Kein eigenes Konto, Backend, Analytics-/Werbe-SDK, Abo, Cast-SDK, Plattformdownloader oder SponsorBlock. Die App verkauft keine YouTube-Premium-Freischaltung und verspricht keine werbefreie Websitewiedergabe.

Websites werden unverändert geladen; Erweiterungen für erzwungenes Plattform-PiP/Hintergrund, Shorts-/Masthead-CSS und Ressourcenfilter sind entfernt. Eine eigene Hauptseiten-Sperrliste ist keine Werbung-/DNS-/VPN-/Unterressourcenfilterung. Plattformlinks bleiben normale manuell geöffnete Lesezeichen. Von der Website selbst bereitgestellte Funktionen richten sich nach Dienst/Region/Account/Abonnement des Nutzers.

## Voraussetzungen und reproduzierbare Reviewwege

Kein Demoaccount erforderlich. Auf einem Mac lokal `./Scripts/check-macos.sh` für Xcode-Build/XCTest ausführen; die Pflichtreise benötigt ein tatsächlich PiP-fähiges Gerät/Simulator. Keine hochgeladenen Testclips eines Drittanbieters verwenden. Eigene synthetische H.264/AAC-Clips liegen unter `Tests/Fixtures` mit Generatoranleitung. Sie sind **nicht** im App-Release gebündelt: für einen Gerätetest in Dateien kopieren und ausdrücklich importieren. DEBUG-Testlaunches verwenden dieselben eigenen Clips; keine andere Reviewer-/Release-Funktion wird versteckt aktiviert.

1. **Browser/Navigation:** Start → Suchfeld → normale HTTPS-Seite → Link/Popup → Zurück/Vorwärts → native Aktionsliste → Start/Tabübersicht. Direkte YouTube-Watch-URL ohne Vorgeschichte öffnen: sichtbaren Abwärtsknopf oder „Zurück oder Startseite“ nutzen. Zur normalen Websiteansicht zurückschalten; DOM/Player nicht kopieren. Vollbild über dienstseitige Controls verlassen; native Navigation wieder erreichbar.
2. **Native Wiedergabe:** Start → Mediathek → „Eigene Datei öffnen“ → eigenen Clip aus Dateien wählen. Play, Pause, Skip, Rate, Untertitel/Audio/Kapitel nur soweit vorhanden. A und später B setzen, Schleife löschen. UI reagiert bei Fehler mit bewusster Wiederholung und Datei-Neuverknüpfung.
3. **Pflichtreise:** Clip öffnen → Systemvollbild → zurück → System-PiP → Home/andere App → zurück → native Queue öffnen → nächstes eigenes Video → zurück zum Suchfeld. Derselbe Player, weiterlaufende Medienzeit, kein zweiter Ton und keine verlorene Navigation. Automatisierter Fall: `NativePlaybackJourneyUITests`; **noch nicht ausgeführt**. Ungeeignete Geräte dürfen nicht durch einen unechten Fallback als PiP-Erfolg zählen.
4. **Hintergrund/AirPlay:** Eigenen Clip hörbar starten, App verlassen/Gerät sperren; erlaubte native Wiedergabe und Lock-Screen-Aktionen prüfen. Kopfhörer/Bluetooth entfernen, Unterbrechung auslösen, AirPlay verbinden/trennen, Netzwerk wechseln/unterbrechen. Websiteanbieter separat prüfen; iOS-Mediensession ist keine Erlaubnis einer bezahlten Dienstfunktion.
5. **Mediathek:** Benannte Liste anlegen, Medien/Website-Link hinzufügen, Reihenfolge ändern, eigene Notiz und Zeitpunkt speichern/bearbeiten, springen/teilen. Native Liste bewusst als Queue starten. Fehlende Quelle muss stoppen statt Endlosschleife; Websiteeinträge nur einzeln öffnen.
6. **Timer:** 30 Sekunden testen, +10 Min verlängern, abbrechen; Pause/Tab-/Quellenwechsel, aktuelles VOD, Queue-Ende. Timerdauer läuft absolut weiter. A–B endet nicht von selbst; ohne echtes Ende kein Endezähler. Während nativer Hintergrund-Audiowiedergabe sollen AV-Zeitbeobachter/Runloop prüfen; exakte Ausführung bei Sperre/OS-Suspendierung ist noch nicht bewiesen.
7. **Privat:** Privaten Tab öffnen, Titel/URL verwenden, Popup testen, zurück zu normalen Tabs: kein Verlauf, Resume, Widget/Intent oder Snapshot. Privaten Favorit wählen: klare Bestätigung des Austritts. Private Sitzung schließen/neustarten: keine Wiederherstellung. Privates Webvideo beim Appwechsel pausiert, kein app-erzwungenes PiP, keine private App-Diagnose.
8. **Daten:** Verlauf löschen: Favoriten/Notizen/Listen bleiben, Besuchs-/Resume-/geschlossene Tabvorschläge verschwinden. Website-Daten separat löschen, aktive Seiten vorher schließen. Eigene Sicherung exportieren/importieren: Formatversion/Größen-/URLvalidierung, bestehende IDs gewinnen, keine Cookies/Credentials/privaten Tabs/Dateirechte/History. Fehlende Dateien neu zuordnen.
9. **Sperre/Erweiterungen:** Gerätesperre aktivieren, Kaltstart/Foreground/FaceID-Abbruch testen; alle Sheets im App-Umschalter verdeckt, kein Shortcutzugriff vor Entsperren. Normale bereits bewusst gestartete Systemmedien können weiterlaufen. Favoritenfreigabe zunächst aus, dann explizit an/aus und Widget/Siri prüfen. Eingehende Teilen-Erweiterung auf Nutzerwunsch entfernt; kein solcher Eintrag im iOS-Teilen-Menü. Widget und normale ausgehende ShareSheets bleiben.
10. **Zugänglichkeit:** iPhone/iPad, Rotation, kleine Fenster, größte Schrift, VoiceOver, Hardwaretastatur, Reduce Transparency/Reduce Motion, Hell/Dunkel/System. Keine Video-Farbmanipulation. Text-/Touchziele auf Abschneiden prüfen.

## Transparenz für Apple

- Audio-Hintergrundmodus nur für echte erlaubte Medien; keine stille Audioschleife/Workaround.
- Öffentliche Apple-APIs; keine API-Keys, Streamextraktion, Premium-Imitation, herunterladbaren Featuremodule, privaten APIs oder nach Review eingeschalteten Integrationen.
- Privacy-Manifests für App/Widget/Share; App-Group-UserDefaults nur eigene freigegebene Daten. ATT nicht als Umgehung anderer Datenschutzpflichten betrachten.
- Bei App-Privacy-Antworten die Ausnahme für echte Open-Web-Navigation gegen das konkrete Produkt mit vorgegebenen Lesezeichen/Websitekontrollen prüfen; kein automatisches „keine Daten erhoben“ aus fehlendem Backend ableiten.
- Kontakt/Verantwortlicher, öffentliche Datenschutzerklärung und Support müssen vor Einreichung bestätigt/aktualisiert werden. Quelleabhängige Rechte ggf. auf Nachfrage nachweisen. Vertriebsländer/Marken-/Jugendschutzfragen noch offen.
- Altersfragebogen ehrlich für offenen Webzugriff/Inhalte beantworten; keine Altersklasse erfunden oder im Konto geändert.
- Kein Kauf-/Restoreweg im aktuellen Produkt, da kein echtes StoreKit-Produkt vorliegt. Eine spätere Preis-/Einmalkaufentscheidung ist separat.

Apple-Regelgrundlage: [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [App Privacy](https://developer.apple.com/app-store/app-privacy-details/), [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/). Diese Notizen sind weder eine Apple-Zusage noch eine umfassende rechtliche Freigabe.
