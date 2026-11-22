# Geburtstage

Verlässliche Geburtstags-Erinnerungen mit persönlichen Glückwünschen. Android (Samsung), Flutter, Design-System «Nacht, leiser».

## Stand: Phase 1

- Datenmodell (Drift/SQLite): Personen, Notizen, Grüsse
- Kontakt-Import mit Duplikat-Erkennung: gleiche Nummer oder E-Mail = sicher, ähnlicher Name und gleicher Geburtstag = nachfragen
- Screens: Heute, Personen, Person, Bearbeiten, Import, Einstellungen
- Sicherung als JSON-Datei (teilen, z. B. in Google Drive) und Wiederherstellung
- Tests für Geburtstagslogik und Duplikat-Erkennung

Noch nicht: Erinnerungen (Phase 2), KI-Glückwünsche (Phase 3), automatischer SMS-Versand (Phase 4), automatisches Drive-Backup.

## Build

GitHub Actions baut bei jedem Push auf `main`:

1. `flutter create` erzeugt den Android-Ordner, `tool/patch_android.py` setzt Name und Berechtigungen.
2. Drift-Code wird generiert, dann Analyse, Tests und `flutter build apk --release`.
3. Die APK liegt danach unter **Releases › latest** (`geburtstage.apk`).

Die APK ist mit einem festen Schlüssel signiert (Repo-Secret `DEBUG_KEYSTORE_B64`). Darum lassen sich Updates ohne Datenverlust über die alte Version installieren. Den Schlüssel nie löschen: ohne ihn muss die App neu installiert werden.

## Installieren auf dem Samsung

1. Auf dem Handy im Browser das Repo öffnen (angemeldet), **Releases › latest › geburtstage.apk** laden.
2. Datei öffnen. Beim ersten Mal «Installation aus dieser Quelle zulassen» bestätigen.

## Offene Punkte

- Android-Ordner einchecken, sobald Berechtigungen für Phase 2 dazukommen
- Roboto Flex als eingebettete Schrift
