# PowerShell-/Deployment-Log (fortlaufendes Ledger)

> Regel: Jeder Deployment-Aufruf (PowerShell oder SSH direkt auf dem Router)
> wird hier als datierte Zeile dokumentiert - inklusive Fehlern und der
> Korrektur, mit der es schliesslich funktioniert hat. Zeilen werden nie
> ueberschrieben.
>
> Format: Datum/Zeit (UTC) | Skript/Befehl | Ziel | Ergebnis (OK/FEHLER + Exitcode) | Fehlermeldung (Kurzform) | Korrektur

## Ledger

| Datum/Zeit (UTC) | Skript / Befehl | Ziel | Ergebnis | Fehlermeldung | Korrektur |
|---|---|---|---|---|---|
| 2026-08-29 (vor Optimierung) | scp ... (Alt-Deployment, via cmd /c) | RUTX11 | FEHLER | "Das System kann den angegebenen Pfad nicht finden" | Key-Auth + BatchMode=yes, direkter scp-Aufruf statt cmd /c (siehe Learnings) |
| 2026-08-29 | deploy/install_ems_proxy.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erst nach Bedarf; Self-Update via github_update.sh ist der Hauptweg |
| 2026-08-29 | deploy/update_rutx11.ps1 (neu erstellt) | RUTX11 | NOCH NICHT AUSGEFUEHRT | - | Erst nach Erstinstallation nutzen |
| 2026-08-29 13:49 | Bootstrap-Einzeiler (wget, 2x --header) | RUTX11 (SSH) | FEHLER | wget: unrecognized option | BusyBox-wget kann keine Header -> curl nutzen |
| 2026-08-29 13:53 | Bootstrap-Einzeiler (curl -> /usr/bin) | RUTX11 (SSH) | FEHLER | curl: (23) client returned ERROR on write of 88 bytes | / ist squashfs read-only -> Ziel /usr/local/bin (Commits 875625d, f995952) |
| 2026-08-29 13:59 | Bootstrap-Einzeiler (curl -> /usr/local/bin) + github_update.sh feature/optimierung | RUTX11 (SSH) | OK | Hinweis "Skipping invalid Lua prefix" beim uhttpd-Restart (unkritisch, stammt von der uci/uhttpd-Konfigpruefung) | ERSTES ERFOLGREICHES DEPLOYMENT: Token-Auth ok, uhttpd-Instanz Port 8080 angelegt, Watchdog gestartet (PID 17078) |

## Konventionen fuer Eintraege

- Ergebnis: OK (EXITCODE:0) oder FEHLER (EXITCODE:n bzw. Marker aus BusyBox).
- Bei Fehlern: Fehlermeldung in Kurzform, vollstaendige Ausgabe bei Bedarf als
  Datei unter docs/logs/ ablegen.
- Nach jeder Korrektur-Iteration eine neue Zeile - so bleibt die komplette
  Fehlersuche nachvollziehbar.
