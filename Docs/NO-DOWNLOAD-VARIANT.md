# Vollständige Entfernung der Medien-Downloadfunktion

Stand: 15.10.2026. Der Nutzer hat die Entfernung autorisiert. Ohne belegte Autorisierung fremder Medienquellen wurde die native Audio-/Video-Downloadfunktion aus dem gesamten Projekt entfernt, einschließlich Entwicklungsbuilds. Es gibt keinen Compile-Flag, keinen internen Download-Sheet-Pfad und keinen versteckten Nutzungs- oder Reviewer-Schalter mehr.

Entfernt wurden Downloader/Jobs/Dateiverwaltung, Downloadmenüs und -Ansicht, Download-spezifische Tests und die Medien-URL-/MIME-Weitergabe. Die bisherige Release-only-Bedingung ist entfallen. SponsorBlock und Google Cast sind ebenfalls vollständig entfernt; Begründung und verbleibende Lizenzen: [COMMERCIAL-USE.md](COMMERCIAL-USE.md).

Bestehende Nutzerdateien im bisherigen Application-Support/Downloads-Verzeichnis werden nicht automatisch gelöscht, migriert oder übertragen. Die neue App erzeugt dort keine Dateien und bietet keine Download-/Dateiverwaltungsoberfläche mehr. Eine Deinstallation unterliegt weiterhin der normalen iOS-Datenlöschung.

`python Scripts/check-portable.py` prüft die Abwesenheit der entfernten Dateien, Produktionssymbole, Buildflags und Cast-Netzwerkberechtigungen sowie verbleibende Tests und Projektstruktur. Das ersetzt keinen echten iOS-Build. Vor Veröffentlichung auf einem Mac mit Xcode 26+/iOS-26-SDK `./Scripts/check-macos.sh` ausführen, Debug/Release und das Archiv prüfen und bestehende Nutzerdateien bei einem Update kontrollieren.

AirPlay, HTML-Wiedergabesteuerung, PiP, Timer und Browserfunktionen bleiben erhalten. Nutzungsbedingungen besuchter Dienste, öffentliche Datenschutzangaben und App Review bleiben gesonderte Release-Prüfpunkte. Keine GitHub-Actions-Ausführung oder Apple-Einreichung wurde dadurch ausgelöst.
