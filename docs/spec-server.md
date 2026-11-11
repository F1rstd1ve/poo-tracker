# Gassi-Server – Spezifikation (Etappen A und B)

Entscheidung und Begründung: [ADR 0006](adr/0006-eigener-gassi-server.md). Begriffe: [GLOSSARY.md](../GLOSSARY.md).

## Etappen

- **A – Mülleimer-Kacheln** (diese Spezifikation): OSM-Mülleimer für Deutschland, Österreich und die Schweiz als statische Kacheln auf Cloudflare; die Uhr lädt sie statt Overpass; Zustimmung „Teilen“; Datenschutzerklärung.
- **B – Geteilte Mülleimer** (Abschnitt unten): Worker + D1, Anlegen/Bestätigen/Melden, Warteschlange auf der Uhr, Hochladen bestehender eigener Mülleimer.
- **C – Admin-Seite und Store**.

## Kachelformat t1

Erzeugt von `pipeline/build_tiles.py` aus Geofabrik-Extrakten (`osmium tags-filter -R` auf `n/amenity=waste_basket`, `n/vending=excrement_bags`, `n/waste=dog_excrement`).

- **Wurzelraster** 0,4° × 0,4°: `ri = floor((lat + 90) / 0.4)`, `rj = floor((lon + 180) / 0.4)`, Schlüssel `<ri>_<rj>` (Wien-Mitte: `345_490`).
- Jede Wurzel ist ein **Quadtree**: geteilt in SW/SE/NW/NE (Ziffern 0–3), solange mehr als 400 Mülleimer drin sind, höchstens 6 Ebenen (kleinste Kachel 0,00625° ≈ 700 × 470 m).
- `t1/<ri>_<rj>/i.json` – `{"s": "<Preorder>"}`: `1` = geteilt, `0` = Kachel mit Mülleimern, `-` = leer.
- `t1/<ri>_<rj>/<pfad>.json` – `{"d": "<Hundekot-Behälter>", "g": "<Mülleimer>"}`, Pfad aus Ziffern, `r` für eine ungeteilte Wurzel. Jeder Eintrag `dlat,dlon;` in 1e-5° (≈ 1 m) ab der SW-Ecke der Kachel.
- Hundekot-Behälter: `waste` enthält `dog_excrement` oder `vending=excrement_bags`.
- `t1/meta.json` – Datum, Anzahl Mülleimer/Wurzeln/Kacheln, größte Kachel in Byte.
- Wurzeln ohne Mülleimer haben keine Dateien (404): Dort fällt die Uhr auf Overpass zurück.
- Österreich (Nov. 2026): 38.315 Mülleimer, 86 Wurzeln, 280 Kacheln, größte 4,3 KB, Aufbereitung ca. 2 s.

## Uhr (`source/TileLoader.mc`)

- Lädt jede Kachel, die ein Quadrat von ±500 m um die Position berührt, eine Anfrage nach der anderen; erneut erst nach 100 m Bewegung geprüft.
- Index und Kacheln gelten 30 Tage, „nicht abgedeckt“ 7 Tage. Eine 404 auf eine Kachel (Struktur hat sich mit dem Wochen-Update geändert) lädt den Index neu.
- Neue Daten ersetzen alle OSM-Mülleimer im Rechteck der Kachel (`Bins.mergeRect`), höchstens 4000 OSM-Mülleimer auf der Uhr.
- Fehler: Code auf der Mülleimer-Führung, neuer Versuch nach 60 s. Ohne Handy: -104.
- Ohne Zustimmung („Teilen“) wird nichts geladen; die Mülleimer-Führung zeigt „Online-Mülleimer aus“.

## Zustimmung

- Beim ersten Start einmal: *„Mülleimer online laden und eigene teilen? Dabei geht die ungefähre Position an den Gassi-Server.“*
- Änderbar am Startbildschirm mit **MENU halten** → *Online-Mülleimer*; dort auch *Datenschutz* (öffnet die Seite am Handy). In der Connect-App zusätzlich die Einstellung *Online-Mülleimer*.

## Server (`server/`)

- Cloudflare Worker nur mit statischen Dateien (`wrangler.jsonc`, `public/`): `index.html`, `datenschutz.html`, `_headers` (Cache 1 Tag), Kacheln unter `t1/` (nicht im Git).
- `.github/workflows/tiles.yml`: montags 03:17 UTC sowie bei Änderungen an `server/` oder `pipeline/`; lädt die drei Länder-Extrakte, baut die Kacheln, `wrangler deploy`. Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- Adresse: **https://poo-tracker.kjoerg.workers.dev** (Worker `poo-tracker`, Subdomain `kjoerg`), in der App `ServerConfig.BASE`.

