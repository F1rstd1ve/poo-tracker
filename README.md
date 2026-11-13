# Gassi-Depot

Garmin-Connect-IQ-App für Hundespaziergänge: zeichnet den Spaziergang auf, merkt sich abgelegte Hundesäcke, warnt auf dem Rückweg und führt zum nächsten Mülleimer.
Spezifikation: [docs/spec-v1.md](docs/spec-v1.md) · Begriffe: [GLOSSARY.md](GLOSSARY.md) · Entscheidungen: [docs/adr](docs/adr/)

Aktueller Stand: **Version 1 komplett (Schritte 1–7)**, im Simulator getestet. Offen: Praxistest mit Hund auf der Uhr.

## Entwicklungsumgebung einrichten (einmalig, macOS)

1. **Java** (wird vom Monkey-C-Compiler gebraucht) – ohne Admin-Rechte über Homebrew; `scripts/build.sh` findet es automatisch:
   ```bash
   brew install openjdk@17
   ```
   Für VS Code/Simulator zusätzlich in den Einstellungen der Monkey-C-Erweiterung bzw. per `export JAVA_HOME=/opt/homebrew/opt/openjdk@17` bekannt machen.
2. **Connect IQ SDK Manager** von <https://developer.garmin.com/connect-iq/sdk/> herunterladen, installieren, mit deinem Garmin-Konto anmelden, dann:
   - Reiter *SDK*: neuestes SDK (9.3.x) installieren und „Use as current“ wählen.
   - Reiter *Devices*: **Epix Pro (Gen 2)** 42/47/51 mm herunterladen.
3. **VS Code**: Erweiterung *Monkey C* von Garmin installieren (optional, für Editor und Simulator).
4. **Entwicklerschlüssel**: liegt bereits unter `~/.garmin-dev/developer_key.der`. **Sichern!** Store-Updates funktionieren später nur mit demselben Schlüssel.

## Bauen

```bash
scripts/build.sh               # Epix Pro 47 mm (Standard)
scripts/build.sh epix2pro51mm  # andere Größe
```

Ergebnis: `bin/GassiDepot-<gerät>.prg`.

## Im Simulator testen

```bash
open "$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)/bin/ConnectIQ.app"
```

```bash
"$(cat ~/Library/Application\ Support/Garmin/ConnectIQ/current-sdk.cfg)/bin/monkeydo" bin/GassiDepot-epix2pro47mm.prg epix2pro47mm
```

Im Simulator unter *Simulation → Set Position* bzw. *Activity Data* eine GPS-Spur simulieren.

## Auf die Uhr bringen (Sideload)

**Automatisch** (Uhr per USB angesteckt; braucht einmalig `brew install libmtp`):

```bash
scripts/install.sh               # baut für epix2pro51mm und kopiert nach GARMIN/Apps
```

Vorher **Garmin Express komplett beenden** (Menüleisten-Symbol → Beenden), sonst ist die Uhr belegt („Unable to initialize device“). Ebenso OpenMTP/Android File Transfer schließen.

**Von Hand**: OpenMTP öffnen (die Epix ist ein MTP-Gerät und erscheint nicht im Finder) und `bin/GassiDepot-epix2pro<größe>.prg` nach **`GARMIN/Apps`** kopieren.

Danach Uhr abstecken. Die App erscheint in der Aktivitätsliste als *Gassi-Depot* (START → nach unten blättern; sonst über *Liste bearbeiten* hinzufügen).

Eine per Sideload installierte App ist nur auf deiner Uhr, aktualisiert sich nicht automatisch und liefert keine Absturzberichte nach Garmin Connect. Stürzt sie ab, entsteht `GARMIN/APPS/LOGS/CIQ_LOG.YML`; die Datei bitte mit OpenMTP zurückkopieren.

Spätere Alternative: Upload in den Connect IQ Store als **Beta-App** (nur für dich sichtbar), Installation und Updates dann über die Connect-IQ-App am Handy.

## Gassi-Server (Mülleimer-Kacheln und geteilte Mülleimer)

Siehe [docs/spec-server.md](docs/spec-server.md) und [ADR 0006](docs/adr/0006-eigener-gassi-server.md).

Kacheln lokal bauen (braucht `brew install osmium-tool`):

