# Janitza UMG 604-PRO - Modbus-Kernregister (Netzanschlusszaehler)

> Quelle: Janitza "UMG 604-PRO Modbus-address and Formulary" (Firmware rel. 5.030+),
> Doc.no. 1.033.034.h 07/2025. Stand: 2026-08-29.
> Rolle im Projekt: Ueber diesen Zaehler bezieht das Tesvolt EMS seine Netzleistung.

## Protokoll-Eckdaten

- Modbus TCP (Ethernet) und Modbus RTU (RS485) parallel moeglich.
- Als Slave unterstuetzt: FC03 (Read Holding), FC04 (Read Input),
  FC06 (Write Single), FC16 (Write Multiple).
- Datenformat: Big-Endian (High-Byte vor Low-Byte, High-Word vor Low-Word)
  fuer alle Adressen dieser Liste - KEIN Word-Swap noetig.
- Messwerte sind Float32 (2 Register pro Wert, gerade Adressabstaende).
- Vorzeichenkonvention Leistung: + = Bezug (obtaining), - = Lieferung (supply).

## Haeufig benoetigte Messwerte (Block ab 19000, Float32)

| Adresse | Signal | Einheit |
|---|---|---|
| 19000/19002/19004 | Spannung L1-N / L2-N / L3-N | V |
| 19012/19014/19016 | Strom L1 / L2 / L3 | A |
| 19020/19022/19024 | Wirkleistung L1 / L2 / L3 | W |
| **19026** | **Wirkleistung Summe (Psum3 = P1+P2+P3)** | **W** |
| 19034 | Scheinleistung Summe | VA |
| 19042 | Blindleistung Summe (Grundschwingung) | var |
| 19044-19048 | CosPhi L1/L2/L3 | - |
| 19050 | Netzfrequenz | Hz |
| 19052 | Drehfeld (1=rechts, 0=keins, -1=links) | - |
| 19060 | Wirkenergie Summe L1..L3 | Wh |
| 19068 | Wirkenergie Summe, bezogen (consumed) | Wh |
| 19076 | Wirkenergie Summe, geliefert (delivered) | Wh |

Alternativer Block (aeltere Adressen): 1333/1335/1337 Wirkleistung L1/L2/L3 (Float32).

## Relevanz fuer den Proxy (Szenario B, Zaehlerkorrektur-Option)

- Wichtigstes Register fuer das EMS: **19026 (Psum3, Float32, W)** - die
  Summenwirkleistung am Netzanschlusspunkt.
- Falls die Option "Zaehlerwerte um BLUESUN-Leistung korrigieren" umgesetzt
  wird, muesste der Proxy mindestens 19020-19026 konsistent anpassen
  (Phasenwerte + Summe), sonst faellt die Manipulation im EMS auf
  (Summe != Phasensumme).
- OFFEN am Geraet verifizieren: Unit-ID des Zaehlers, ob das Tesvolt EMS per
  TCP oder RS485 abfragt, und welchen Registerblock das EMS tatsaechlich liest
  (19000er vs. 1300er).
