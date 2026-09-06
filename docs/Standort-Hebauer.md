# Standort Hebauer (site/hebauer)

> Stand 2026-09-06. Phase 1: Proxy dient als rudimentaeres EMS,
> AUSSCHLIESSLICH LESEND (kein Schreibpfad zu irgendeinem Geraet).

## Geraete

| Geraet | Modell | Anbindung | Profil | Status |
|---|---|---|---|---|
| Hybrid-WR + Batterie | Solis S6 Hybrid 50 kW | Datalogger S2-WL-ST (LAN), Modbus TCP Port 502 | profiles/solis_s6_hybrid.lua | Register aus ESINV-33000ID v3.4; S2-WL-ST unterstuetzt Modbus TCP NATIV (Herstellerangabe) |
| PV-WR | Kaco blueplanet NX3 10 kW | Modbus TCP (SunSpec, Annahme) | profiles/kaco_nx3_sunspec.lua | VORLAEUFIG - Kaco-Doku fehlt, Modellkette am Geraet scannen |
| Netzzaehler | Janitza UMG 604 (ohne Pro) | Modbus TCP Port 502 | profiles/janitza_umg604.lua | Psum 19026 f32be aus Doku; am Geraet verifizieren |

## Datalogger S2-WL-ST (Solis) - Modbus TCP

Quelle: Solis "Modbus TCP Communication Guide for S2-WL-ST Wi-Fi/LAN
Logger" (usservice.solisinverters.com, v1.1 vom 2024-05-29).

* Der S2-WL-ST stellt einen Modbus-TCP-Server bereit:
  **Port 502 (Default)**, Anfragen werden per RS485 an den WR
  durchgereicht.
* **Default-IP bei Direktverbindung: 10.10.100.254**; im LAN holt
  sich der Stick per DHCP eine Adresse. Fuer den Proxy eine
  **statische IP** setzen: SolisCloud-App -> Advanced -> LAN Settings
  (oder ueber die eingebaute Webseite des Loggers).
* ACHTUNG Adress-Offset: Im Solis-Guide beginnt die
  Register-Adressierung bei 0. Beim ersten Test pruefen, ob SOC auf
  **33139 oder 33138** liegt (Offset -1 zur Protokollliste).
* Bis zu 10 Inverter pro Stick (RS485-Kette) - Unit-ID = jeweilige
  Slave-Adresse des WR.
* Timing der RTU-Seite gilt weiter: >= 300 ms zwischen Lese-Frames,
  max. 50 Register/Frame.

## Solis S6 Hybrid - Kernregister (ESINV-33000ID v3.4, FC04)

Protokoll: Modbus RTU 9600 8N1 hinter dem Datalogger; Datentypen
Big-Endian (high word first); >= 300 ms zwischen Lese-Frames,
>= 700 ms bei Steuerframes (Phase 2); max. 50 Register/Frame.

| Register | Bedeutung | Typ | Einheit | Anmerkung |
|---|---|---|---|---|
| 33057-33058 | Total PV Input Power | U32 | 1 W | |
| 33079-33080 | Active Power (Inverter) | S32 | 1 W | |
| 33094 | Grid Frequency | U16 | 0,01 Hz | |
| 33095 | Inverter Current Status | U16 | - | Appendix 3 (M33095), mit 33070 |
| 33133 | Battery 1 Voltage | U16 | 0,1 V | |
| 33134 | Battery 1 Current | S16 | 0,1 A | Betrag; Richtung aus 33135 |
| 33135 | Battery 1 Direction | U16 | - | 0 = Laden, 1 = Entladen |
| 33139 | Battery 1 SOC | U16 | 1 % | |
| 33140 | Battery 1 SOH | U16 | 1 % | |
| 33149-33150 | Battery 1 Real-time Power | S32 | 1 W | Betrag; Richtung aus 33135 |
| 33151-33152 | AC Grid Port Total Active Power | S32 | 1 W | + = aus WR raus |
| 33263-33264 | Meter Total Active Power | S32 | 1 W | + = Einspeisung, - = Netzbezug |
| 33147 | Grid-side Home Load Power | U16 | 1 W | > 65 kW: mit 34343 zu U32 |

Hinweis Mehrgeraete-Summen (falls spaeter mehrere Solis parallel):
34905-34906 Hybrid inverters' Total Battery Power (S32, 1 W,
+ = Laden, 0x80000000 = ungueltig).

## Offene Verifikationspunkte (vor Inbetriebnahme)

1. ~~Datalogger-Typ / TCP-Durchleitung~~ ERLEDIGT 2026-09-06:
   S2-WL-ST unterstuetzt Modbus TCP nativ (Port 502). Noch offen:
   statische IP vergeben und Verbindung am Geraet testen.
2. Register-Offset testen: SOC auf 33139 oder 33138 (Solis-Guide
   adressiert ab 0)? Mit test.html (read-only) klaeren.
3. Solis Slave-Adresse (Default 1?) und Erreichbarkeit ueber den
   Datalogger testen.
4. Kaco NX3: SunSpec-Kennung 'SunS' bei 40000 lesen, Modellkette
   scannen, W/Hz/SF-Adressen bestaetigen, Unit-ID klaeren.
5. Janitza UMG 604: Psum 19026 (f32be) und Word-Order am Geraet
   verifizieren; Unit-ID klaeren.
6. Router fuer Hebauer: eigenes GitHub-Token, Bootstrap nach
   docs/Migration-Neuer-Router.md, Branch site/hebauer.

## Phase 2 (spaeter, NICHT in diesem Stand)

Steuerung der Solis-Batterie ueber 43xxx-Register (FC03/06/10,
>= 700 ms Steuerintervall). Erst nach Phase-1-Verifikation und
separater Freigabe - dann bekommt das Profil einen write-Block
inkl. Failsafe-Konzept.