## Etappe B – Geteilte Mülleimer

Entschieden im Grilling vom 11.11.2026 (ADR 0006).

### Regeln

- **Gleicher Mülleimer** = gleiche Art (Mülleimer / Hundekot-Behälter) und höchstens **8 m** Abstand. Gilt auf dem Server und auf der Uhr (Duplikat-Frage beim Anlegen).
- **Anlegen:** Neu angelegt ist ein geteilter Mülleimer sofort für alle sichtbar, aber *unbestätigt*. Legt eine **andere** Kennung mit genauem GPS denselben Mülleimer an, wird er *bestätigt* (kein zweiter Eintrag). Ein Beitrag mit ungenauem GPS bestätigt nie, sondern wird ein eigener unbestätigter Eintrag. Dieselbe Kennung erzeugt kein Duplikat (der Server antwortet mit dem vorhandenen Eintrag); ist dieser unbestätigt, mindestens **20 Stunden** alt und das GPS genau, wird er dabei bestätigt (**Selbst bestätigen**).
- **Entsorgt** innerhalb von 8 m eines geteilten Mülleimers bestätigt ihn: den einer anderen Kennung sofort, den eigenen frühestens 20 Stunden nach dem Anlegen. OSM-Mülleimer werden nicht bestätigt.
- **Meldung** („Hier ist kein Mülleimer“): auf der eigenen Uhr sofort weg; für alle weg nach Meldungen von **2 verschiedenen Kennungen**. Gilt für geteilte und OSM-Mülleimer (OSM-Mülleimer werden über Art und Koordinate auf 1e-5° erkannt).
- **Löschen:** eigene, noch unbestätigte Mülleimer (gleiche Kennung).
- **OSM gegen geteilt** (wöchentlicher Kachel-Bau): unbestätigter geteilter Mülleimer mit OSM-Mülleimer gleicher Art ≤ 8 m → der geteilte wird gelöscht. Bestätigter geteilter Mülleimer → der OSM-Mülleimer wird aus den Kacheln entfernt.
- **Grenzen:** höchstens 30 Anlegen und 30 Meldungen (inkl. Bestätigungen/Löschen) pro Tag (UTC) je Kennung **und** je IP-Adresse (IP nur als Hash mit Tages-Salz). Ein Anlegen weiter als 50 km vom ersten Anlegen derselben Kennung am selben Tag wird abgelehnt. Abgelehnte Beiträge bleiben auf der Uhr in der Warteschlange und werden später erneut gesendet.
- **Aufräumen** (täglicher Cron): unbestätigte nach 6 Monaten, Meldungen nach 12 Monaten, Zähler nach 1 Tag.
- Kein App-Schlüssel (das Repository ist öffentlich). Aufräumen von Unsinn über die Admin-Seite (Etappe C).

### API (Worker, `server/src/index.js`)

Basis `https://poo-tracker.kjoerg.workers.dev/api/v1`. Alle Antworten JSON, Koordinaten in Grad (WGS84).

**`POST /api/v1/c`** – Beiträge senden (höchstens 10 Ereignisse pro Anfrage):

```json
{"u": "<Kennung, 32 Hex-Zeichen>", "e": [
  {"t": "a", "k": "g", "la": 48.20821, "lo": 16.37381, "i": 0},
  {"t": "r", "k": "d", "la": 48.20810, "lo": 16.37300, "s": 0},
  {"t": "f", "s": 1234},
  {"t": "x", "s": 1235}
]}
```

- `t`: `a` anlegen, `r` Meldung, `f` bestätigt durch Entsorgen, `x` eigenen unbestätigten löschen.
- `k`: `g` Mülleimer, `d` Hundekot-Behälter. `i`: 1 = ungenaues GPS. `s`: Server-Kennung des geteilten Mülleimers (bei `r` auf einen OSM-Mülleimer: 0).
- Antwort `{"r": [ … ]}`, ein Ergebnis je Ereignis in derselben Reihenfolge:
  - `a`: `{"s": <id>, "f": 0|1}` (`f` = bestätigt; bei Bestätigung eines vorhandenen dessen `id`)
  - `f`: `{"ok": 1, "f": 0|1}` (Zustand danach)
  - sonst `{"ok": 1}`
  - Fehler je Ereignis: `{"err": "limit"}` (später erneut), `{"err": "far"}` (50-km-Regel, später erneut), `{"err": "bad"}` (verwerfen)
- Ganze Anfrage ungültig (kein JSON, Kennung falsch, > 10 Ereignisse): HTTP 400.

