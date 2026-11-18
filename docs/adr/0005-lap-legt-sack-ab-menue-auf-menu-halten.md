# LAP legt sofort einen Sack ab, das Aktionsmenü liegt auf „MENU halten“

Ersetzt [ADR 0002](0002-lap-taste-oeffnet-aktionsmenue.md).

Auf Garmin-Uhren ist die rechte untere Taste überall „zurück“. In ADR 0002 öffnete sie während eines Spaziergangs ein Menü. Im Alltag ist das verwirrend: Man drückt LAP, um irgendwo herauszukommen, und landet in einem Menü. Deshalb gilt jetzt:

- **LAP (kurz)** auf einer Spaziergang-Seite legt sofort einen Sack ab, ohne Menü. Das ist die häufigste Aktion, jetzt mit einem Tastendruck.
- **Überall sonst bleibt LAP „zurück“**: in Menüs und Dialogen, im Erkunden-Modus der Karte (zurück zum Folgen), auf dem Alarmbildschirm (Alarm ausblenden) und am Startbildschirm (App verlassen).
- **MENU halten** (lange auf UP) öffnet das Aktionsmenü, wie bei Garmin üblich. Es enthält Mülleimer hinzufügen/entfernen, Aufgehoben/Entsorgt, Offene Sackdepots, Karte erkunden und weiterhin *Sack ablegen*.
- Weil ein einzelner Tastendruck ablegt, steht 30 s lang *Ablegen rückgängig* zuoberst im Aktionsmenü.
- Ein Wischen nach rechts auf dem Touchscreen erzeugt dasselbe „zurück“ wie die Taste. Auf den Spaziergang-Seiten wird es ignoriert, damit ein versehentliches Wischen keinen Sack ablegt. Die App unterscheidet das über das rohe Tastenereignis (`onKeyPressed`). Liefert ein Gerät dieses Ereignis nie, zählt jedes „zurück“ als Taste.

## Nachtrag 18.11.2026: LAP macht das Naheliegende

Im Alltag soll LAP auch Aufheben und Entsorgen erledigen (Wunsch aus dem Feldtest):

- **Rückweg-Alarm ausgelöst** (≥ 50 m weg, wieder ≤ 25 m am Sack, auch auf dem Alarmbildschirm) → *Aufgehoben*. Nicht schon direkt nach dem Ablegen: Macht der Hund 10 m weiter nochmal, legt LAP einen zweiten Sack ab statt den ersten aufzuheben.
- **Sack in der Hand, bekannter Mülleimer ≤ 15 m** → *Entsorgt*.
- **Sack in der Hand, kein Mülleimer bekannt** → Auswahl *Mülleimer hier* / *Hundekot-Behälter hier* (entsorgt und legt den Mülleimer an) / *Neuen Sack ablegen*.
- **sonst** → *Sack ablegen*.

*Entsorgt* über das Aktionsmenü ohne bekannten Mülleimer fragt dasselbe, statt *Neuen Sack ablegen* aber *Kein öffentlicher* (z. B. die Tonne daheim): Es wird nie automatisch ein Mülleimer angelegt, sonst landete die Haustonne öffentlich (und bei der Entwickler-Uhr sofort bestätigt) auf dem Server. Beim Speichern des Spaziergangs gelten getragene Säcke weiterhin still als heimgenommen.

