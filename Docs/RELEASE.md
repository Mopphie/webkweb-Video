# Prüfung vor einem Release

## Tatsächlicher Prüfstand

Linux: 22 Node-Tests der originalen Playback.js, Syntaxparser für 19 Swift-Dateien, Plists/Manifest-/YAML-/Ressourcenstruktur und Shell-/Python-Syntax. 21 XCTest-Definitionen einschließlich Filterchunking/Ausnahmen, Datenlösch-Commit, privatem Store, Dialogqueue, Timer und Intent-Verteilung sind vorbereitet; sie wurden hier nicht ausgeführt. Swift-Typprüfung und Apple-SDK-/XcodeGen-Build sind offen. Cast SDK und CloudKit wurden nicht auf Apple-Plattformen getestet. [AUDIT-FIXES.md](AUDIT-FIXES.md) beschreibt die Zuordnung aller Auditbefunde.

**Keine Actions oder automatisch ausgelösten Workflows. Ohne ausdrückliches OK des Nutzers keine GitHub-Actions-Minuten.** Lokaler Einstieg: `./Scripts/check-macos.sh`, Cast: `./Scripts/check-macos.sh --cast`.

## Mac und Geräte

1. Standardprojekt und Cast-Workspace bauen, XCTest ausführen. iPhone/iPad, kleine Breite, große Schrift, VoiceOver, Transparenz reduzieren und beide Glass-SDK-Pfade testen.
2. App/Widget mit echtem Team und provisionierter App Group signieren. Widget-Auswahl, Favoritenbesuch/-edit/-reorder/-löschung, Siri/Kurzbefehle und Home-Deep-Link bei warmem und kaltem Start prüfen.
3. Suche aller drei Anbieter, Desktop-UA/Zoom, Popup/opener/close, Zurück/Vorwärts einschließlich BFCache, gleiche iframe-URLs, normale Wiederherstellung und private Tabs prüfen. Private Tabs nie persistieren/aufzeichnen; History-off gesondert von Session-Restore testen.
4. Pending-Navigation während Website-Wipe, mehrere Tabs/Stores, Logout und Fehler-/Timeoutpfad testen. Löschen wird erst nach Abschluss der leeren Dokumente als erfolgreich gemeldet.
5. Autoplay/PiP/AirPlay/Seek/Lautstärke, offener Shadow DOM, primärer Player plus Nebenplayer, Audio, Replays, recycelte DRM-Player und Videozählung prüfen. Geschlossene Shadow Roots und DRM bleiben Plattformgrenzen.
6. Alle Quellen einzeln/gemeinsam, Import, Ausnahmen, Quelle deaktivieren bei Ausfall einer anderen, >40k Regeln, Offlinecache und tägliche Foreground-Updates prüfen. WebKit-RegEx-Kompilierung und Geräteperformance mit großen Listen beobachten; bei Kompilierungsfehler bleibt die letzte funktionierende Version mit Diagnose erhalten.
7. SponsorBlock-Kategorien, iframe/SPA, Host-Seiten-Ausnahmen, Skip/Undo, keine Segmente, Servicefehler und laufende YouTube-Werbung prüfen.
8. Freie Dauer, N Videos, aktuelles Video, Cancel/Resume, neue Autoplay-Player und persistierte Deadline testen. Sperrbildschirm, PiP, Bluetooth, AirPlay, Anrufunterbrechung, Clock-Stop und Suspension beobachten; keine Background-/Clock-Zeitgarantie versprechen.
9. Cast-Fälle aus [CAST.md](CAST.md), insbesondere Load/Pause/Timer-Rennen, tatsächliche Fehler und Gerätesession-Wechsel.
10. Für optionales CloudKit echten Container über `configure-cloudkit.py` setzen; iCloud/Push provisionieren. Lokalen Store vor Migration sichern, opt-in/neustart/offline/fallback und Zwei-Geräte-Sync mit Favoriten-Snapshot-Aktualisierung prüfen. Schema erst nach erfolgreichem Development-Test in Production bereitstellen.

## Noch offene Release-Angaben

Öffentliche Datenschutzerklärungs-URL, Support-URL und echter Betreiber/Kontakt sind ausdrücklich noch offen. Konfigurationsfelder sind vorbereitet; keine Beispieldaten als echte Release-Angaben verwenden. Apple-Team, App-Group- und optional CloudKit-Provisionierung werden vom Betreiber vorgenommen.

Vor Veröffentlichung: App-Store-Datenschutzauskunft einschließlich optionalem SponsorBlock/Cast/iCloud mit dem finalen Build abgleichen, Signierung/Icons/Screenshots/Altersfreigabe prüfen und Dienstbedingungen/Rechte beachten. `ITSAppUsesNonExemptEncryption=false` setzt übliche ausgenommene System-/TLS-Verschlüsselung voraus. Keine Zugehörigkeit zu den verlinkten Diensten oder garantierte App-Store-Zulassung behaupten.

Sachliche Beschreibung: „Browser für iPhone und iPad mit Tabs, Favoriten, nativer Video-Steuerung, AirPlay und Sleep-Timer. Unterstützte Webseiten können Inline-Video und Bild-in-Bild nutzen. Ein optionaler Netzwerkfilter reduziert bestimmte Anfragen; SponsorBlock überspringt verfügbare Community-Segmente. Funktionen hängen von Webseite, iOS und Wiedergabequelle ab.“
