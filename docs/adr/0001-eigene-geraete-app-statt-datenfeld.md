# Eigene Geräte-App statt Datenfeld in der Garmin-„Gehen“-App

Gassi-Depot ist eine eigenständige Connect-IQ-Geräte-App, die den Spaziergang selbst aufzeichnet (Sportart Gehen, synchronisiert normal nach Garmin Connect), statt als Datenfeld in der nativen Gehen-App zu laufen. Grund: Datenfelder erhalten auf Uhren keine Tasten-Eingaben, das Ablegen eines Sackdepots per Tastendruck wäre so nicht möglich (das undokumentierte `onTap` auf Touch-Uhren ist keine verlässliche Alternative).

## Konsequenzen

- Datenseiten, Pause/Beenden-Ablauf und Aufzeichnung muss die App selbst bereitstellen; die nativen Datenseiten der Uhr stehen nicht automatisch zur Verfügung.
