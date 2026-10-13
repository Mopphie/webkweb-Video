# Datenschutzhinweise für WebKWeb

Stand: 13. Oktober 2026. Diese Fassung beschreibt die Entwicklungsversion. Verantwortlicher und Kontaktadresse müssen vom Betreiber vor einer öffentlichen Veröffentlichung ergänzt werden; dieser Repository-Text ist noch keine veröffentlichte Policy-URL.

## Lokale Daten

WebKWeb speichert Titel, vollständige Adressen und Besuchszeitpunkte für Verlauf und Favoriten lokal mit SwiftData. Der Verlauf ist auf 500 nicht favorisierte Seiten begrenzt; Favoriten werden nicht automatisch gelöscht. Vollständige URLs können Suchbegriffe, Video-IDs und andere URL-Parameter enthalten. Favoriten werden zusätzlich im lokalen App-Group-Speicher abgelegt, damit WidgetKit und Siri/Kurzbefehle sie lesen können. Es gibt keinen aktiven CloudKit-/iCloud-Sync.

Die Bibliothek bietet Löschen einzelner Einträge, Entfernen von Favoriten und Löschen des nicht favorisierten Verlaufs. Cookies, Cache und andere WebKit-Website-Daten werden separat über Einstellungen → Cookies & Website-Daten löschen entfernt. Beim Deinstallieren der App werden deren lokale App-Daten entfernt; die systemseitige Aufbewahrung geteilter Container hängt davon ab, ob weitere zugehörige Erweiterungen/Apps vorhanden sind.

## Netzwerkanfragen

Besuchte Webseiten und deren eingebundene Dienste erhalten normale Browseranfragen, insbesondere IP-Adresse, mobile Safari-Kennung und gegebenenfalls eigene Cookies. Inhalte und Datenschutzregeln dieser Webseiten liegen bei deren Betreibern. Netzwerkfilter reduzieren bestimmte Anfragen, blockieren aber nicht alle Werbung oder Tracking.

Wenn eine Eingabe als Suchbegriff aufgelöst wird, wird sie in einer Google-Suche als Query übermittelt. Direkte HTTP-Adressen können im WebView unverschlüsselt übertragen werden; die nativen Listen- und SponsorBlock-Abfragen verwenden HTTPS.

Bei aktivem Netzwerkfilter lädt WebKWeb die AdGuard DNS-Liste von `adguardteam.github.io` höchstens einmal pro Tag beim Öffnen der App sowie bei manuellem Update. Der Host kann die IP-Adresse und normale technische Anfragedaten sehen. Verlauf/Favoriten werden nicht an diesen Host gesendet. Unterstützte Regeln werden lokal zu einer WebKit Content Rule List kompiliert und von WebKit gespeichert. Bei deaktiviertem Filter findet kein automatisches Listenupdate statt; ein ausdrücklich manuell gewähltes Update kann weiterhin laden.

SponsorBlock ist standardmäßig ausgeschaltet. Nach Aktivierung übermittelt WebKWeb die ID eines geöffneten YouTube-Videos und die gewünschten Segmentkategorien an `sponsor.ajay.app`. Die ephemere native Sitzung sendet keine WebKit-Cookies; der Dienst sieht die IP-Adresse. Segmente werden kurzzeitig im Arbeitsspeicher gecached. Beim Abschalten werden weitere Abfragen und Skips beendet. Über die Speicherung bereits übermittelter Anfragen entscheidet der Drittanbieter. Dessen Informationen: https://sponsor.ajay.app/privacy.

Die App-Privacy-Datei deklariert diese optionale Übermittlung als Browsing History für App-Funktionalität, ohne appseitige Verknüpfung mit einer Identität oder Nutzung für Tracking. Das ist kein Ersatz für die vor Veröffentlichung zu prüfende App-Store-Datenschutzauskunft einschließlich sämtlicher Drittanbieter.

## AirPlay und optionales Cast

AirPlay verwendet die iOS-Systemfunktionen und die gewählte Wiedergaberoute. Ein Build mit dem Google Cast SDK sucht nach Geräten im lokalen Netzwerk und fragt die entsprechende iOS-Berechtigung ab. Beim Übertragen werden direkter Medienlink, Titel und Startposition an das gewählte Gerät übermittelt. Der Receiver ruft die Quelle selbst ab. Browser-Cookies, DRM-Lizenzen und Login-Header werden nicht übertragen. Für Google Cast und den Receiver gelten deren eigene Datenschutzinformationen.

Der Standardbuild enthält kein Cast SDK und startet keine Cast-Gerätesuche. Es gibt keinen eigenen Analytics-Dienst, keinen Werbe-SDK und keine appseitige Cross-App-Tracking-ID. Webseiten können unabhängig davon eigene Datenverarbeitung betreiben.

## Verwendete System-APIs

`UserDefaults` speichert Einstellungen und Updatezeit sowie Favoriten im geteilten lokalen App-Group-Container. Die Required-Reason-Erklärungen CA92.1 und 1C8F.1 stehen in den Privacy-Manifesten von App und Widget. AVAudioSession und Audio-Hintergrundmodus konfigurieren Wiedergabe; WebKit und iOS können sie im Hintergrund anhalten.
