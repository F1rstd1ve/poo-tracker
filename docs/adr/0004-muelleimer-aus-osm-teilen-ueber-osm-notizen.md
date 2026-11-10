# Mülleimer aus OpenStreetMap, Teilen über OSM-Notizen statt eigenem Server

> **Teilen über OSM-Notizen und Laden über das öffentliche Overpass ersetzt durch [ADR 0006](0006-eigener-gassi-server.md).**


Garmin bietet keine Schnittstelle, um Wegpunkte/POIs zwischen Nutzern zu teilen. Gassi-Depot verwendet deshalb OpenStreetMap als gemeinsamen Datenbestand: Ab Version 1 werden öffentliche Mülleimer und Hundekot-Behälter aus OSM in der Umgebung geladen (über das gekoppelte Handy) und lokal zwischengespeichert; eigene Mülleimer bleiben zunächst nur auf der Uhr. Ab Version 2 können eigene Mülleimer – jeweils nach ausdrücklicher Bestätigung – als OSM-Notiz gemeldet werden, damit Freiwillige sie eintragen.

## Considered Options

- **Eigener Server**: sofortiges Teilen unter App-Nutzern, aber dauerhafte Kosten, Hosting, DSGVO-Pflichten und Missbrauchsschutz. Verworfen zugunsten von OSM (kein Betrieb, Nutzen für alle Karten-Apps), um den Preis einer Verzögerung von Tagen bis Wochen.
