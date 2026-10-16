# Datenschutzhinweise für DevnTube

Stand: 16. Oktober 2026. Technischer Entwicklungsstand. Die öffentliche [Datenschutzerklärung](https://mopphie.github.io/webkweb-privacy/), der [Support](https://mopphie.github.io/webkweb-privacy/support/) und das [Impressum](https://mopphie.github.io/webkweb-privacy/impressum/) sind erreichbar. Diese Datei dokumentiert zusätzliche Implementierungsdetails; maßgeblich bleibt die Prüfung am später tatsächlich ausgelieferten Build. Die externe Datenschutzerklärung muss vor Verteilung dieses Builds die entfernten Integrationen widerspiegeln.

## Lokale Daten und optionale iCloud-Synchronisierung

SwiftData speichert Titel, vollständige Adressen und Besuchszeitpunkte für Verlauf/Favoriten. Nicht favorisierte Historie ist auf 500 Einträge begrenzt und kann abgeschaltet werden. Favoriten lassen sich bearbeiten, sortieren und löschen. Vollständige URLs können Suchbegriffe, Video-IDs und Parameter enthalten. Benutzername/Passwort werden nicht gespeichert. Normale Tabs und Zeit-/Anzahl-Timer werden separat lokal wiederhergestellt; Tab-Restore lässt sich abschalten und ist unabhängig von History-off.

Private Tabs verwenden einen nicht persistenten WebKit-Speicher. Sie erscheinen weder im Verlauf noch im Session-/Timer-Snapshot. Ein bewusst aus einem privaten Tab gespeicherter Favorit wird in die normale Favoritenbibliothek übernommen. Private Titel erscheinen nicht in System-Medienmetadaten. Privates Browsen verbirgt Netzwerkanfragen nicht vor Webseiten, Netzbetreibern oder optionalen Filterquellen.

Die normale URL-/Favoriten-Wiedergabequeue, ihre Shuffle-Reihenfolge und Repeat-Einstellung werden lokal in UserDefaults gespeichert, ohne private Tabs und ohne iCloud-Sync. Die Bibliothek/Queue bietet das Entfernen einzelner Einträge. Bei einer ausdrücklich eingegebenen Queue-Adresse gilt die normale Speicherung; eine aus einem privaten Tab stammende Seite wird nicht automatisch übernommen.

Die App enthält keine native Medien-Downloadfunktion mehr. Lokal gespeicherte Dateien aus früheren Versionen werden durch diese Änderung weder geöffnet noch übertragen oder automatisch gelöscht. Auch das Löschen von Website-Daten entfernt diese Dateien nicht. Die App bietet dafür keine neue Download- oder Dateiverwaltungsoberfläche.

Favoriten werden zusätzlich im lokalen App-Group-Container abgelegt, damit WidgetKit und Siri/Kurzbefehle sie lesen können. Widgetauswahl speichert Favoritenreferenzen. iCloud ist standardmäßig aus und nur mit tatsächlich provisioniertem Container verfügbar. Nach opt-in und Neustart synchronisiert SwiftData Verlauf und Favoriten mit Apples privater CloudKit-Datenbank des angemeldeten iCloud-Kontos. Private Tabs, WebKit-Cookies, Browsersitzungen und Timer werden nicht synchronisiert. Abschalten entfernt nicht automatisch bereits in iCloud vorhandene Daten; Löschungen bei aktivem Sync werden synchronisiert. Apples Regeln und iCloud-Aufbewahrung gelten zusätzlich.

Die Bibliothek löscht einzelne Einträge oder nicht favorisierten Verlauf. Website-Daten-Löschen stoppt ausstehende Navigationen, schließt die aktiven Dokumente und löscht danach Cookies/Cache/weitere WebKit-Daten; Verlauf/Favoriten werden gesondert gelöscht. Ein Abbruch wird gemeldet. Deinstallation entfernt lokale App-Daten; geteilter Container und iCloud unterliegen zusätzlicher Systemaufbewahrung.

## Netzwerkanfragen

Besuchte Webseiten und deren Dienste erhalten normale Browseranfragen: IP-Adresse, gewählte Safari-Kennung, gegebenenfalls Cookies und Inhalte. Webseite und Netzbetreiber können diese Daten unabhängig verarbeiten. HTTP-Adressen können unverschlüsselt geladen werden. Suchen werden an den gewählten Anbieter Google, DuckDuckGo oder Bing gesendet. Zugangsdaten enthaltende URL-Eingaben werden weder geladen noch gesucht.

Bei aktivem Filter lädt die App aktivierte Listen beim Start/Vordergrundwechsel höchstens täglich sowie nach Quellenänderungen oder manuellem Update. Presets sind AdGuard DNS (`adguardteam.github.io`) und HaGeZi (`raw.githubusercontent.com`); eigene HTTPS-Quellen oder lokale Textdateien sind möglich. Listenhosts sehen IP-Adresse und technische Anfrageinformationen, erhalten aber keinen Verlauf/Favoriten. Filterabrufe sind ephemer und cookie-frei. Eingelesene Quelltexte, Imports und kompilierte Regeln werden lokal gecached. Bei deaktiviertem Filter findet kein automatisches tägliches Update statt; ausdrücklich angeforderte Updates/Quellenänderungen können laden.

## AirPlay und Systemfunktionen

AirPlay nutzt ausschließlich iOS-Systemrouten. Die App enthält weder SponsorBlock-Abfragen noch das Google Cast SDK und führt keine eigene Cast-Gerätesuche aus. Es werden keine direkten Medien-URLs an eine solche Integration übergeben. Das App-Privacy-Manifest enthält keine frühere SponsorBlock-Browsing-History-Deklaration. Die Release-Datenschutzauskunft muss weiterhin dem finalen Build, den besuchten Webseiten und gegebenenfalls CloudKit entsprechen.

UserDefaults speichert Optionen, Updatezeit, normale Session/Timer und den Favoriten-Snapshot. Required-Reason-Erklärungen CA92.1/1C8F.1 stehen in App-/Widget-Manifesten. Now Playing zeigt Wiedergabeinformationen und verarbeitet öffentliche Remote-Befehle; AVAudioSession konfiguriert Wiedergabe, garantiert aber keine dauerhafte WebKit-Hintergrundausführung.

Kein eigener Analytics-Dienst, Werbe-SDK oder appseitige Cross-App-Tracking-ID. Webseiten und optionale Drittdienste können eigene Verarbeitung betreiben.

## Freiwillige Playerdiagnose

Jeder Tab hält höchstens 40 technische Wiedergabeereignisse im Arbeitsspeicher. Erfasst werden App-Build, Wiedergabe-/Lade-/Pausezustand, Filterstatus, Zeitposition, Dauer, verfügbare Framezähler und Audio-Unterbrechungen. Der Bericht enthält beim normalen Tab nur den Hostnamen, bei privaten Tabs stattdessen „private“. Vollständige Webseiten-/Video-/Medienadressen, URL-Parameter, Seitentitel, Cookies und Inhalte werden nicht übernommen.

„Playerdiagnose kopieren“ legt den Bericht ausschließlich nach ausdrücklichem Antippen in die lokale iOS-Zwischenablage, ohne Universal Clipboard und mit fünf Minuten Ablaufzeit. Die App übermittelt den Bericht nicht an einen Server. Wer ihn anschließend selbst in einen Chat oder eine andere App einfügt, veranlasst diese Weitergabe selbst.
