# DevnTube — lokale Datenschutzhinweise

Stand 16. Oktober 2026. Dieser Quellstand wurde nicht veröffentlicht. Betreiber/Verantwortlicher ist noch zu bestätigen; vorher ist keine Veröffentlichung freigegeben. Die in der App hinterlegten öffentlichen Support-/Privacy-Seiten müssen inhaltlich aktualisiert werden.

DevnTube verwendet kein eigenes Backend, Werbe-, Analytics-, Fingerprinting- oder Tracking-SDK und erfordert kein eigenes Konto. Daraus folgt nicht, dass beim Browsen keine Daten verarbeitet oder an Websites übertragen werden.

## Normale Nutzung

Normale Einstellungen, Tabwiederherstellung, Link-/Medienqueue, Favoriten, maximal 500 nicht favorisierte Verlaufsseiten, eigene Playlists, Notizen und Weitersehen liegen lokal. Die Mediathek speichert bei eigenen Dateien eine lokale Dateiberechtigung, keine automatische Videokopie. Die Dateien-App bzw. ihr Anbieter kann eigene Netz-/Cloudfunktionen verwenden. Normale App-Daten können Teil regulärer Betriebssystem-Backups sein. Es gibt keinen App-CloudKit-Abgleich.

WebKit lädt besuchte Seiten und ihre Ressourcen direkt. Betreiber erhalten übliche Browserdaten, z.B. IP-Adresse, HTTP-Anfragen, Cookies und ggf. eigene Trackinginformationen. Suchbegriffe gehen an den gewählten Anbieter Google, DuckDuckGo oder Bing. Wiederhergestellte normale Tabs können beim Start erneut ihre Website laden. Autorisierte Direktquellen laden über Apples Medienframework vom angegebenen Server; keine Streamsuche, kein Proxy und kein Plattformdownload. Es gibt keine Filterlisten-/SponsorBlock-/Metadaten-API-Anfragen.

Einzelne Favoriten/Verlaufseinträge lassen sich löschen; Verlaufslöschung entfernt zusätzlich Besuchs-/Weitersehenwerte und flüchtige geschlossene Tabs. Favoriten, unabhängige eigene Listen/Notizen und Dateien bleiben. Website-Cookies/Cache werden separat nach Schließen aktiver Seiten gelöscht. Einige URLs können vertrauliche Informationen enthalten: App-Speicherung/Export weist Credentials und gängige Token-/OAuth-Parameter ab. Eine vollständige semantische Erkennung beliebiger URL-Geheimnisse ist nicht möglich.

## Privatmodus

Private Webtabs verwenden nicht persistenten WebKit-Speicher. Kein automatischer Verlauf, Resume, normaler Favorit/Playlist, Tabrestore, app-eigener Titel-/Thumbnailcache, Widget, Intent, Spotlight-Eintrag, Export, iCloud-Datensatz oder App-Diagnose wird aus ihnen erzeugt. Private Popups bleiben im Privatbereich. Beim Beenden der Sitzung werden Tabs geschlossen; beim Appwechsel wird privates Websiteaudio pausiert und die App-Vorschau verdeckt. App-seitiges System-PiP ist für private Webtabs deaktiviert. Eigene private Now-Playing-Metadaten werden nicht veröffentlicht.

Ein bewusst gespeicherter privater Favorit benötigt eine klare Bestätigung: Link und Titel verlassen dann den Privatbereich und werden normale Daten. Ein solcher allein gespeicherter Favorit ist noch kein besuchter normaler Verlaufseintrag. Eigene bereits normale Bibliotheksmedien bleiben ein ausdrücklich normaler Bereich; sie werden nicht automatisch zu privaten Medien, nur weil parallel ein privater Tab offen ist.

Privatmodus ist keine Anonymisierung gegenüber Websites, Netzbetreiber oder Internetanbieter und keine Garantie vollständiger Spurenfreiheit auf OS-/Websiteebene. Eine optionale Gerätecode-/Biometriesperre schützt die Appoberfläche und ihre Vorschau, einschließlich geöffneter Sheets; sie ist keine zusätzliche Vollverschlüsselung. Bereits bewusst gestartete normale native Systemwiedergabe kann mit System-PiP/AirPlay/Medienanzeigen weiterlaufen.

## Bewusstes Teilen und Systemfunktionen

Normale Favoriten werden erst nach Opt-in für Widgets und Siri in die lokale App Group kopiert. Private Sitzungen werden nicht geteilt. Ein Widerruf leert den Snapshot und fordert Widgetaktualisierung an; iOS bestimmt Aktualisierung und kann alte OS-Vorschläge/Timelines behalten. Die App führt keine automatische private Intent-Donation oder Spotlight-Indexierung durch. App-Aktionen dürfen die aktivierte Sperre nicht umgehen.

Die eingehende Teilen-Erweiterung ist entfernt. Ihr früherer lokaler Übergabepuffer wird beim Start gezielt gelöscht; unabhängige Widget-Favoriten bleiben erhalten. Export enthält normale eigene Favoriten/Listen/Notizen und ausgewählte harmlose Browseroptionen, keine Cookies, Credentials, privaten Tabs, Dateiberechtigungen, Sperrkonfiguration oder Wiedergabehistorie. Ziel und Weitergabe des Exports bestimmt der Nutzer.

Der native Systemplayer kann normale Titel, Zeit und Steuerelemente an iOS-Medienanzeigen übergeben. AirPlay nutzt die von iOS gewählten Geräte und deren Regeln; kein lokaler Browserfilter auf dem Empfänger wird zugesichert. Nur ausdrückliches Kopieren einer normalen Playerdiagnose überträgt bis zu 40 RAM-Ereignisse/numerische Zustände in die lokale Zwischenablage, ohne Titel, URLs, Cookies oder Zugangsdaten; localOnly, Ablauf nach fünf Minuten. Private Diagnosen sind deaktiviert, kein automatischer Upload.

## Noch vor Veröffentlichung zu erledigen

Verantwortlicher/Kontakt, Vertriebsländer, Aufbewahrungs-/Betroffenenrechtsangaben und öffentliche Texte bestätigen. Apple-App-Privacy-Antworten anhand des tatsächlichen offenen Browsers gegenüber gezielter Drittseitenintegration prüfen: Apple unterscheidet diese Fälle. Keine automatische globale Erklärung „keine Daten erhoben“ aus dem fehlenden eigenen Backend ableiten. Details: [Audit](Docs/APP_AUDIT.md), [Register](Docs/LICENSE_REGISTER.md), [Releaseblocker](Docs/RELEASE_BLOCKERS.md).
