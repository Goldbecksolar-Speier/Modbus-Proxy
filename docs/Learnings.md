# Learnings (fortlaufend)

## Deployment / PowerShell
- **SCP-Fehler "Das System kann den angegebenen Pfad nicht finden"**: Ursache
  war der Start ueber `cmd /c` / `Start-Process` mit blockierten interaktiven
  Prompts - NICHT fehlende Dateien. Loesung: Key-Auth + non-interactive
  Aufruf (`-o BatchMode=yes`).
- **SSH-Haenger**: Passwort-/Host-Key-/Tailscale-Prompts wurden blockiert.
  Loesung: Key-Auth, `StrictHostKeyChecking=no`, keine interaktiven Prompts.
- **BusyBox-Exitcodes**: liefert teils `True`/`False` statt `0`/`1` ->
  im Wrapper ueber `echo EXITCODE:$?`-Marker abfangen.
- **PowerShell-Parserfehler** (fehlende Quotes/Klammern): Ursache waren
  beschaedigte Dateien (Copy/Paste, falsche Kodierung). Loesung: Datei
  komplett neu generieren und **in ANSI speichern**.

## Architektur
- Der Tesvolt-Marketer-Watchdog (Holding-Register 12/13) erwartet ca. jede
  Minute einen neuen Wert; Timeout nach 5 Minuten -> lokale Steuerung.
- BLUESUN-Sollwerte sind x100 skaliert - Skalierungsfehler erzeugen
  100-fache Leistungssollwerte (sicherheitskritisch, immer clampen).
- Failsafe-Prinzip: Bei BLUESUN-Ausfall automatisch passthrough und
  SetPower_B=0, damit das EMS die Tesvolt-Batterie weiter steuern kann.

## Alte Codestaende (altercode/)
- `modbus_proxy.lua` und `powersplit.lua` waren nur Skeletons.
- `get_param.cgi`, `set_params.cgi`, `set_ips.cgi` waren leer (0 Bytes).
- `index.html`/`index_alt.html` enthielten JS-Fehler (`=` statt `===`,
  unvollstaendige Promise-Ketten) - ersetzt durch neue `status.html`.
- Watchdog nutzte `killall` und hatte keinen Failsafe - ersetzt.
