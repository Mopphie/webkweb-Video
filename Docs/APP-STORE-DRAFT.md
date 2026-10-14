# App-Store-Eintrag – Arbeitsentwurf, nicht eingereicht

Stand: 14. Oktober 2026. Die Texte beschreiben den geplanten **Standardbuild** und müssen nach einem echten Xcode-/Gerätetest gegen die tatsächlich ausgelieferte App geprüft werden. Keine Store-Daten wurden hochgeladen. Keine erfundenen Screenshots, Zugänge oder Betreiberangaben.

## Metadaten (de-DE)

- Name: **DevnTube** (8 Zeichen; Verfügbarkeit in App Store Connect noch prüfen)
- Untertitel: **Videobrowser für iPhone & iPad** (30 Zeichen)
- Stichwörter, vorläufig: `browser,video,tabs,favoriten,privatmodus,airplay,bildinbild,sleeptimer,werbeblocker` (83 Zeichen). Vor Nutzung rechtlich und ASO-seitig prüfen; keine Dienstmarken als Suchwörter vereinnahmen.
- Kategorie: **offen**; Betreiber wählt passend zur tatsächlichen App-Store-Einordnung.
- Preis/Regionen: **offen**.
- Altersfreigabe: **offen**; die aktualisierten Fragen in App Store Connect für einen Browser mit unbeschränktem Webseitenzugang und tatsächlicher Inhaltsdarstellung beantworten. Keine Kinderfreigabe ohne Prüfung behaupten.

### Beschreibungsvorschlag

DevnTube ist ein Browser für iPhone und iPad mit Tabs, Favoriten und Werkzeugen für die Wiedergabe von Webseitenvideos. Öffne Webseiten, speichere Favoriten und nutze private Tabs, deren Sitzungen nicht wiederhergestellt werden.

Für unterstützte HTML-Videos bietet die App Wiedergabesteuerung, Bild-in-Bild, AirPlay und einen Sleep-Timer. Ob eine Funktion verfügbar ist, bestimmen die jeweilige Webseite, das Video und iOS. Ein optionaler Netzwerkfilter und SponsorBlock können bestimmte Anfragen beziehungsweise verfügbare Community-Segmente behandeln; sie garantieren keine werbefreie Wiedergabe.

DevnTube ist unabhängig von den aufgerufenen Webseiten und deren Betreibern. Die Nutzung fremder Dienste unterliegt deren Bedingungen.

**Vor Einreichung prüfen:** Jede Aussage am Standardbuild, echte Nutzbarkeit unter iOS 17 und iOS 26, Datenschutz, Dienstbedingungen und Markenrechte. Optionale Cast-/CloudKit-Funktionen nicht in der Beschreibung nennen, solange sie nicht provisioniert und im eingereichten Build enthalten sind. Audio-/Video-Downloads nicht bewerben, solange die Rechtefrage und die Release-Variante ungeklärt sind.

## Vorhandene und offene Eingaben

- Öffentliche HTTPS-Datenschutz-URL: **vorhanden**, <https://mopphie.github.io/webkweb-privacy/> (`WebKWebPrivacyURL`)
- Öffentliche HTTPS-Support-URL: **vorhanden**, <https://mopphie.github.io/webkweb-privacy/support/> (`WebKWebSupportURL`)
- Betreibername/Kontakt: **von der bestehenden Printatops-Seite übernommen**, <https://mopphie.github.io/webkweb-privacy/impressum/> (`WebKWebOperatorContact`); finale Betreiberfreigabe/rechtliche Prüfung ausstehend
- Apple-Team `HUN9MS832X`, explizite IDs `de.mopphie.devntube` und `de.mopphie.devntube.favorites` sowie App Group `group.de.mopphie.devntube`: **im Portal angelegt, Zuordnung bei beiden IDs geprüft**. Beide App-Store-Profile erstellt und gegen IDs, Gruppe und lokales Zertifikat geprüft. `.p12`-Passwort und Gerätetests: **OFFEN**
- iCloud-Container: **NICHT BESTÄTIGT**; CloudKit deaktiviert lassen
- App-Privacy-Antworten einschließlich besuchter Webseiten, optionalem SponsorBlock/Cast/iCloud und SDKs: **OFFEN**, nach finalem Build und Datenflussaudit ausfüllen
- Export-/Verschlüsselungsfragen, Altersfreigabe, Rechte an Icon/Marke und Dienstbedingungen: **OFFEN**
- Autorisierung für Downloads von Audio/Video aus Drittquellen: **FEHLT**. Der Betreiber hat die [Release-Variante ohne Downloads](NO-DOWNLOAD-VARIANT.md) für **alle Nutzer** bestätigt; ein echter Mac-Build fehlt noch. Alternativ erst Rechte für konkret autorisierte Quellen belegen und eine begrenzte Variante entwickeln. Kein versteckter Reviewer-Schalter.

## Echte Screenshots und Review-Hinweise – noch zu erstellen

Auf einem autorisierten Mac mit signiertem Standardbuild auf iPhone und iPad aufnehmen: Startseite mit acht Icons, allgemeine Tabs/Adressleiste, YouTube-Watch-Ansicht mit rotem Menübutton (nur bei erlaubter Marken-/Inhaltsnutzung), Favoriten und Player/Timer. Portrait/Querformat, große Schrift und VoiceOver separat prüfen. Nur **echte App-Screenshots** der finalen Buildversion hochladen; Konzeptgrafiken oder Bildkompositionen sind kein Ersatz. Rechte an sichtbaren Webseiteninhalten vor Store-Verwendung klären.

App-Review-Notizen nach erfolgreichem Gerätetest: native Menünavigation der Watch-Ansicht erklären, Abhängigkeit von Webseiten-/iOS-Funktionen und optionale Einstellungen benennen; Demo-Zugang nur falls tatsächlich benötigt, niemals erfinden. TestFlight-Upload und App-Store-Einreichung erst nach ausdrücklicher Freigabe.

Quelle für die Build-Mindestanforderung und neuen Altersfreigabe-Fragebogen: [Apple Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/). Weitere Review-Risiken: [APP-REVIEW-DESIGN.md](APP-REVIEW-DESIGN.md), [RELEASE.md](RELEASE.md).
