# DevnTube / WebKWeb

Native SwiftUI-/WebKit-App für iPhone und iPad, mit eigenem AVKit-Player und lokaler Mediathek für rechtmäßig nutzbare Dateien/Direktquellen. Deployment iOS 17+, Xcode-Projektgenerierung über `project.yml` (Xcode 26+). Keine externen App-SDKs, kein eigenes Backend oder Konto.

**Aktueller lokaler Stand: nicht releasebereit.** Dieser Auftrag hat keinen neuen iOS-Build, TestFlight-Upload oder Remote-Push ausgelöst. Frühere Build-5-Ergebnisse gelten ausschließlich für den historischen Quellstand. Alle aktuellen iOS-/Geräteprüfungen sind noch auszuführen.

- Browser/Suche, normale/private Tabs, Pins/Gruppen, Favoriten/Verlauf und erreichbare Navigation.
- Eigene native Dateien/ausdrücklich autorisierte Direktmedien, ein stabiler Player mit Miniplayer/System-PiP/AirPlay und vorgesehener Hintergrund-Audiowiedergabe.
- Separate Queue und benannte Playlists, Weitersehen, eigene Zeitmarken/Notizen, Dateien-Neuverknüpfung und versionierte Datensicherung.
- Optionale Geräteauthentifizierung, bewusst freigegebene Widget-/Siri-Favoriten ohne eingehende Teilen-Erweiterung.
- Normale Websites bleiben echte Websites. Keine Plattform-Werbeblockierung, SponsorBlock, Stream-Extraktion, Plattformdownloads, Cast-SDK oder erzwungene Premium-/Hintergrundfunktionen. Allgemeine Hauptseiten-Sperrliste statt Ressourcenfilter. Keine neuen Käufe/Abos; iCloud nicht eingerichtet.

## Prüfung und Dokumentation

1. [APP_AUDIT](Docs/APP_AUDIT.md) — tatsächlicher Bestand, Architektur, Netz-/Datenflüsse.
2. [LICENSE_REGISTER](Docs/LICENSE_REGISTER.md) — vier getrennte Rechte-/Bedingungsebenen und Primärquellen.
3. [FEATURE_MATRIX](Docs/FEATURE_MATRIX.md) — vollständige Entscheidungen F01–F31.
4. [PROVIDER_CAPABILITIES](Docs/PROVIDER_CAPABILITIES.md) — echte Grenzen nach Quelle.
5. [REMOVALS_AND_MIGRATIONS](Docs/REMOVALS_AND_MIGRATIONS.md) — vollständige Bereinigung und Datenerhalt.
6. [TEST_REPORT](Docs/TEST_REPORT.md) — ausgeführte und nicht ausgeführte Tests.
7. [APP_REVIEW_NOTES](Docs/APP_REVIEW_NOTES.md) — reproduzierbare Wege, keine Einreichung.
8. [RELEASE_BLOCKERS](Docs/RELEASE_BLOCKERS.md) — konkrete nächste Voraussetzungen.
9. [Datenschutzhinweise](PRIVACY.md).

Lokale portable Prüfungen: `python3 Scripts/check-portable.py`; eigener echter Chromium-Decoder: `python3 Scripts/check-browser.py` (Playwright/Chromium/ffmpeg als Testwerkzeuge). Foundation-Modelle und Swift-Syntax: `./Scripts/check-core.sh` mit lokal vorhandenem offiziellen Swift-6.1-Container, ohne Netzwerk im Testcontainer. Das ist **kein Apple-SDK-Build**.

Auf einem verfügbaren lokalen Mac: `./Scripts/check-macos.sh`; anschließend Pflichtreise und Gerätefälle aus dem Testbericht. Der Mac-Testhelfer signiert oder lädt nicht hoch. Der autorisierte TestFlight-Workflow signiert App und Favoriten-Widget mit ihren bestehenden separaten Profilen. Die eingehende Teilen-Erweiterung und deren Signieranforderungen sind auf Nutzerwunsch entfernt. Ein alter CloudKit-Konfigurationshelfer implementiert keinen fertigen Datenabgleich.

Historische `Docs/RELEASE.md`, `FUNCTION-TEST-MATRIX.md`, `AUDIT-FIXES.md`, `COMMERCIAL-USE.md`, Store-/Designentwürfe dokumentieren frühere Zustände. Die oben verlinkten Dokumente ersetzen deren aktuelle Produkt-/Freigabeaussagen. Keine weltweite Rechtsfreigabe, Apple-Annahme oder universelle Plattformwiedergabe zugesichert.