```bash
python3 pipeline/build_tiles.py austria-latest.osm.pbf --out server/public
```

Auf Cloudflare bringt sie die GitHub Action `.github/workflows/tiles.yml` (wöchentlich). Einmalige Einrichtung: Cloudflare-Konto, `npx wrangler login`, GitHub-Repository, Secrets `CLOUDFLARE_API_TOKEN` und `CLOUDFLARE_ACCOUNT_ID`; Adresse: https://poo-tracker.kjoerg.workers.dev (`source/ServerConfig.mc`).

## Bedienung während des Spaziergangs

| Taste | Wirkung |
|---|---|
| START | Pause-Menü (Fortsetzen / Speichern / Verwerfen) |
| LAP (kurz) | Sack ablegen; in Menüs, im Karten-Erkunden und auf dem Alarmbildschirm: zurück |
| MENU halten (lange UP) | Aktionsmenü: Ablegen rückgängig, Aufgehoben/Entsorgt, Mülleimer / Hundekot-Behälter anlegen, Mülleimer entfernen, Offene Sackdepots, Karte erkunden |
| UP / DOWN | Seiten blättern |

## Einstellungen ändern

Am Handy in der **Connect IQ App** → *Meine Geräte* → Epix → *Gassi-Depot* → *Einstellungen* (funktioniert erst, wenn die App über den Store installiert ist; bei Sideload im Simulator unter *File → Edit Persistent Storage* bzw. *Settings*).
Einstellbar: Datenseiten 1–3 (anzeigen, Layout 1–4 Felder, Felder), Mülleimer-Führung/Kartenseite ein/aus, Alarm-Radien (scharf ab / auslösen bei), Alarmton, Online-Mülleimer, Touch an/aus, GPS-Modus. Auf der Uhr: Startbildschirm → MENU halten → *Online-Mülleimer*, *Touch*, *Datenschutz*.

## Testliste Karten-Prototyp (Schritt 2)

- [ ] Karte erscheint, folgt deiner Position, Zoomstufe sinnvoll
- [ ] Drei Testmülleimer (2 grün, 1 blau) rund um den Startpunkt sichtbar
- [ ] Blaue Streckenlinie wächst beim Gehen
- [ ] LAP setzt orangen Sack-Marker
- [ ] Antippen der Karte → Garmin-Verschieben/Zoomen funktioniert (Touch + Tasten)
- [ ] BACK führt zurück zum Folgen; Zoomstufe bleibt/springt? (notieren)
- [ ] Statuszeile oben (GPS/D/ERK) ist über der Karte sichtbar
- [ ] Touch im Folgen-Modus verursacht kein unerwartetes Umschalten

## Testliste Aufzeichnung (Schritt 3)

- [ ] Startbildschirm zeigt GPS-Status (rot → gelb/grün), START startet
- [ ] Datenseite: Zeit läuft, Distanz steigt beim Gehen, Puls, Uhrzeit
- [ ] UP/DOWN wechselt zwischen Datenseite und Karte
- [ ] START → Pause-Menü; BACK im Menü bleibt pausiert (oranger Balken), START setzt fort
- [ ] Speichern → „Spaziergang gespeichert“, App schließt, Aktivität erscheint in Garmin Connect als Gehen
- [ ] Verwerfen → Rückfrage, nichts gespeichert
- [ ] Tippen auf den Bildschirm startet und pausiert **nie** (Startbildschirm, Datenseiten, Alarm)
- [ ] *Touch* aus (Startbildschirm oder im Spaziergang → MENU halten): Touchscreen reagiert in der App nicht mehr, auch nach App-Neustart; nach Verlassen der App wieder normal
- [ ] Stopp-Bildschirm: Garmin-Menü mit rotem Rand, Zeit, Weiter / Speichern / Verwerfen mit Symbolen
- [ ] Karte antippen → Erkunden: Garmin-Steuerung zum Verschieben und Zoomen erscheint; BACK → Folgen

## Testliste Sackdepot & Rückweg-Alarm (Schritt 4)