**`GET /api/v1/s/<ri>_<rj>`** – geteilte Ebene einer 0,4°-Wurzel (gleiches Raster wie t1):

```json
{"b": "id,k,f,dlat,dlon;…", "h": "k,dlat,dlon;…"}
```

- `b`: alle sichtbaren geteilten Mülleimer (`k` 1 = Mülleimer, 2 = Hundekot-Behälter; `f` 1 = bestätigt), `dlat/dlon` in 1e-5° ab der SW-Ecke der Wurzel.
- `h`: OSM-Mülleimer, die durch 2 Meldungen für alle ausgeblendet sind.
- Leere Wurzel: `{"b": "", "h": ""}` (immer 200). `Cache-Control: public, max-age=3600`; der Worker hält die Antwort 1 Stunde im Cloudflare-Cache.

### Datenbank (D1 `poo-tracker`, `server/migrations/`)

D1-Datenbank `poo-tracker` (Region EEUR), Tabellen über `wrangler d1 migrations apply poo-tracker --remote`; die Action wendet neue Migrationen vor jedem Deployment an.


- `bins(id, lat, lon, kind, confirmed, uid, imprecise, created, confirmed_at)`
- `reports(target, uid, created)` – `target` = `s:<id>` oder `o:<k>:<lat5>:<lon5>`; eindeutig je (`target`, `uid`)
- `hidden_osm(kind, lat5, lon5, root)` – OSM-Mülleimer mit 2 Meldungen
- `counters(day, key, n_add, n_other, anchor_lat, anchor_lon)` – `key` = `u:<Kennung>` oder `ip:<Hash>`

### Uhr

- **Kennung:** 32 Hex-Zeichen zufällig, erzeugt bei der Zustimmung; wird gelöscht, wenn das Teilen ausgeschaltet wird.
- **Warteschlange** (`ShareQueue`): Anlegen, Meldungen, Bestätigungen, Löschen werden gespeichert und gesendet, wenn das Handy verbunden ist und gerade nichts geladen wird – bis zu 10 pro Anfrage, nach Fehlern später erneut (auch beim nächsten Spaziergang). Nach dem Update werden die bisherigen eigenen Mülleimer einmal automatisch eingereiht (nur mit Zustimmung).
- **Geteilte Ebene** (`SharedLoader`): je Wurzel im ±500-m-Quadrat, gültig 1 Stunde; ersetzt die geteilten Mülleimer anderer Nutzer dieser Wurzel. Eigene Mülleimer (mit Server-Kennung) werden nicht doppelt angezeigt, übernehmen aber den Status *bestätigt*.
- **Anzeige:** unbestätigte Mülleimer als Ring statt gefülltem Punkt (Karte und Pfeilseite), auf der Pfeilseite zusätzlich „unbestätigt“.
- **Aktionsmenü:** *Mülleimer anlegen* und *Hundekot-Behälter anlegen*. Steht dort schon ein unbestätigter geteilter Mülleimer derselben Art (≤ 8 m), fragt die Uhr „Ist noch da?“ → *Bestätigen* statt eines Duplikats; beim eigenen erst 20 Stunden nach dem Anlegen, vorher „Schon gespeichert – bestätigen ab morgen“.
- **Startmenü** (MENU halten am Startbildschirm): unter *Online-Mülleimer* „Geteilt: 5 · wartend: 0“.

### Kachel-Bau mit geteilten Mülleimern

Die Action exportiert vor dem Bau `SELECT id,lat,lon,kind,confirmed FROM bins` (`wrangler d1 execute --remote --json`) und übergibt ihn an `build_tiles.py --shared … --delete-sql …`: OSM-Mülleimer ≤ 8 m neben einem bestätigten geteilten gleicher Art fallen aus den Kacheln; unbestätigte geteilte ≤ 8 m neben einem OSM-Mülleimer werden nach dem Deployment gelöscht. Klappt der Export nicht (z. B. Token ohne D1-Recht), werden die Kacheln nur aus OSM gebaut (Warnung im Lauf).

### Test

`server/test/api_test.sh` gegen `wrangler dev --local --var TEST_IP_HEADER:X-Test-IP` (74 Prüfungen); `server/test/self_confirm_test.sh` gegen einen Dev-Server mit zusätzlich `--var SELF_CONFIRM_S:0`. Nie gegen den echten Server ausführen; `TEST_IP_HEADER` nie in Produktion setzen.

## Offen

- Geheimes `IP_SALT` (`wrangler secret put IP_SALT`), sonst ist der Salt für die IP-Hashes öffentlich im Repository.
- Ausgeblendete OSM-Mülleimer (`hidden_osm`) werden nie aufgeräumt.
