# Gassi-Depot – Spezifikation Version 1

Ergebnis des Grilling-Interviews (November 2026). Begriffe siehe [GLOSSARY.md](../GLOSSARY.md), Grundsatzentscheidungen siehe [docs/adr](adr/).

## Zielgerät

- Entwicklung und Test: Epix Pro (Gen 2), alle Größen (42/47/51 mm).
- Langfristig: Connect IQ Store, weitere Uhren (Fenix 7/8, Forerunner 255/265/955/965, Venu 3 …).
- Sprachen: Deutsch und Englisch, automatisch nach Systemsprache.

## Spaziergang

- Eigene Connect-IQ-Geräte-App (ADR 0001), zeichnet als Sportart *Gehen* auf und synchronisiert normal mit Garmin Connect.
- Jedes Sackdepot wird als Markierung (FIT-Entwicklerfeld) mitgeschrieben.
- Startbildschirm: GPS-Status + Hinweis auf offene Sackdepots („1 offenes Sackdepot, 340 m entfernt“). Start auch ohne GPS möglich.
- START: Pause → *Fortsetzen / Speichern / Verwerfen*. Bei offenen Sackdepots vor dem Speichern Warnung „1 Sack noch offen – trotzdem beenden?“.
- GPS und Rückweg-Alarm laufen auch in der Pause weiter.
- GPS-Modus: Standard „Alle Systeme + Mehrfrequenz“, umschaltbar auf „Alle Systeme“ oder „Nur GPS“.

## Bedienung

- **LAP (kurz)** legt auf jeder Spaziergang-Seite sofort einen Sack ab (ADR 0005). Sonst bleibt LAP „zurück“: in Menüs, im Erkunden-Modus der Karte, auf dem Alarmbildschirm (blendet ihn aus), am Startbildschirm (App verlassen). Wischen nach rechts legt keinen Sack ab.
- **MENU halten** (lange auf UP) öffnet das kontextabhängige Aktionsmenü, oberster Eintrag vorausgewählt:
  - normal: *Sack ablegen* · *Mülleimer anlegen* · *Hundekot-Behälter anlegen* · *Mülleimer entfernen* · *Offene Sackdepots* · *Karte erkunden*
  - innerhalb 30 s nach dem Ablegen: *Ablegen rückgängig* zuoberst
  - Rückweg-Alarm ausgelöst: *Aufgehoben* zuoberst
  - Sack aufgehoben, nicht entsorgt: *Entsorgt* zuoberst
  - innerhalb 30 s nach automatischem „Entsorgt“: *Entsorgen rückgängig*
- **START** bleibt überall Pause/Stopp. Stopp-Bildschirm wie bei Garmin: System-Menü mit rotem Theme, Zeit als Titel, *Weiter / Speichern / Verwerfen* mit Symbolen (ADR 0007; *Später fortsetzen* ist für Connect-IQ-Apps nicht möglich).
- **Touch** startet, pausiert oder legt nie etwas ab (ADR 0007). Auf der Kartenseite öffnet Tippen *Erkunden*; dort steuert die Garmin-Karte (Verschieben, Zoomen), BACK kehrt zu *Folgen* zurück.
- **UP/DOWN** blättern: Datenseite 1–3 → Mülleimer-Führung → Kartenseite.
- Es gibt keine Runden.

## Sackdepot

- Beliebig viele pro Spaziergang; Zustände offen → aufgehoben → entsorgt.
- Ablegen bestätigt mit kurzer Vibration und „Sackdepot gespeichert“.
- Ohne brauchbares GPS (keine Position oder Genauigkeit > 30 m): „Warte auf GPS…“, längstens 30 s, dann beste verfügbare Position mit Hinweis; für solche Sackdepots gilt ein Auslöseradius von 40 m.
- Offene Sackdepots überdauern das Ende des Spaziergangs und lösen beim nächsten Spaziergang wieder aus.
- *Offene Sackdepots* im Aktionsmenü: Liste mit Distanz und Alter, einzeln löschbar. Kein automatisches Löschen.
- „Brauchbares GPS“ = Garmin-Qualität *usable* oder *good*; nach 30 s wird auch *poor* akzeptiert (→ ungenaues Sackdepot), eine bloß *zuletzt bekannte* Position nie (könnte von einem ganz anderen Ort stammen).
- Aufgehobene, aber nicht als entsorgt markierte Säcke gelten beim Speichern des Spaziergangs als mitgenommen und werden gelöscht.

## Rückweg-Alarm

- Scharf, sobald man ≥ 50 m vom Sackdepot entfernt war; löst aus bei ≤ 25 m (bzw. 40 m bei ungenauem Sackdepot). Beide Radien einstellbar.
- Auslösen: zwei ruhige Vibrationsimpulse + sanfter Drei-Ton-Gong (abschaltbar) + Anzeige wechselt zum Alarmbildschirm. Ohne Bestätigung Wiederholung alle 30 s, höchstens 3 Mal. Entfernt man sich unbestätigt wieder über den Scharf-Radius, wird neu scharf geschaltet.
- Mehrere Sackdepots im Auslöseradius → ein gemeinsamer Alarm („2 Säcke“); *Aufgehoben* gilt für alle ausgelösten.
- Alarmbildschirm führt zuerst mit Pfeil und Distanz zum Sackdepot selbst; nach *Aufgehoben* automatisch zur Mülleimer-Führung.
- Funktioniert nur, während ein Spaziergang in der App läuft.

## Entsorgen

