# BLUESUN / UDAN-EMS Steuerblock 0x1500 (Herstellerfreigabe 2026-09-04)

> Quelle: Herstellerantwort BLUESUN/UDAN vom 2026-09-04 auf die Anfrage
> vom 2026-08-29 + Registerliste "EMS/HMI Communication Modbus485 v1.18".
> Verbindungsdaten (IP/Port/Unit-ID) stehen NICHT im Repo (Regel 6) -
> Konfiguration ueber Setup-UI bzw. /etc/tesvolt_ip_b und /etc/tesvolt_unit_b.

## Freigegebener Schreibpfad: Variante A (Steuerblock 0x1500)

| Register | Name | Werte | Bemerkung |
|---|---|---|---|
| 0x1500 | ControlMode | 1=Automatik, 2=manuell | Bei Automatik werden 0x1501/0x1502 NICHT angenommen; bei manuell MUESSEN beide geschrieben werden |
| 0x1501 | SystemState | 1=Laden, 2=Entladen, 3=Standby | Richtung; Standby = Lade-/Entladeleistung 0 |
| 0x1502 | ExpectedPower | Betrag in 0,1 kW (u16) | nur positiver Betrag, Richtung ueber 0x1501 |
| 0x1503 | ControlPriority | 1=lokal, 2=remote | lokal: EMS ignoriert Cloud-Plattform; remote: EMS ignoriert lokale Befehle |
| 0x1504 | Netz/Off-Grid | 1=Netzparallel, 2=Insel | NICHT anfassen |
| 0x1505 | PCS Start/Stop | 1=Start, 2=Stop | einmalig beim Aktivieren der Regelung |
| 0x1507 | Blindleistung | 0,1 kVar | optional, ungenutzt |

Variante B (0x1530/0x1531, PCS-direkt) wird NICHT verwendet (nicht freigegeben).

## Herstellervorgaben

- Paralleler Modbus-TCP-Master neben dem HMI: ERLAUBT.
- Min. **200 ms Abstand zwischen Requests** (im Proxy erzwungen: bs_throttle).
- **KEIN Watchdog/Timeout im UDAN-EMS** ("No timeout setting"): bei
  Kommunikationsverlust bleibt der letzte Sollwert dauerhaft aktiv.
  => Failsafe MUSS clientseitig erfolgen (Proxy + Watchdog).
- Ruecksprung Automatik: erst Standby + 0 kW schreiben (0x1501=3,
  0x1502=0), dann 0x1500=1.

## Sequenzen (Implementierung modbus_proxy.lua)

### Init (einmalig beim Aktivieren des Split-Modus)

1. 0x1503 = 1 (lokale Prioritaet)
2. 0x1500 = 2 (manueller Modus)
3. 0x1505 = 1 (PCS Start)

### Sollwert schreiben (write_bluesun_setpoint, p in W)

1. Richtung: p > 0 -> 0x1501 = 2 (Entladen); p < 0 -> 0x1501 = 1 (Laden);
   |p| < 50 W (deci = 0) -> 0x1501 = 3 (Standby)
2. Betrag: 0x1502 = round(|p| / 100)  (W -> 0,1 kW)
3. Unveraenderte Werte werden nur alle 5 s erneut geschrieben (Keepalive),
   Aenderungen sofort. Zwischen allen Requests min. 200 ms.

### Failsafe (Safe-State = Standby + 0 kW)

Ausgeloest durch:
- Proxy: kein EMS-Sollwert seit > 10 s (ems_timeout_s)
- Proxy/Watchdog: BLUESUN 3x nicht erreichbar -> zusaetzlich passthrough

Schreibfolge: 0x1501 = 3, dann 0x1502 = 0.
Dezimal fuer mb_cli.lua: 0x1501 = 5377, 0x1502 = 5378, 0x1500 = 5376.

## Offene Punkte / Verifikation am Geraet

- [ ] Init-Sequenz am Geraet testen (nimmt das EMS 0x1503=1 an?)
- [ ] Verhalten bei 0x1505=1, wenn PCS bereits laeuft (idempotent?)
- [ ] Standby-Test: 0x1501=3 -> geht PCS-Leistung wirklich auf 0?
- [ ] Skalierung 0x1502 mit kleinem Wert verifizieren (z.B. 50 = 5,0 kW)
- [ ] Word-Order/Byte-Order bei Leseregistern (0x1140 SOC) pruefen
