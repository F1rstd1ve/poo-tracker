# Eigener Gassi-Server: schnelle Mülleimer-Kacheln und geteilte Mülleimer

Ersetzt den Teilen-Teil von [ADR 0004](0004-muelleimer-aus-osm-teilen-ueber-osm-notizen.md) (OSM-Notizen) und das direkte Laden vom öffentlichen Overpass-Server innerhalb des Abdeckungsgebiets.

Im Feldtest kamen OSM-Mülleimer nie auf der Uhr an: Die öffentlichen Overpass-Server brauchen selbst für winzige Abfragen 30–45 s oder antworten mit 502/504. Die Uhr bricht dann mit -2 ab (BLE_HOST_TIMEOUT, „Handy hat nicht rechtzeitig geantwortet“). Garmin selbst bietet keinen gemeinsamen Speicher für Connect-IQ-Apps; Daten zwischen Nutzern lassen sich nur über einen eigenen Server teilen.

Deshalb betreibt Gassi-Depot einen eigenen **Gassi-Server** auf Cloudflare (Gratis-Konto):

- **Mülleimer-Kacheln** (Etappe A): Eine GitHub Action bereitet wöchentlich die OSM-Daten für Deutschland, Österreich und die Schweiz auf (Geofabrik-Extrakt, `osmium tags-filter`). Daraus entstehen fertige, kleine Kachel-Dateien (höchstens etwa 10 KB, in der Stadt kleiner, am Land größer), die Cloudflare kostenlos und unbegrenzt ausliefert. Außerhalb dieser drei Länder fällt die Uhr auf den öffentlichen Overpass-Server zurück.
- **Geteilte Mülleimer** (Etappe B): Ein Cloudflare Worker mit D1-Datenbank nimmt angelegte Mülleimer und Meldungen entgegen. Ein neuer Mülleimer ist sofort für alle sichtbar, aber *unbestätigt*; *bestätigt* wird er, wenn ein zweiter Nutzer ihn anlegt oder dort entsorgt. Unbestätigte verschwinden nach 6 Monaten, jeder Mülleimer verschwindet nach 2 Meldungen verschiedener Nutzer. Höchstens 30 neue Mülleimer und 30 Meldungen pro Kennung und Tag.
- **Teilen** braucht eine ausdrückliche Zustimmung beim ersten Start (Garmin-Vorgabe: Standortdaten nur mit Opt-in). Die Uhr verwendet eine zufällige, anonyme Kennung; Beiträge stehen unter CC0. Übertragen werden nur Mülleimer-Positionen, Art, Kennung, Zeit und grobe Kachel-Nummern.
- In OpenStreetMap wird nichts automatisch eingetragen (das wäre ein „Import“ mit Abstimmungspflicht).
- Der Code liegt in einem öffentlichen GitHub-Repository (`server/`, `pipeline/`); Schlüssel und Zugangsdaten nie.

## Considered Options

- **Weiter öffentliches Overpass**: kein Betrieb, aber in der Praxis zu langsam für den Weg über das Handy. Verworfen.
- **Mülleimer-Paket fest in der App**: zuverlässig, aber nur für ein Gebiet und ohne Teilen. Verworfen als bloßer Workaround.
- **OSM-Notizen** (ADR 0004): Andere sehen einen Mülleimer erst, wenn ihn Freiwillige eintragen; viele automatische Notizen sind in der OSM-Gemeinschaft unerwünscht. Verworfen als Hauptweg.
- **Eigener Mietserver** (ca. 5 €/Monat) oder Firebase/Supabase: mehr Wartung bzw. Kosten. Cloudflare liefert statische Dateien gratis und unbegrenzt.

## Consequences

- Datenschutzerklärung (Deutsch/Englisch) und Zustimmungsabfrage sind Pflicht, ebenso „© OpenStreetMap-Mitwirkende“ in App und Store.
- Die Server-Adresse ist in der App fest eingebaut; ein Adresswechsel braucht ein App-Update.
- Wer Konten verwaltet: Cloudflare-Konto, `wrangler login` und das GitHub-Secret richtet der Nutzer ein.