- [ ] LAP (kurz): sofort Vibration + „Sackdepot gespeichert“, oranger Sack auf der Karte
- [ ] Wischen nach rechts auf einer Datenseite legt **keinen** Sack ab
- [ ] MENU halten → *Ablegen rückgängig* steht 30 s lang oben → Sack wieder weg
- [ ] Ohne GPS: „Warte auf GPS…“ mit 30-s-Countdown, BACK bricht ab
- [ ] ≥ 50 m weggehen, zurückkommen: bei ≤ 25 m Alarm (Vibration, Ton, Alarmbildschirm mit Pfeil + Distanz zum Sack)
- [ ] Pfeil zeigt auch im Stand in die richtige Richtung (Kompass)
- [ ] Ohne Bestätigung: Wiederholung nach 30 s, höchstens 3×
- [ ] LAP auf dem Alarmbildschirm blendet ihn aus (legt keinen Sack ab)
- [ ] MENU halten → *Aufgehoben* steht oben → Alarm weg, Sack verschwindet von der Karte
- [ ] MENU halten → *Entsorgt* steht oben → erledigt
- [ ] Zwei Säcke nah beieinander → ein Alarm „2 Säcke hier!“
- [ ] Spaziergang mit offenem Sack speichern → Warnung „1 Sack noch offen – trotzdem beenden?“
- [ ] Nächster Start: Startbildschirm zeigt „1 offenes Sackdepot · xxx m“; Alarm funktioniert wieder
- [ ] MENU halten → *Offene Sackdepots* → Depot wählen → löschen

## Testliste Mülleimer (Schritt 5)

- [ ] Handy mit Garmin Connect gekoppelt: nach dem Start erscheinen OSM-Mülleimer (grün) und Hundekot-Behälter (blau) auf der Karte; Mülleimer-Seite zeigt *nicht* dauerhaft „Mülleimer offline“
- [ ] Falls doch offline: die Zahl in Klammern notieren (−104 = kein Handy, −300 = Zeitüberschreitung, −402/−403 = Antwort zu groß, 429/502/504 = Server überlastet, −2/−101 = Bluetooth/Warteschlange)
- [ ] UP/DOWN: Datenseite → Mülleimer-Führung → Karte
- [ ] Mülleimer-Führung: Pfeil (Kompass) + Distanz zum nächsten Mülleimer, Randpunkte für alle im Umkreis von 100 m; Hundekot-Behälter bevorzugt, wenn ≤ 20 m weiter
- [ ] Offenes Sackdepot: roter Pfeil + Distanz zum Sack, rote Randpunkte, Mülleimer-Distanz unten
- [ ] Nach *Aufgehoben* springt die Uhr zur Mülleimer-Führung
- [ ] Beim Mülleimer ≥ 3 s stehen bleiben → „Entsorgt? (Menü: rückgängig)“, zurück zur vorherigen Seite; MENU halten → *Entsorgen rückgängig* (30 s)
- [ ] MENU halten → *Mülleimer anlegen* / *Hundekot-Behälter anlegen*; ≤ 8 m neben einem bekannten derselben Art → „Schon ein Mülleimer hier“ mit *Abbrechen* vorausgewählt
- [ ] MENU halten → *Mülleimer entfernen*: 3 nächste; eigener unbestätigter wird gelöscht, alle anderen „gemeldet“ (hier sofort weg)
- [ ] Teilen: Startbildschirm → MENU halten → *Online-Mülleimer* zeigt „Geteilt: n · wartend: m“; mit Handy wird „wartend“ nach kurzer Zeit 0
- [ ] Unbestätigte Mülleimer als Ring (Karte, Pfeilseite „· unbestätigt“); ein zweites Gerät/Konto bestätigt durch Anlegen oder Entsorgen
- [ ] Alarmton ist jetzt ein sanfter Drei-Ton-Gong (statt Garmin-Alarmton)

## Testliste Datenseiten & Feinschliff (Schritte 6–7)

- [ ] Standard: Datenseite 1 (Zeit · Distanz | Puls · Uhrzeit), Datenseite 2 (offene Säcke · zum Sack · zum Mülleimer), dann Mülleimer-Führung, Karte
- [ ] Alle Werte lesbar (Zahlenschrift, Einheit steht in der Beschriftung); Tempo zeigt „--:--“ im Stand
- [ ] Distanzen auf Alarm- und Mülleimer-Seite mit Einheit („18 m“)
- [ ] Neues App-Symbol in der Aktivitätsliste
- [ ] Karte: oben nur noch ein GPS-Punkt statt Debug-Zeile
