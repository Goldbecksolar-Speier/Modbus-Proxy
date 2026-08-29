# Architektur-Szenarien: Einbindung des Proxys in die Regelschleife

> Stand: 2026-08-29. Grundsatzfrage: Wo verlaeuft die Regelschleife zwischen
> Tesvolt EMS und Tesvolt-Batterie - und wo kann der Proxy eingreifen?
>
> Kernaussage: Eine CAN-Verbindung kann der Proxy NICHT abfangen. Der Proxy
> funktioniert nur an Stellen, an denen Modbus TCP ueber das IP-Netz laeuft.

## Szenario A: Tesvolt-Batterie per Modbus TCP am EMS

```
Tesvolt EMS --Modbus TCP--> [RUTX11-Proxy :1502] --+--> Tesvolt-Batterie (Modbus TCP)
                                                    +--> BLUESUN UDAN-EMS :502 Unit 10
```

- Bisherige Annahme des Projekts.
- Der Proxy sitzt vollstaendig in der Schleife: Das EMS sieht nur den Proxy,
  der Proxy splittet die Sollwerte gewichtet auf beide Batterien.
- Voraussetzung: Die Tesvolt-Batterie hat ein eigenes Modbus-TCP-Interface
  und die Ziel-IP im EMS ist auf den Proxy umkonfigurierbar.

## Szenario B: Tesvolt-Batterie per CAN direkt am EMS

Die Schleife EMS <-> Tesvolt-Batterie ist geschlossen und fuer den Proxy
unsichtbar. Eingriff dort ist nicht moeglich und nicht sinnvoll.
Der Proxy setzt stattdessen EINE EBENE HOEHER an:

```
Vermarkter/Regler --> [Proxy] --+--> Tesvolt EMS (Marketer-Interface, Modbus TCP)
                                 |         +--CAN--> Tesvolt-Batterie (interne Schleife, unberuehrt)
                                 +--> BLUESUN UDAN-EMS :502 Unit 10
```

- Der Proxy agiert gegenueber dem Tesvolt EMS als Vermarkter/uebergeordneter
  Regler ueber das Marketer-Interface (siehe TESVOLT Energy Manager
  MarketerInterfaceModbusSpecifications).
- Gesamt-Sollwert wird im Proxy gesplittet:
  - Tesvolt-Anteil -> Marketer-Register des EMS (EMS setzt intern via CAN um)
  - BLUESUN-Anteil -> direkt an UDAN-EMS
- Wichtig: Marketer-Watchdog (Holding-Register 12/13) muss ca. 1x/Minute
  bedient werden, sonst faellt das EMS nach 5 Minuten auf lokale Steuerung
  zurueck (siehe Learnings-Ledger).
- Auswirkung auf den Code: PowerSplit-Kern (powersplit.lua) bleibt gleich,
  nur das ZIEL des Tesvolt-Anteils aendert sich (Marketer-Register statt
  Batterie-Register).

## Risiko in Szenario B: Regelkampf am Netzanschlusspunkt

Wenn das Tesvolt EMS auf den Netzanschlusszaehler regelt (Closed Loop,
z. B. Nulleinspeisung oder Peak Shaving), sieht es die BLUESUN-Leistung als
Stoerung am Zaehler und regelt dagegen:

1. Proxy -> BLUESUN: entlade 50 kW
2. Netzzaehler zeigt +50 kW Einspeisung
3. Tesvolt EMS kompensiert: laedt eigene Batterie mit 50 kW
4. Netto-Wirkung null, beide Batterien verschleissen Zyklen gegeneinander

Loesungsansaetze:

- Tesvolt EMS im Modus externe Sollwertvorgabe (Marketer-Interface)
  betreiben statt eigener Zaehlerregelung -> nur der Proxy regelt.
- Zaehlerplatzierung so waehlen, dass das EMS den BLUESUN nicht sieht.
- BLUESUN-Leistung als Messwert ans EMS melden (falls Register vorhanden).

## Netzanschlusszaehler: Janitza UMG 604 Pro

- Das Tesvolt EMS bezieht seine Netzleistung ueber einen Janitza UMG 604 Pro.
- Der UMG 604 Pro hat selbst ein Modbus-TCP-Gateway (Standardport 502) und
  RS485; das EMS liest die Netzwerte vermutlich per Modbus vom Zaehler.
- Daraus ergibt sich eine ZUSAETZLICHE Option gegen den Regelkampf:
  Der Proxy koennte auch zwischen Zaehler und EMS gesetzt werden und die
  Zaehlerwerte um die BLUESUN-Leistung korrigieren, so dass das EMS den
  BLUESUN nicht sieht. (Vorsichtig bewerten: Manipulation von Messwerten
  ist funktional maechtig, aber schwer zu debuggen und muss failsafe sein -
  bei Proxy-Ausfall muss das EMS wieder echte Zaehlerwerte sehen.)
- Registerliste/Doku des UMG 604 Pro wird in die Knowledge-Struktur
  aufgenommen (User, 2026-08-29).

## Offene Klaerungspunkte (entscheiden A vs. B)

1. Wie ist die Tesvolt-Batterie real angebunden? (CAN an SIC/EMS oder Modbus TCP)
2. In welchem Regelmodus laeuft das Tesvolt EMS? (Zaehlerregelung vs. externe Vorgabe)
3. Wo sitzt der UMG 604 Pro relativ zum BLUESUN-Anschlusspunkt?
4. Herstellerantwort UDAN-EMS zum Schreibpfad (0x1500ff vs. 0x1530/0x1531).
