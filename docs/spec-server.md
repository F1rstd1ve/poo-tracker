# Gassi-Server – Spezifikation (Etappe A)

Entscheidung und Begründung: [ADR 0006](adr/0006-eigener-gassi-server.md). Begriffe: [GLOSSARY.md](../GLOSSARY.md).

## Etappen

- **A – Mülleimer-Kacheln** (diese Spezifikation): OSM-Mülleimer für Deutschland, Österreich und die Schweiz als statische Kacheln auf Cloudflare; die Uhr lädt sie statt Overpass; Zustimmung „Teilen“; Datenschutzerklärung.
- **B – Geteilte Mülleimer**: Worker + D1, Anlegen/Bestätigen/Melden, Warteschlange auf der Uhr, Hochladen bestehender eigener Mülleimer.
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

## Offen

- Kontakt (Name, E-Mail) in der Datenschutzerklärung.
- Echter Test über HTTPS: erst nach dem ersten Deployment möglich (Simulator und Uhr verlangen HTTPS; ein lokaler Tunnel wurde nicht verwendet).
