# Optionales Google Cast

Der Standardbuild benötigt kein Cast SDK und startet keine Gerätesuche. Für den echten SDK-Build auf einem Mac mit CocoaPods:

```bash
xcodegen generate
pod install
open WebKWeb.xcworkspace
./Scripts/check-macos.sh --cast
```

Der eingecheckte `Podfile` verwendet Googles offizielles `google-cast-sdk-no-bluetooth` (`~> 4.8`). Die auf dem Mac aufgelöste Version, ihr Privacy-Manifest und `Podfile.lock` vor einem Release prüfen und festhalten. Nach `xcodegen generate` erneut `pod install` ausführen. Standardmäßig wird der Default Media Receiver (`CC1AD845`) verwendet; eine eigene Receiver-ID verlangt auch die entsprechende Bonjour-Konfiguration.

`canImport(GoogleCast)` aktiviert echte SDK-Aufrufe: `GCKCastContext`, Geräteauswahl, `GCKRemoteMediaClient.loadMedia`, Session-/Request-/Media-Listener, laufende Receiverposition und Play/Pause/Seek/Trennen sowie Googles erweiterte Mediensteuerung. Der MIME-Typ gehört zur tatsächlich gewählten `currentSrc`. Die lokale Wiedergabe wird nach bestätigter Ladeanfrage pausiert; ein zwischenzeitlicher Benutzerstopp oder Timerablauf wird auch bei verspäteten Callbacks respektiert. Receiverfehler werden angezeigt. Eine erfolgreiche Ladeanfrage garantiert keinen decodierbaren Stream.

Info.plist enthält Lokalnetzwerk-Erklärung und `_googlecast._tcp` / `_CC1AD845._googlecast._tcp`. Ohne SDK werden diese Berechtigungen nicht zur Discovery benutzt.

Nur direkte, unverschlüsselte HTTP(S)-Quellen mit bekanntem MIME-Typ oder Dateiendung werden angeboten. Keine Übertragung von `blob:`/MSE, EME/DRM, Browser-Cookies, Login-Headern oder YouTube-Watch-Seiten. Öffentliche Erreichbarkeit, URL-Gültigkeit, Receiver-Codecs und gegebenenfalls CORS bleiben erforderlich. Es werden keine YouTube-Streams extrahiert. Der aktuelle Load-Pfad verwendet `.buffered`; kein besonderer Live-Receiver-/DVR-Modus.

SponsorBlock und Videozählung steuern den lokalen HTML-Player. Der Zeit-Timer pausiert eine aktive Cast-Session, wenn die App ausgeführt wird; App-Suspension verhindert eine Zeitgarantie. Testfälle: reales Gerät, Berechtigung erlauben/ablehnen, freie MP4/HLS-Quelle, unerreichbare Quelle, Sessionwechsel, verspäteter Load nach Pause/Timer, Receiverfehler und Remote-Controls. SDK-Build und Hardwaretests sind in Linux nicht ausführbar und bleiben offen. Session-/Media-Callback-Signaturen wurden zusätzlich mit Googles offizieller Swift-Beispielapp abgeglichen.