- *Entsorgt* per Aktionsmenü, oder automatisch, wenn man ≥ 3 s innerhalb von 15 m eines Mülleimers nahezu stillsteht; dann kurze Vibration „Entsorgt?“ und 30 s lang rückgängig machbar.
- *Entsorgt* erledigt alle aufgehobenen Sackdepots. Danach Rücksprung zur vorherigen Seite.

## Mülleimer

- **Eigene Mülleimer**: *Mülleimer anlegen* bzw. *Hundekot-Behälter anlegen* speichert die aktuelle Position mit dieser Art, ohne Namen; mit „Teilen“ wird daraus ein geteilter Mülleimer (ADR 0006, docs/spec-server.md). Gibt es in 8 m Umkreis schon einen Mülleimer derselben Art: „Hier gibt es schon einen Mülleimer – trotzdem speichern?“ (Nein vorausgewählt).
- **OSM-Mülleimer**: über das gekoppelte Handy von der öffentlichen Overpass API geladen (ADR 0004), Umkreis 1 km um den Start, Nachladen beim Verlassen des geladenen Gebiets, lokal zwischengespeichert, 30 Tage gültig. Abfrage mit auf ca. 500 m gerundeten Koordinaten. Ohne Verbindung: gespeicherter Stand, dezenter Hinweis.
  - Zählen: allgemeine öffentliche Mülleimer und Hundekot-Behälter; keine großen Container/Müllinseln.
  - Technik: Overpass liefert alle Koordinaten als ein kompakter Text je Art (~22 Byte pro Mülleimer, 1350 Mülleimer = 30 KB). Ist die Antwort für die Uhr zu groß, wird mit 600 m bzw. 400 m Radius neu angefragt. Overpass verlangt einen eigenen User-Agent (sonst HTTP 406). Die öffentlichen Server sind oft überlastet (30–45 s Antwortzeit, 502/504): Nach einem Fehler wird nach 10 s der nächste Server versucht (overpass-api.de, lz4.overpass-api.de, overpass.private.coffee, overpass.kumi.systems), nach einer erfolglosen Runde erst nach 2 Minuten. Der letzte Fehlercode steht auf der Mülleimer-Führung („Mülleimer offline (-300)“). Zusammenführen, Nahbereich und Kartenmarker laufen in getrennten Callbacks (Watchdog).
- *Mülleimer entfernen*: drei nächste Mülleimer mit Distanz und Art; eigene unbestätigte werden gelöscht, alle anderen gemeldet (auf der eigenen Uhr sofort weg, für alle nach 2 Meldungen).

## Seiten

- **Datenseiten** (ADR 0003): bis zu 3, je Layout mit 1–4 Feldern, einzeln ein-/ausschaltbar. Felder: Zeit, Distanz, Tempo, Ø Tempo, Puls, Ø Puls, Höhe, Anstieg, Kalorien, Schritte, Uhrzeit, Offene Sackdepots, Distanz zum nächsten Sackdepot, Distanz zum nächsten Mülleimer.
- **Mülleimer-Führung**: Pfeil (Kompass, ersatzweise GPS-Kurs) und Luftlinien-Distanz zum nächsten Mülleimer, laufend neu berechnet; Hundekot-Behälter werden bei ±20 m bevorzugt. Alle Mülleimer im Umkreis von 100 m als kleine Randmarker. Offene Sackdepots haben Vorrang: jedes als roter Randmarker, und solange eines offen ist, zeigt der große Pfeil rot zum nächsten Sackdepot (Distanz darunter); der Ziel-Mülleimer bleibt als markierter Randpunkt mit Distanz in der untersten Zeile. Abschaltbar.
- **Kartenseite**: Position, eigene Strecke, Sackdepots, Mülleimer und Hundekot-Behälter mit eigenen Symbolen. Modus *Folgen* (feste Zoomstufe ≈ 300 m; *nicht umgesetzt:* „zuletzt gewählte Zoomstufe merken“ – die Garmin-Karten-API liefert die aktuelle Zoomstufe nicht zurück); Antippen oder *Karte erkunden* öffnet die Garmin-Standardsteuerung (*Erkunden*), BACK kehrt zurück. Abschaltbar.

## Einstellungen (Connect-IQ-Handy-App)

Datenseiten 1–3 (Layout, Felder) · Mülleimer-Führung ein/aus · Kartenseite ein/aus · Scharf-Radius (50 m) · Auslöse-Radius (25 m) · Alarmton ein/aus · OSM-Mülleimer laden ein/aus · GPS-Modus. Einheiten folgen den Systemeinstellungen.

## Umsetzungsreihenfolge

1. Entwicklungsumgebung (Connect IQ SDK 9.3, VS Code + Monkey-C-Erweiterung, Entwicklerschlüssel)
2. Karten-Prototyp auf der Epix (Folgen, Erkunden, eigene Symbole)
3. Aufzeichnung (Start, Pause, Speichern, eine feste Datenseite)
4. Sackdepot, Rückweg-Alarm, Aktionsmenü
5. Mülleimer (eigene + OSM) und Mülleimer-Führung
6. Konfigurierbare Datenseiten + Handy-Einstellungen
7. Feinschliff, DE/EN, Praxistest mit Hund

## Version 2 (nicht Teil von V1)

Datenseiten auf der Uhr bearbeiten · eigene Mülleimer als OSM-Notiz teilen · Store-Veröffentlichung für weitere Uhren · ggf. eigener Zwischenserver für OSM-Abfragen.
