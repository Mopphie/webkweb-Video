# Kommerzielle Nutzung: Bereinigung und verbleibende Pflichten

Prüfstand: 15. Oktober 2026. Geprüft wurden die eingecheckten Quellen, Ressourcen, Abhängigkeiten und konfigurierten Dienste. Dies ist ein nachvollziehbarer technischer Prüfstand; keine umfassende Rechtsfreigabe und keine App-Store-Zusage. Lizenzen, Nutzungsbedingungen und Rechte an einzelnen Medien sind getrennt zu betrachten.

## Aus dem Produkt entfernt

| Bestandteil | Beleg und Entscheidung |
| --- | --- |
| SponsorBlock-API und Datenbankintegration | Die [offizielle API-/Datenbanklizenz](https://github.com/ajayyy/SponsorBlock/wiki/Database-and-API-License) ist CC BY-NC-SA 4.0 ohne gesonderte Erlaubnis. Eine solche Erlaubnis liegt hier nicht vor. Service, Aufrufe, Skip/Undo, Einstellungen, Kategorien und Datenübertragung wurden entfernt. Die Lizenz des Extension-Codes wäre eine andere Frage. |
| StevenBlack-Preset | Das [README mit Quellenlizenzen](https://github.com/StevenBlack/hosts#sources-of-hosts-data-unified-in-this-variant) nennt unter anderem Dan Pollock/someonewhocares als nichtkommerziell. Die [MIT-Lizenz des Repositories](https://github.com/StevenBlack/hosts/blob/master/license.txt) allein klärt diese gemischten Eingangsrechte nicht. Das Preset und bereits gespeicherte Abos auf diesen Repositorypfad werden entfernt; frühere kompilierte Filter werden durch einen neuen Cache-Namensraum nicht erneut angewendet. Eigene lokale Importdateien werden nicht gelöscht. |
| Audio-/Video-Dateidownloads | Keine dokumentierte Quellenautorisierung vorhanden. [Apple 5.2.3](https://developer.apple.com/app-store/review/guidelines/#intellectual-property) fordert diese für Downloads von Drittquellen; direkter HTTPS-Zugriff beweist sie nicht. Downloader, Oberfläche und Export der direkten Medienadresse sind in allen Buildkonfigurationen entfernt. Bereits gespeicherte Nutzerdateien werden nicht angetastet. |
| Optionale Google-Cast-Einbindung | Die [SDK-Bedingungen](https://developers.google.com/cast/docs/terms) erlauben grundsätzlich kommerzielle Nutzung unter Bedingungen. Die bisherige Integration hatte keinen dokumentierten App-Registrierungsnachweis (§3.3), keine dokumentierte Inhaltsfreigabe (§3.4) und bot den SDK-Button im Untermenü (§5.1.2). Statt diese Voraussetzungen als erfüllt zu behaupten, wurden SDK, Podfile, Discovery, Übertragung und Berechtigungen entfernt. Apple AirPlay bleibt. |
| Nachgezeichnete Plattformmarken | YouTube-/Twitch-/TikTok-/Rumble-ähnliche Symbole wurden durch neutrale systemseitige Globus-Symbole ersetzt. Die Namen bleiben als beschreibende Website-Lesezeichen. Die [YouTube-Markenregeln](https://developers.google.com/youtube/terms/branding-guidelines) sind keine pauschale Erlaubnis für veränderte Marken. |
| Eingebaute YouTube-Werbeendpunkte | Die besonderen Regeln für `pagead/` und `api/stats/ads` wurden aus dem eigenen Basisfilter entfernt. Der allgemeine WebKit-Domainfilter bleibt; daraus folgt keine Freigabe jeder denkbaren Filteranwendung durch einen Dienst. |

Es gibt keine Review-exklusive Freischaltung und keine versteckte alternative Variante dieser entfernten Funktionen.

## Verbleibende Bestandteile

| Bestandteil | Grundlage / Umfang |
| --- | --- |
| Swift-/JavaScript-Projektcode | Keine eingebundenen fremden Swift-/JS-Pakete oder heruntergeladenen Scriptlets festgestellt. Diese Bestandsaufnahme beweist keine Rechtekette für eventuelle frühere externe Beiträge; vor Vertrieb müssen dem Betreiber die Rechte am Projektcode zustehen. |
| AdGuard DNS und HaGeZi Light | Beide ausgewählten Listen verweisen auf GPLv3 ([AdGuard](https://github.com/AdguardTeam/AdGuardSDNSFilter/blob/master/LICENSE), [HaGeZi](https://github.com/hagezi/dns-blocklists/blob/main/LICENSE)). **GPL erlaubt kommerzielle Nutzung.** Die Listen werden separat geladen, nicht in der App ausgeliefert. Lizenzhinweise und der vollständige GPLv3-Text liegen in den App-Ressourcen und sind in den Einstellungen erreichbar. Originaldateien samt Headern bleiben im lokalen Quellencache erhalten. Bei späterer Weitergabe von Listen/abgeleiteten Regeln sind insbesondere Lizenz-/Hinweis- und anwendbare Quelltextpflichten zu erfüllen. Die HaGeZi-[Quellenübersicht](https://github.com/hagezi/dns-blocklists/blob/main/sources.md) weist ausdrücklich auf individuelle Eingangslizenzen hin; eine pauschale Prüfung aller künftig wechselnden Eingangsdaten ist damit nicht behauptet. |
| Eigene Filterimporte | Allgemeine Importfunktion für Dateien/HTTPS-Quellen. Sie erteilt keine Nutzungsrechte an den importierten Inhalten. Für mit einem künftigen Release vorinstallierte neue Quellen muss die Rechteprüfung erneut erfolgen. |
| Apple-Systemfunktionen | Öffentliche SwiftUI-/WebKit-/Medien-/Widget-/App-Intents-APIs und systemseitige SF Symbols. Vertrieb erfordert die jeweils geltenden Apple-Verträge, Signing/Provisioning und gegebenenfalls App-Store-Prüfung. |
| App-Icon | Vom Betreiber auf `main` bereitgestellte burgunderfarbene Projektgrafik; keine fremde Plattformmarke als App-Icon festgestellt. Herkunfts-/Nutzungsrechte dieser Betreiberdatei und Namens-/Markenprüfung für den Produktnamen bleiben separat zu bestätigen. |
| Browserinhalt | Keine lokal gebündelten fremden Videos, Thumbnails oder Referenzscreenshots. Die echte Website wird durch WebKit geladen. Ihre Inhalte gehören den jeweiligen Rechteinhabern; eine kommerzielle Browser-App erwirbt dadurch keine Rechte zur kommerziellen Verwertung der Inhalte. [YouTube-Bedingungen](https://www.youtube.com/static?template=terms) und Bedingungen weiterer aufgerufener Dienste bleiben anwendbar. |

## Vor einer Veröffentlichung

* Den finalen Mac-/Gerätebuild, die tatsächlich ausgelieferten Ressourcen und die Datenschutzauskunft prüfen.
* Betreiber, öffentliche Kontakt-/Datenschutz-/Supportangaben und den Produktnamen verbindlich bestätigen. Im Repository nachträglich konfigurierte URLs sind kein Nachweis ihrer rechtlichen Freigabe.
* Ausschließlich eigene oder passend lizenzierte Demo-Videos, Vorschaubilder und echte App-Screenshots für Werbung/Store verwenden. Die vom Nutzer bereitgestellten YouTube-Referenzen sind keine kommerziell freigegebenen Marketingmedien und gehören nicht ins App-Bundle.
* Die externe öffentliche Datenschutzwebsite an die entfernten Funktionen anpassen, bevor dieser Build verteilt wird; diese Änderung bearbeitet ausschließlich das App-Repository.

Der Nutzer hat GitHub Actions am 16.10.2026 ausdrücklich jederzeit für Builds und Tests freigegeben. Der neue Validierungsworkflow startet auf dem Entwicklungsbranch; der TestFlight-Workflow unterstützt manuellen Dispatch und den gesondert beauftragten TestFlight-Release-Branch. Diese Testfreigabe enthält keine App-Store-Veröffentlichung.
