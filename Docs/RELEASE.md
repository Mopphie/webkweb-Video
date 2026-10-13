# Prüfung vor einem Release

## Aktueller Prüfstand

Die Implementierung wurde in einer Linux-Umgebung erstellt. Dort wurden sieben ausführbare Node-Regressionstests für die Playback-Bridge erfolgreich ausgeführt und Swift-Dateien mit einem Swift-Syntaxparser geprüft. Plists, Manifeststruktur, Projektzuordnung und Shell-Syntax wurden lokal geprüft. Swift-Typprüfung, Xcode-Build, XCTest, Simulator-UI und reale Medien-/Gerätefunktionen können dort nicht ausgeführt werden und sind noch offen. Der optionale Google-Cast-Build wurde ebenfalls nicht kompiliert oder auf Hardware geprüft.

Es gibt keine automatisch getriggerten CI-Workflows. **GitHub Actions dürfen erst nach ausdrücklichem OK des Nutzers angelegt oder ausgeführt werden.** Der lokale Einstieg ist `./Scripts/check-macos.sh`; `xcodebuild` führt XCTest einschließlich eines Content-Rule-List-Reaktivierungs-Regressionstests aus.

## Auf dem Mac / auf Geräten

1. XcodeGen-Projekt erzeugen, Simulator-Build und XCTest durchführen. Danach iPhone- und iPad-Simulator, Hell/Dunkel, große Schrift und VoiceOver prüfen.
2. Beide Targets mit dem eigenen Team signieren; Bundle-IDs und App Group konsistent provisionieren. Auf einem echten iPhone und iPad starten, Widget hinzufügen, Favoriten hinzufügen/löschen und Deep-Link-/Siri-Aufrufe testen.
3. URL/Suche, Tabwechsel, Popup-Tabs, Zurück/Vorwärts, Offlinefehler, Cookies/Login und Website-Daten-Löschen prüfen. Tabs bleiben im laufenden Prozess erhalten; Tab-/WebView-Sitzungen werden nach App-Neustart nicht wiederhergestellt.
4. Inline/Autoplay/PiP/AirPlay an mehreren HTML5-Playern prüfen, auch mit iframe. Lautstärke über nativen Regler, Play/Pause/Seek und Gestenfläche testen. Webseiten dürfen Autoplay verweigern.
5. Filter aus/ein, Update offline/online, Ausnahmen und gebrochene Webseiten prüfen. DNS-Liste wird auf einen sicheren Domain-Teilumfang und 15.000 Regeln begrenzt. YouTube-Endpunkte sind zusätzlich enthalten; serverseitig eingebettete Werbung bleibt möglich.
6. SponsorBlock zuerst aus, dann aktivieren; Video-ID-Wechsel über YouTube-SPA, keine Segmente, Servicefehler, Intro/Sponsor/Outro/Eigenwerbung und ad-showing-Player testen.
7. Sleep-Timer nach Zeit und Videos testen, insbesondere Tabwechsel, doppelte Endereignisse, Playlist-Autoplay, Replay und App-Suspension. Background Audio bei Sperrbildschirm, Appwechsel, PiP und Unterbrechungen tatsächlich beobachten. Einen zuverlässig pünktlichen Timer in einer suspendierten WKWebView nicht versprechen.
8. Für optionales Cast alle Schritte in CAST.md mit realem Receiver durchführen. Der Google-Cast-SDK-Build braucht eine separate Prüfung seiner SDK-/Privacy-Version und seiner öffentlichen APIs.

## App-Store-Unterlagen

- Öffentlich erreichbare Datenschutzerklärung und Support-URL mit echtem verantwortlichem Betreiber/Kontakt veröffentlichen; App-Store-Datenschutzauskunft inklusive optionaler SponsorBlock-Übermittlung und optionalem Cast SDK ausfüllen.
- Icons, Screenshots, Altersfreigabe, Export-Compliance und erforderliche Capabilities mit dem tatsächlichen Release-Build prüfen. `ITSAppUsesNonExemptEncryption=false` setzt voraus, dass nur übliche, ausgenommene System-/TLS-Verschlüsselung genutzt wird.
- Webseiten-/Dienstbedingungen und erforderliche Rechte für Werbung, Markennamen und Inhalte prüfen. Keine Zugehörigkeit zu YouTube, Google, AdGuard oder SponsorBlock behaupten.
- Keine garantierte App-Store-Zulassung, werbefreies YouTube, generelle DRM-Umgehung oder immer funktionierendes Hintergrund-Audio bewerben.

Mögliche sachliche Beschreibung: „Ein Browser für iPhone und iPad mit Tabs, Favoriten, nativer Video-Steuerung, AirPlay und Sleep-Timer. Unterstützte Webseiten können Inline-Video und Bild-in-Bild nutzen. Ein optionaler Netzwerkfilter reduziert bestimmte Anfragen; SponsorBlock überspringt verfügbare Community-Segmente. Funktionen hängen von Webseite, iOS und Wiedergabequelle ab.“
