# Optionales Google Cast

Der Standardbuild enthält keinen Google-Cast-Code als SDK-Abhängigkeit. AirPlay funktioniert über die nativen iOS-Steuerelemente. Die Cast-Oberfläche zeigt ehrlich, wenn das SDK fehlt.

## SDK integrieren

Auf einem Mac mit CocoaPods:

```bash
xcodegen generate
cp Podfile.cast Podfile
pod install
open WebKWeb.xcworkspace
```

`Podfile.cast` verwendet das offizielle `google-cast-sdk-no-bluetooth`-Pod (4.x, kompatibel mit dem verwendeten öffentlichen API). SDK-Version und deren Privacy-Manifest vor einem Release auf Aktualität prüfen und `Podfile.lock` für einen konkreten Produktbuild festhalten. Nach erneutem `xcodegen generate` auch `pod install` erneut ausführen. Standardmäßig wird Googles Default Media Receiver (`CC1AD845`) verwendet; für einen eigenen Receiver müssen App-ID und Bonjour-Eintrag zusammen geändert werden.

`canImport(GoogleCast)` aktiviert die Anbindung in `App/CastService.swift`. `configure()` erstellt `GCKCastContext`; `GCKUICastButton` öffnet die Geräteauswahl. Der Übertragen-Button baut eine `GCKMediaInformation` mit direktem `currentSrc`, MIME-Typ, Titel und Startzeit und sendet sie über `GCKRemoteMediaClient.loadMedia`. Eine gesendete Anfrage ist keine Bestätigung erfolgreicher Receiver-Wiedergabe; dessen Status erscheint über die Google-Cast-Geräte-/Mediensteuerung.

Die Info.plist enthält `NSLocalNetworkUsageDescription` und `_googlecast._tcp` / `_CC1AD845._googlecast._tcp`. Der optionale SDK-Build löst die iOS-Lokalnetzwerk-Abfrage aus. Ohne SDK wird keine Cast-Suche gestartet.

## Funktionsgrenzen

Nur direkte, unverschlüsselte HTTP(S)-Quellen mit bekanntem Medien-MIME-Typ oder passender Dateiendung sind auswählbar. `blob:`, EME/DRM-Medien und Watch-Seiten werden abgelehnt. Die Erkennung kann serverseitig geschützte HTTP-Links nicht zuverlässig als solche erkennen. Der Benutzer muss einen öffentlich erreichbaren Link wählen; fehlende Cookies, abgelaufene signierte URLs, fehlende CORS-Unterstützung, Receiver-Codecs oder DRM können die Cast-Wiedergabe verhindern. WebKWeb extrahiert keine YouTube-Streams und ersetzt die URL nicht durch eine YouTube-Watch-Seite.

SponsorBlock und HTML-video-basierte Videozählung wirken im Browserplayer. Sie werden nicht auf Cast gespiegelt. Der Zeit-Timer pausiert eine aktive Cast-Session, wenn die App zur Ausführung kommt; eine von iOS suspendierte App garantiert keinen Stop am Receiver. HTTPS-HLS-Livestreams sind Receiver-abhängig; der aktuelle Load-Pfad ist auf normale, seekbare Medien ausgerichtet.

Prüfen: reales Cast-Gerät im gleichen Netz; Berechtigung erteilen/ablehnen; freie MP4/HLS-Quelle; blob-/DRM-Quelle; nicht erreichbare Quelle; Wechsel der Cast-Session und Timer-Pause. Der optionale Cast-Build wurde in der Linux-Umgebung nicht kompiliert oder auf Geräten getestet.
