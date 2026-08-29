# Learnings (fortlaufendes Ledger)

> Regel: Jede neue Erkenntnis wird hier als datierte Zeile ergaenzt.
> Format: Datum | Kategorie | Learning | Ursache | Loesung/Regel
> Bestehende Zeilen werden nie ueberschrieben, nur ergaenzt.

## Ledger

| Datum | Kategorie | Learning | Ursache | Loesung / Regel |
|---|---|---|---|---|
| 2026-08-29 | PowerShell/SCP | SCP-Fehler "Das System kann den angegebenen Pfad nicht finden" | Start ueber cmd /c bzw. Start-Process mit blockierten interaktiven Prompts - NICHT fehlende Dateien | Key-Auth + non-interactive Aufruf (-o BatchMode=yes) |
| 2026-08-29 | PowerShell/SSH | SSH-Haenger beim Deployment | Passwort-/Host-Key-/Tailscale-Prompts wurden blockiert | Key-Auth, -o StrictHostKeyChecking=no, keine interaktiven Prompts |
| 2026-08-29 | RUTX11/BusyBox | Exitcodes kommen teils als True/False statt 0/1 | BusyBox-Shell-Verhalten | Marker im Wrapper: echo EXITCODE:$? und in PowerShell parsen |
| 2026-08-29 | PowerShell/Encoding | Parserfehler (fehlende Quotes/Klammern) | Beschaedigte Dateien durch Copy/Paste bzw. falsche Kodierung | PS1-Dateien komplett neu generieren und in ANSI speichern (nur ASCII-Zeichen im Code) |
| 2026-08-29 | Tesvolt EMS | Marketer-Watchdog Holding-Register 12/13 erwartet ca. jede Minute neuen Wert | Timeout nach 5 Minuten -> lokale Steuerung | Watchdog-Feeder implementieren (naechster Entwicklungsschritt) |
| 2026-08-29 | BLUESUN | Sollwerte sind x100 skaliert (SetPower_B 0x1144, Limits 0x361D/0x361F) | Skalierungsfehler erzeugen 100-fache Leistungssollwerte | Sicherheitskritisch: immer clampen (powersplit.lua) |
| 2026-08-29 | Architektur | Failsafe-Prinzip bei BLUESUN-Ausfall | 3x Kommunikationsfehler | Automatisch passthrough + SetPower_B=0, EMS steuert Tesvolt weiter |
| 2026-08-29 | Alt-Code | modbus_proxy.lua / powersplit.lua waren nur Skeletons; get_param/set_params/set_ips.cgi leer (0 Bytes) | Unfertiger Stand | Komplett neu implementiert (feature/optimierung) |
| 2026-08-29 | Alt-Code | index.html/index_alt.html mit JS-Fehlern (= statt ===, offene Promise-Ketten) | Handarbeit ohne Review | Ersetzt durch neue status.html/setup.html |
| 2026-08-29 | Alt-Code | Watchdog nutzte killall und hatte keinen Failsafe | Alter Stand | Ersetzt: PID-Kill + Failsafe + Logrotation 500 kB |
| 2026-08-29 | RUTOS | Projektdoku nutzt systemd-Pfade, RUTOS ist aber OpenWrt (procd/init.d) | Doku-Annahme | /etc/init.d/ems_watchdog als procd-Skript erstellen (naechster Schritt) |
| 2026-08-29 | Doku-Prozess | Learnings und alle PowerShell-Aufrufe werden ab sofort strukturiert festgehalten | User-Vorgabe 2026-08-29 | Learnings hier als Ledger; PowerShell-Aufrufe in docs/PowerShell-Log.md |

## Regeln (dauerhaft gueltig)

1. PS1-Dateien immer in ANSI speichern, nur ASCII-Zeichen im Code (keine Umlaute).
2. Alle Skripte nur im GitHub-Projektordner - niemals OneDrive/SharePoint.
3. Doku und Learnings als Markdown in docs/.
4. Keine automatischen Aenderungen an produktiven Systemen; Aenderungen vorher erklaeren.
5. Jeder PowerShell-Aufruf wird in docs/PowerShell-Log.md dokumentiert (Datum, Befehl, Exitcode, Fehler, Korrektur).
