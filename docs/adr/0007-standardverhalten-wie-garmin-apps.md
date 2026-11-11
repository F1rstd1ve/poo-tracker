# In Standardbereichen verhält sich Gassi-Depot wie die offiziellen Garmin-Apps

Im Feldtest fiel auf, dass die App an gewohnten Stellen abweicht: Ein Tippen aufs Display pausierte den Spaziergang, auf der Kartenseite fehlten Verschieben und Zoomstufen, und der Stopp-Bildschirm sah anders aus als in der „Gehen“-Aktivität. Grundsatz ab jetzt: Wo es ein Garmin-Standardverhalten gibt, übernimmt Gassi-Depot es; eigene Bedienung gibt es nur für das, was es bei Garmin nicht gibt (Sackdepot, Mülleimer).

- **Touch startet, pausiert oder legt nie etwas ab.** START und ein Tippen kommen bei Connect IQ beide als „select“ an, BACK/LAP und Wischen nach rechts beide als „back“. Die App unterscheidet sie über das rohe Tastenereignis (`KeyGuard`).
- **Kartenseite:** Tippen öffnet *Erkunden* mit der Garmin-eigenen Steuerung (Verschieben, Zoomstufen); dort gehen alle Eingaben außer BACK an die Garmin-Karte. BACK kehrt zu *Folgen* zurück. Einschränkung: Laut Entwicklerforum funktioniert Touch-Verschieben in diesem Kartenmodus auf manchen Uhren nicht zuverlässig.
- **Stopp-Bildschirm** wie in den Garmin-Apps: das System-Menü (`Menu2`) mit dem roten Menü-Theme (`MENU_THEME_RED`, roter Rand), Symbolen und der verstrichenen Zeit als Titel: *Weiter / Speichern / Verwerfen*. Kein selbst gezeichnetes Menü, damit Schrift, Scrollen und Touch genau wie bei Garmin sind.
- **Nicht möglich:** *Später fortsetzen*. Eine Connect-IQ-App kann eine laufende Aufzeichnung nicht über das Verlassen der App hinweg aufheben; Garmin bietet „Resume Later“ nur für eigene Aktivitäten.
