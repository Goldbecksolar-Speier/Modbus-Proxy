# Register-Mapping: Tesvolt EMS <-> Proxy <-> BLUESUN

## EMS-Register (Proxy-Sicht)

| EMS-Reg | Tesvolt | BLUESUN (Skalierung) |
|---|---|---|
| 30001 | SOC_T | SOC_B (0x1140) |
| 30003 | Voltage_T | Voltage_B (0x3601 x0.1) |
| 30004 | Current_T | Current_B (0x3602 x0.1) |
| 30005 | Power_T | PCS Power (0x1128 x0.01) |
| 30007 | Status_T | Status_B (0x1100) |
| 30008 | Error_T | Error_B (0x1010) |
| 30020 | Capacity_T | Capacity_B (0x3619 x0.1) |
| 40003 | ChargeLimit_T | ChargeLimit_B (0x361D x100) |
| 40004 | DischargeLimit_T | DchgLimit_B (0x361F x100) |
| 30005 (write) | SetPower_T | SetPower_B (0x1144 x100) + Mode (0x1143) |

## Tesvolt Marketer-Interface (offizielle Spezifikation, Rev. H.01, 03/2025)

SOC ist dort ein 32-Bit-Float ueber zwei Input-Register:

| Adresse | Registry | Typ | Einheit | Datentyp | Zugriff | Beschreibung |
|---|---|---|---|---|---|---|
| 9  | 10 | Input Register | % | float | R | State of Charge (Low-Word) |
| 10 | 11 | Input Register | % | float | R | State of Charge (High-Word) |

Weitere relevante Register:
- 11/12: Lade-/Entladeleistung der Batterie (W, 32-Bit)
- 32-35: Possible Maximum Power Charging/Discharging (W, 32-Bit)
- 36/37: Storage Capacity (Wh, 32-Bit)
- 12/13 (Holding): **Watchdog-Register** - bei aktiver Steuerung ca. jede
  Minute neu beschreiben; nach 5 Minuten ohne neuen Wert uebernimmt die
  lokale Steuerung.
- 100/101: Fehlerregister, Bit 0x0020 = Fehler in der SOC-Aufzeichnung.

Endianness: Standard-Modbus Big-Endian je 16-Bit-Register; bei 32-Bit-Werten
gilt die explizite Low/High-Word-Angabe der Tabelle.

## BLUESUN Registerkonstanten (0-EMS/HMI Modbus485 v1.18)

| Hex | Dezimal | Bedeutung | Skalierung |
|---|---|---|---|
| 0x1140 | 4416 | SOC_B | 1 |
| 0x1143 | 4419 | Mode | - |
| 0x1144 | 4420 | SetPower_B | x100 |
| 0x361D | 13853 | ChargeLimit_B | x100 |
| 0x361F | 13855 | DischargeLimit_B | x100 |
