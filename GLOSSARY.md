# Gassi-Depot

Garmin-Uhren-App, die einen Spaziergang mit Hund aufzeichnet und dabei hilft, unterwegs abgelegte Hundesäcke auf dem Rückweg nicht zu vergessen und sie im nächsten Mülleimer zu entsorgen.

## Sprache

**Spaziergang**:
Die von der App aufgezeichnete Aktivität, vergleichbar mit der Garmin-„Gehen“-Aktivität.
_Vermeiden_: Walk, Aktivität, Tour

**Sackdepot**:
Die gespeicherte Position, an der ein gefüllter Hundesack für den Rückweg abgelegt wurde. Pro Spaziergang kann es beliebig viele geben; ein offenes Sackdepot überdauert das Ende des Spaziergangs.
_Vermeiden_: Wegpunkt, Marker, POI, Ablage

**Mülleimer**:
Ein bekannter Ort, an dem Hundesäcke entsorgt werden können. Entweder ein OSM-Mülleimer oder ein geteilter Mülleimer.
_Vermeiden_: Mistkübel, Abfallbehälter, Tonne

**Geteilter Mülleimer**:
Ein Mülleimer, den ein Nutzer der App angelegt hat. Mit Zustimmung zum Teilen ist er für alle Nutzer sichtbar, sonst nur auf der eigenen Uhr. „Eigen“ heißt nur noch „von mir angelegt“.
_Vermeiden_: Eigener Mülleimer (als eigene Kategorie), Community-Mülleimer

**Unbestätigt / Bestätigt**:
Zustand eines geteilten Mülleimers. Neu angelegt ist er unbestätigt; bestätigt wird er, wenn ein zweiter Nutzer ihn ebenfalls anlegt oder dort entsorgt (gleiche Art, höchstens 8 m, genaues GPS). Unbestätigte verschwinden nach 6 Monaten. Auf der Uhr sind unbestätigte als Ring statt als Punkt dargestellt.

**OSM-Mülleimer**:
Ein Mülleimer aus OpenStreetMap, den die App aus der Umgebung geladen hat.

**Hundekot-Behälter**:
Ein Mülleimer (aus OSM oder geteilt), der ausdrücklich für Hundekot gedacht ist, oft mit Sackerl-Spender. Beim Anlegen wählt man im Aktionsmenü *Mülleimer anlegen* oder *Hundekot-Behälter anlegen*. Wird bei annähernd gleicher Entfernung gegenüber allgemeinen Mülleimern bevorzugt.
_Vermeiden_: Hundestation, Dog-Bin

**Meldung**:
„Hier ist kein Mülleimer“ zu einem OSM- oder geteilten Mülleimer. Auf der eigenen Uhr ist er sofort weg; für alle verschwindet er nach 2 Meldungen verschiedener Nutzer. OpenStreetMap selbst bleibt unverändert.
_Vermeiden_: Ausblenden, Löschen (Löschen gilt nur für eigene, noch unbestätigte Mülleimer)

**Teilen**:
Die einmalige Zustimmung, Mülleimer online zu laden und eigene Mülleimer mit allen zu teilen. Dabei gehen ungefähre Positionen an den Gassi-Server. Ohne Zustimmung gibt es nur Mülleimer auf der eigenen Uhr.

**Kennung**:
Eine zufällige, anonyme Nummer der Uhr, mit der der Gassi-Server Beiträge desselben Nutzers erkennt (Bestätigen, Meldungen, Tagesgrenzen). Entsteht bei der Zustimmung zum Teilen und wird beim Ausschalten vergessen.
_Vermeiden_: Benutzer-ID, Konto, Geräte-ID

**Beitrag**:
Was die Uhr an den Gassi-Server schickt: ein angelegter Mülleimer, eine Meldung, eine Bestätigung durch Entsorgen oder das Löschen eines eigenen unbestätigten Mülleimers. Beiträge warten auf der Uhr, bis das Handy verbunden ist.
_Vermeiden_: Upload, Sync

**Gassi-Server**:
Der eigene Server der App (Cloudflare), der Mülleimer-Kacheln ausliefert und geteilte Mülleimer verwaltet.
_Vermeiden_: Backend, Cloud, Proxy

**Mülleimer-Kachel**:
Ein Datenpaket mit allen OSM-Mülleimern eines Gebiets. In der Stadt klein, am Land groß, damit es schnell übers Handy auf die Uhr kommt.
_Vermeiden_: Tile, Paket

**Aktionsmenü**:
Das Menü, das während eines Spaziergangs durch langes Drücken von MENU (UP-Taste) erreichbar ist und je nach Lage die passende Aktion (Ablegen rückgängig, Aufgehoben, Entsorgt, Mülleimer verwalten) zuoberst anbietet. Ein kurzer Druck auf LAP legt dagegen direkt einen Sack ab (ADR 0005).
_Vermeiden_: Rundenmenü, Lap-Menü

**Rückweg-Alarm**:
Die Warnung, die ausgelöst wird, wenn man sich einem offenen Sackdepot wieder nähert, nachdem man sich davon entfernt hatte.
_Vermeiden_: Erinnerung, Geofence, Benachrichtigung

**Mülleimer-Führung**:
Die Anzeige von Richtung und Luftlinien-Distanz zum nächstgelegenen Mülleimer, ergänzt um Hinweise auf weitere Mülleimer in der näheren Umgebung. Solange ein Sackdepot offen ist, zeigt sie zuerst zum nächsten Sackdepot (rot); der Mülleimer bleibt als Randpunkt sichtbar.
_Vermeiden_: Navigation, Routing

**Datenseite**:
Eine vom Nutzer gestaltete Seite des Spaziergangs, die eine Auswahl von Werten (z. B. Zeit, Distanz, offene Sackdepots) anzeigt.
_Vermeiden_: Datenbildschirm, Screen

**Kartenseite**:
Die Seite des Spaziergangs mit Karte, eigener Strecke, Sackdepots und Mülleimern. Kennt die Modi *Folgen* (Karte läuft mit) und *Erkunden* (Verschieben und Zoomen).
_Vermeiden_: Map, Navigationsseite

**OSM-Notiz**:
Ein Hinweis an die OpenStreetMap-Community, dass an einer Stelle ein Mülleimer steht. Seit ADR 0006 nicht mehr der Weg zum Teilen; höchstens später als Liste für freiwillige Kartierer.
_Vermeiden_: Upload, Sharing, Veröffentlichen

## Zustände eines Sackdepots

**Offen**:
Der Sack liegt noch am Sackdepot.

**Aufgehoben**:
Der Sack wurde vom Sackdepot mitgenommen, ist aber noch nicht entsorgt.

**Entsorgt**:
Der Sack ist in einem Mülleimer gelandet; das Sackdepot ist erledigt.

## Zustände eines Rückweg-Alarms

**Scharf**:
Man hat sich weit genug vom Sackdepot entfernt, sodass eine Wiederannäherung den Alarm auslöst.

**Ausgelöst**:
Man hat sich einem scharfen Sackdepot wieder genähert; die Uhr warnt.
