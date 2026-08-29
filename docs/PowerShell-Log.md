# PowerShell-Log (fortlaufendes Ledger)

> Regel: Jeder PowerShell-Aufruf (Deployment, Test, Reparatur) wird hier als
> datierte Zeile dokumentiert - inklusive Fehlern und der Korrektur, mit der
> es schliesslich funktioniert hat. Zeilen werden nie ueberschrieben.
>
> Format: Datum/Zeit (UTC) | Skript/Befehl | Ziel | Ergebnis (OK/FEHLER + Exitcode) | Fehlermeldung (Kurzform) | Korrektur

## Ledger

| Datum/Zeit (UTC) | Skript / Befehl | Ziel | Ergebnis | Fehlermeldung | Korrektur |
|---|---|---|---|---|---|
| 2026-08-29 (vor Optimierung) | scp ... (Alt-Deployment, via cmd /c) | RUTX11 | FEHLER | "Das System kann den angegebenen Pfad nicht finden" | Key-Auth + BatchMode=yes, direkter scp-Aufruf statt cmd /c (siehe Learnings) |
| 2026-08-29 | deploy/install_ems_proxy.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erster Testlauf steht aus (naechster Entwicklungsschritt) |
| 2026-08-29 | deploy/update_rutx11.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erst nach Erstinstallation nutzen |

## Konventionen fuer Eintraege

- Ergebnis: OK (EXITCODE:0) oder FEHLER (EXITCODE:n bzw. Marker aus BusyBox).
- Bei Fehlern: Fehlermeldung in Kurzform, vollstaendige Ausgabe bei Bedarf als
  Datei unter docs/logs/ ablegen.
- Nach jeder Korrektur-Iteration eine neue Zeile - so bleibt die komplette
  Fehlersuche nachvollziehbar.
