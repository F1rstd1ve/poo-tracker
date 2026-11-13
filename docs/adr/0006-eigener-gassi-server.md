# Eigener Gassi-Server: schnelle Mülleimer-Kacheln und geteilte Mülleimer

Ersetzt den Teilen-Teil von [ADR 0004](0004-muelleimer-aus-osm-teilen-ueber-osm-notizen.md) (OSM-Notizen) und das direkte Laden vom öffentlichen Overpass-Server innerhalb des Abdeckungsgebiets.

Im Feldtest kamen OSM-Mülleimer nie auf der Uhr an: Die öffentlichen Overpass-Server brauchen selbst für winzige Abfragen 30–45 s oder antworten mit 502/504. Die Uhr bricht dann mit -2 ab (BLE_HOST_TIMEOUT, „Handy hat nicht rechtzeitig geantwortet“). Garmin selbst bietet keinen gemeinsamen Speicher für Connect-IQ-Apps; Daten zwischen Nutzern lassen sich nur über einen eigenen Server teilen.

Deshalb betreibt Gassi-Depot einen eigenen **Gassi-Server** auf Cloudflare (Gratis-Konto):

- **Mülleimer-Kacheln** (Etappe A): Eine GitHub Action bereitet wöchentlich die OSM-Daten für Deutschland, Österreich und die Schweiz auf (Geofabrik-Extrakt, `osmium tags-filter`). Daraus entstehen fertige, kleine Kachel-Dateien (höchstens etwa 10 KB, in der Stadt kleiner, am Land größer), die Cloudflare kostenlos und unbegrenzt ausliefert. Außerhalb dieser drei Länder fällt die Uhr auf den öffentlichen Overpass-Server zurück.
- **Geteilte Mülleimer** (Etappe B): Ein Cloudflare Worker mit D1-Datenbank nimmt angelegte Mülleimer und Meldungen entgegen. Ein neuer Mülleimer ist sofort für alle sichtbar, aber *unbestätigt*; *bestätigt* wird er, wenn ein zweiter Nutzer ihn anlegt oder dort entsorgt. „Derselbe Mülleimer“ heißt gleiche Art und höchstens 8 m Abstand (15 m wären zu grob: echte Mülleimer stehen oft 10–15 m auseinander, und ein Hundekot-Behälter neben einem Mülleimer muss getrennt bleiben); ungenaues GPS bestätigt nie. **Selbst bestätigen** (Nachtrag 11.11.2026): Mit wenigen Nutzern bliebe fast alles unbestätigt und würde nach 6 Monaten gelöscht. Deshalb bestätigt auch derselbe Nutzer seinen Mülleimer, wenn er frühestens 20 Stunden nach dem Anlegen wieder dort ist (Entsorgt dort, oder erneut anlegen → „Ist noch da – bestätigen?“). Wer an verschiedenen Tagen physisch am selben Ort steht, hat ihn wirklich gesehen; das zu fälschen ist viel Aufwand für wenig Wirkung, und Unsinn räumt die Admin-Seite weg. 20 Stunden statt „anderer Kalendertag“, damit 23:50 und 0:10 nicht zählen. Auf der eigenen Uhr erscheinen eigene Mülleimer immer gefüllt (wer ihn angelegt hat, weiß, dass er da ist); „unbestätigt“ ist ein Schutz für die anderen Nutzer. **Vertrauenswürdige Kennungen** (Tabelle `trusted`, von Hand gepflegt, z. B. die Uhr des Entwicklers): deren Mülleimer sind mit genauem GPS sofort für alle bestätigt – sonst blieben gerade die sorgfältig erfassten Mülleimer dort unbestätigt, wo (noch) niemand anderes die App nutzt. Unbestätigte verschwinden nach 6 Monaten, jeder Mülleimer verschwindet nach 2 Meldungen verschiedener Nutzer. Höchstens 30 neue Mülleimer und 30 Meldungen pro Kennung und Tag.
- **Teilen** braucht eine ausdrückliche Zustimmung beim ersten Start (Garmin-Vorgabe: Standortdaten nur mit Opt-in). Die Uhr verwendet eine zufällige, anonyme Kennung; Beiträge stehen unter CC0. Übertragen werden nur Mülleimer-Positionen, Art, Kennung, Zeit und grobe Kachel-Nummern.
- **OSM gegen geteilt:** Steht ein OSM-Mülleimer gleicher Art innerhalb von 8 m, verschwindet ein *unbestätigter* geteilter Mülleimer; ein *bestätigter* geteilter Mülleimer bleibt, und der OSM-Mülleimer wird ausgeblendet – zwei Nutzer haben ihn tatsächlich gesehen.
- Geteilte Mülleimer kommen als eigene, dynamische Ebene je 0,4°-Wurzel vom Worker (1 Stunde Zwischenspeicher), weltweit; die OSM-Kacheln bleiben statisch. Die Uhr sammelt Beiträge in einer Warteschlange und sendet sie gebündelt, sobald das Handy verbunden ist; bisherige eigene Mülleimer werden nach dem Update einmal hochgeladen. Kein App-Schlüssel (öffentliches Repository); Schutz über Tagesgrenzen je Kennung und IP-Adresse und eine 50-km-Regel.
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
