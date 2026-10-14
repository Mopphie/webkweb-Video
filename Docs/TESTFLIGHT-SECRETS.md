# GitHub-TestFlight-Vorbereitung – KEIN Workflow gestartet

PhotoMaid benutzt in `F:/PhotoMaid-release-prep/.github/workflows/testflight.yml` genau diese **sechs Namen** für einen manuellen TestFlight-Upload. GitHub Actions in `Mopphie/webkweb-Video` hat derzeit keine Workflows und keine Repository-Secrets. **Die Namen sind ein Muster, keine fertige WebKWeb-Signierung.** Keine Werte, Private Keys oder Passwörter in dieses Repository oder in einen Chat kopieren.

1. `APP_STORE_CONNECT_KEY_ID` – ID eines autorisierten App-Store-Connect-API-Schlüssels.
2. `APP_STORE_CONNECT_ISSUER_ID` – zugehörige Issuer-ID.
3. `APP_STORE_CONNECT_API_KEY_BASE64` – Base64 der privaten `.p8`-Datei.
4. `APPLE_CERTIFICATE_PASSWORD` – Exportpasswort der Apple-Distribution-`.p12`.
5. `APPLE_CERTIFICATE_BASE64` – Base64 der `.p12` mit privatem Signierschlüssel.
6. `APPLE_PROVISIONING_PROFILE_BASE64` – Base64 des **WebKWeb-App-Store-Profils**, nicht des PhotoMaid-Profils.

**Zusätzlich erforderlich:** WebKWeb hat ein eingebettetes Widget. Für manuelle Signierung ist ein **eigenes Widget-App-Store-Profil** nötig (etwa `APPLE_WIDGET_PROVISIONING_PROFILE_BASE64` als siebtes Secret). Alternativ ein sicher definiertes Paket beider Profile in einem Secret; dafür müsste der Workflow passend implementiert sein. Team-ID, App-Bundle-ID, Widget-Bundle-ID und App Group sind Konfiguration/Repository-Variablen, nicht automatisch ein siebtes Passwort. `CODE_SIGN_STYLE: Automatic` im aktuellen Projekt ist noch kein funktionsfähiger manueller CI-Signing-Pfad.

**Nur lokale Bestandsprüfung (14.10.2026):** Unter `F:/PhotoMaid_Signing/` liegen eine syntaktisch gültige `.p8`, eine `.p12`, ein Distribution-Zertifikat und ein PhotoMaid-App-Store-`.mobileprovision`. Das PhotoMaid-Profil enthält `HUN9MS832X.com.mrdevn4ever.photomaid`, keine App Group, und läuft am 10.10.2027 ab. Zertifikat und Profil sind deshalb **keine WebKWeb-Profile**; sie beweisen auch keine Freigabe des API-Schlüssels für WebKWeb. Die vorhandene `.txt` ist eine Exportanleitung, **kein** nachweislich gültiges `.p12`-Passwort. Keine WebKWeb-App- oder Widget-Profile gefunden. GitHub-Secrets der PhotoMaid-Organisation sind mit dem aktuellen GitHub-Konto nicht lesbar; Repository-Secrets liefern ohnehin niemals ihre Werte zurück.

**Vor einer CI-Vorbereitung ohne Run:** Apple Developer Team und App-Store-Connect-Zugang prüfen; die realen IDs `de.mopphie.webkweb` und `de.mopphie.webkweb.favorites` registrieren/bei Bedarf autorisiert anpassen, App Group für beide Targets provisionieren, App in App Store Connect anlegen und die zwei zugehörigen App-Store-Profile erstellen. Distribution-Zertifikat samt **bekanntem** Passwort und API-Key-Rolle/Zugriff bestätigen. Einen ausschließlich manuellen `workflow_dispatch`-Pfad mit Sicherheitsbestätigung, Xcode-26-/iOS-26-Prüfung, lokalen Tests, App-/Widget-Signing und Export schreiben; Secrets nur über GitHub Settings beziehungsweise sicheren lokalen Secret-Upload setzen. **Nicht ausführen** ohne separate ausdrückliche Freigabe für macOS-Actions-Minuten und TestFlight-Upload. Ein erfolgreicher Upload ist erst nach echtem Lauf/Apple-Verarbeitung nachgewiesen.

Privatsphäre-/Support-Seite: <https://mopphie.github.io/webkweb-privacy/>. Ihre GitHub-Pages-Bereitstellung wurde gesondert und ausschließlich für die Website freigegeben; das ist **keine** Freigabe eines TestFlight-Workflows.