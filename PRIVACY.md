# Datenschutzhinweise für DevnTube

Stand: 14. Oktober 2026. Technischer Entwicklungsstand. Die öffentliche [Datenschutzerklärung](https://mopphie.github.io/webkweb-privacy/), der [Support](https://mopphie.github.io/webkweb-privacy/support/) und das [Impressum](https://mopphie.github.io/webkweb-privacy/impressum/) sind erreichbar. Diese Datei dokumentiert zusätzliche Implementierungsdetails; maßgeblich bleibt die Prüfung am später tatsächlich ausgelieferten Build.

## Lokale Daten und optionale iCloud-Synchronisierung

SwiftData speichert Titel, vollständige Adressen und Besuchszeitpunkte für Verlauf/Favoriten. Nicht favorisierte Historie ist auf 500 Einträge begrenzt und kann abgeschaltet werden. Favoriten lassen sich bearbeiten, sortieren und löschen. Vollständige URLs können Suchbegriffe, Video-IDs und Parameter enthalten. Benutzername/Passwort werden nicht gespeichert. Normale Tabs und Zeit-/Anzahl-Timer werden separat lokal wiederhergestellt; Tab-Restore lässt sich abschalten und ist unabhängig von History-off.

Private Tabs verwenden einen nicht persistenten WebKit-Speicher. Sie erscheinen weder im Verlauf noch im Session-/Timer-Snapshot. Ein bewusst aus einem privaten Tab gespeicherter Favorit wird in die normale Favoritenbibliothek übernommen. Private Titel erscheinen nicht in System-Medienmetadaten. Privates Browsen verbirgt Netzwerkanfragen nicht vor Webseiten, Netzbetreibern oder optionalen Filtern/SponsorBlock-Diensten.

Die normale URL-/Favoriten-Wiedergabequeue, ihre Shuffle-Reihenfolge und Repeat-Einstellung werden lokal in UserDefaults gespeichert, ohne private Tabs und ohne iCloud-Sync. Die Bibliothek/Queue bietet das Entfernen einzelner Einträge. Bei einer ausdrücklich eingegebenen Queue-Adresse gilt die normale Speicherung; eine aus einem privaten Tab stammende Seite wird nicht automatisch übernommen.

Der direkte Downloader wird im vorbereiteten Standard-Release für alle Nutzer nicht kompiliert; ein Xcode-Binärtest steht aus. **Nur Entwicklungsbuilds:** Ausdrücklich gespeicherte Downloads liegen lokal im vom App-Backup ausgeschlossenen Downloads-Verzeichnis. Das gilt auch für bewusst aus privaten Tabs gespeicherte Dateien. Dateiname und Inhalt bleiben bis zum Löschen erhalten. Retry-Quell-URL und Jobstatus verbleiben nur im Arbeitsspeicher; abgebrochene Zwischenstände werden nicht als fertige Dateien angezeigt. URLSession-Downloads unterstützen HTTPS und sind ephemere, cookie-freie Anfragen ohne Browser-Login/DRM-Lizenzen. Server erhalten normale IP-/Anfragedaten. Die Dateien können durch ausdrückliches Teilen an eine andere App übermittelt werden. Website-Daten-Löschen entfernt nicht diese ausdrücklich gespeicherten Dateien oder die Queue; diese werden in ihren eigenen Ansichten entfernt.

Favoriten werden zusätzlich im lokalen App-Group-Container abgelegt, damit WidgetKit und Siri/Kurzbefehle sie lesen können. Widgetauswahl speichert Favoritenreferenzen. iCloud ist standardmäßig aus und nur mit tatsächlich provisioniertem Container verfügbar. Nach opt-in und Neustart synchronisiert SwiftData Verlauf und Favoriten mit Apples privater CloudKit-Datenbank des angemeldeten iCloud-Kontos. Private Tabs, WebKit-Cookies, Browsersitzungen und Timer werden nicht synchronisiert. Abschalten entfernt nicht automatisch bereits in iCloud vorhandene Daten; Löschungen bei aktivem Sync werden synchronisiert. Apples Regeln und iCloud-Aufbewahrung gelten zusätzlich.

Die Bibliothek löscht einzelne Einträge oder nicht favorisierten Verlauf. Website-Daten-Löschen stoppt ausstehende Navigationen, schließt die aktiven Dokumente und löscht danach Cookies/Cache/weitere WebKit-Daten; Verlauf/Favoriten werden gesondert gelöscht. Ein Abbruch wird gemeldet. Deinstallation entfernt lokale App-Daten; geteilter Container und iCloud unterliegen zusätzlicher Systemaufbewahrung.

## Netzwerkanfragen

Besuchte Webseiten und deren Dienste erhalten normale Browseranfragen: IP-Adresse, gewählte Safari-Kennung, gegebenenfalls Cookies und Inhalte. Webseite und Netzbetreiber können diese Daten unabhängig verarbeiten. HTTP-Adressen können unverschlüsselt geladen werden. Suchen werden an den gewählten Anbieter Google, DuckDuckGo oder Bing gesendet. Zugangsdaten enthaltende URL-Eingaben werden weder geladen noch gesucht.

Bei aktivem Filter lädt die App aktivierte Listen beim Start/Vordergrundwechsel höchstens täglich sowie nach Quellenänderungen oder manuellem Update. Presets sind AdGuard DNS (`adguardteam.github.io`), HaGeZi und StevenBlack (`raw.githubusercontent.com`); eigene HTTPS-Quellen oder lokale Textdateien sind möglich. Listenhosts sehen IP-Adresse und technische Anfrageinformationen, erhalten aber keinen Verlauf/Favoriten. Download-Sitzungen sind ephemer und cookie-frei. Eingelesene Quelltexte, Imports und kompilierte Regeln werden lokal gecached. Bei deaktiviertem Filter findet kein automatisches tägliches Update statt; ausdrücklich angeforderte Updates/Quellenänderungen können laden.

SponsorBlock ist standardmäßig aus. Aktivierung sendet YouTube-Video-ID und ausgewählte Kategorien an `sponsor.ajay.app`, auch für eingebettete Player. Seiten-Ausnahmen und Abschalten beenden weitere Abfragen/Skips. Native ephemere Anfragen übertragen keine WebKit-Cookies; der Dienst sieht IP-Adresse und kann eigene Anfragedaten speichern. Segmente liegen kurz im Arbeitsspeicher. Drittanbieterinformationen: https://sponsor.ajay.app/privacy.

Das App-Privacy-Manifest deklariert optionale Browsing-History-Übermittlung für SponsorBlock zur App-Funktion, ohne appseitige Identitätsverknüpfung oder Tracking. Das ersetzt nicht die Release-Datenschutzauskunft einschließlich optionaler SDKs und CloudKit.

## AirPlay, Cast und Systemfunktionen

AirPlay nutzt iOS-Systemrouten. Ein optionaler Google-Cast-SDK-Build fragt lokalen Netzwerkzugriff ab und sucht Receiver. Direkter Medienlink, Titel und Startposition werden an das ausgewählte Gerät übertragen; der Receiver lädt selbst. Browser-Cookies, DRM-Lizenzen und Login-Header werden nicht übernommen. Für Google Cast und Receiver gelten deren eigene Datenschutzinformationen. Standardbuilds enthalten kein Cast SDK und suchen keine Cast-Geräte.

UserDefaults speichert Optionen, Updatezeit, normale Session/Timer und den Favoriten-Snapshot. Required-Reason-Erklärungen CA92.1/1C8F.1 stehen in App-/Widget-Manifesten. Now Playing zeigt Wiedergabeinformationen und verarbeitet öffentliche Remote-Befehle; AVAudioSession konfiguriert Wiedergabe, garantiert aber keine dauerhafte WebKit-Hintergrundausführung.

Kein eigener Analytics-Dienst, Werbe-SDK oder appseitige Cross-App-Tracking-ID. Webseiten und optionale Drittdienste können eigene Verarbeitung betreiben.
