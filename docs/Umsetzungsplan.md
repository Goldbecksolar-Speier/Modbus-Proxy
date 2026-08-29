# Umsetzungsplan: Naechster Entwicklungsschritt (Stand 2026-08-29)

## Ziel
Deployment auf den Test-RUTX11 und Verifikation der bisher nur theoretisch
korrekten Annahmen. KEINE realen Anlagenparameter im Repo - Konfiguration
ausschliesslich ueber die Setup-UI.

## Schritt 1: init.d statt systemd (ERLEDIGT in feature/optimierung)
- RUTOS basiert auf OpenWrt -> `EMS-Proxy/etc/init.d/ems_watchdog`
  (rc.common, START=95, STOP=10, PID-basierter Stop statt killall).
- Die alte systemd-Unit `etc/systemd/system/ems_watchdog.service` bleibt
  nur als Referenz und wird NICHT mehr deployed.
- Spaeter optional: Umstellung auf procd (USE_PROCD=1) fuer Respawn.
- Aktivierung: `/etc/init.d/ems_watchdog enable && /etc/init.d/ems_watchdog start`

## Schritt 2: luasocket pruefen (Installer erweitert)
Vor bzw. beim Deployment auf dem Router:
```sh
opkg list-installed | grep -i lua
# falls luasocket fehlt:
opkg update
opkg install luasocket
```
Der Installer `deploy/install_ems_proxy.ps1` prueft dies jetzt automatisch
(Schritt 1b) und installiert luasocket bei Bedarf.

## Schritt 3: Verifikation der Tesvolt-Register (OFFEN - am Geraet)
Ohne diese Verifikation bleibt das System theoretisch korrekt, aber
praktisch unbestaetigt. Am Marketer-Interface pruefen:

| Register (Adresse) | Erwartung laut Spez (Rev. H.01, 03/2025) | Test |
|---|---|---|
| SOC 9/10 (Input) | 32-Bit float, Low-Word zuerst, Einheit % | FC04 lesen, Wert mit EMS-Anzeige vergleichen |
| Power 11/12 | 32-Bit, Word-Order pruefen | FC04 lesen bei bekannter Last |
| Watchdog 12/13 (Holding) | ca. 1x/Minute neuer Wert noetig, Timeout 5 Min -> lokale Steuerung | Schreiben aussetzen und Verhalten beobachten |

Testwerkzeug auf dem Router: `modbus_cli` - dabei auch die tatsaechliche
Syntax verifizieren (`-p 1502`, `-w`/`-v` sind bisher nur ANGENOMMEN).
Ergebnisse als neue Zeilen in `docs/Learnings.md` festhalten.

## Schritt 4: Deployment auf Test-Router
1. `deploy/install_ems_proxy.ps1 -RouterIP <IP>` ausfuehren
   (Aufruf + Ergebnis in `docs/PowerShell-Log.md` dokumentieren).
2. Setup-UI aufrufen: `http://<ROUTER>/setup.html`
   -> IPs Tesvolt/BLUESUN und Kapazitaeten eintragen (NICHT im Repo!).
3. Proxy startet unkonfiguriert im Schutzmodus: alle Anfragen werden mit
   Modbus-Exception 0x0A beantwortet, bis IPs gesetzt sind.

## Schritt 5: Integrationstests
- Passthrough-Modus: EMS-Anfragen 1:1 gegen Tesvolt pruefen.
- Split-Modus mit realen SOC-/Kapazitaetswerten (capacity und soc).
- Failsafe-Test: BLUESUN vom Netz trennen -> nach 3 Fehlern muss
  passthrough + SetPower_B=0 greifen (Log pruefen).
- Watchdog-Register 12/13 aktiv bedienen (noch zu implementieren,
  z.B. im ems_watchdog.sh einmal pro Minute).

## Schritt 6: Doku fortschreiben
- Jede Erkenntnis -> `docs/Learnings.md` (datierte Ledger-Zeile).
- Jeder PowerShell-Aufruf -> `docs/PowerShell-Log.md`.
- `docs/Register-Mapping.md` nach Word-Order-Verifikation korrigieren.
