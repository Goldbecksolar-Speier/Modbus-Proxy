# Konzept: Geraeteprofile statt Standort-Branches

> Stand: 2026-09-06. Entscheidung: Da viele Standorte kommen, werden die
> geraetespezifischen Register-Mappings langfristig aus dem Code in
> waehlbare PROFILE ausgelagert. Alle Router fahren dann denselben
> Code-Stand (main); der Standort unterscheidet sich nur durch
> Konfiguration (/etc/tesvolt_*) und gewaehltes Profil.
> Uebergangsweise gelten die Branches site/brand und site/hebauer.

## 1. Ziel

- EIN Code-Stand fuer alle Router (kein Merge-Aufwand pro Standort)
- Neues Geraet = neue Profildatei, KEINE Codeaenderung
- Profile versioniert im Repo (Review + Historie), Auswahl pro Router
  ueber die Setup-UI

## 2. Ablage und Format

Neuer Repo-Ordner `EMS-Proxy/profiles/`, eine Datei pro Geraetetyp.
Format: **Lua-Tabelle** (kein JSON - RUTOS-Lua 5.1 hat keinen
JSON-Parser an Bord, dofile() ist robust und ohne Dependencies):

```lua
-- profiles/bluesun_udan.lua
return {
  id          = "bluesun_udan",
  name        = "BLUESUN 120kW/261kWh (UDAN-EMS)",
  role        = "battery",          -- battery | inverter | meter | ems
  unit_id     = 10,
  min_gap_ms  = 200,                -- Mindestabstand zwischen Requests
  has_watchdog = false,             -- false -> Proxy-Failsafe PFLICHT!

  read = {                          -- Leseregister (Status-UI, Regelung)
    soc   = { addr = 0x1140, fc = 4, type = "u16", scale = 1 },
    -- power = { addr = ..., fc = 4, type = "s32be", scale = 0.01 },
  },

  write = {                         -- optional: Schreibpfad (Sollwerte)
    style = "udan_ctrl_block",      -- Codepfad-Auswahl im Proxy
    init  = {                       -- Init-Sequenz (der Reihe nach)
      { addr = 0x1503, value = 1 }, -- Prio lokal
      { addr = 0x1500, value = 2 }, -- Mode manuell
      { addr = 0x1505, value = 1 }, -- PCS Start
    },
    state_reg = 0x1501,             -- 1=Laden 2=Entladen 3=Standby
    power_reg = 0x1502,             -- Betrag
    power_scale = 0.0001,           -- W -> 0.1 kW
    safe = {                        -- Failsafe-Zustand
      { addr = 0x1501, value = 3 },
      { addr = 0x1502, value = 0 },
    },
  },
}
```

Ein Profil OHNE `write`-Block ist automatisch **read-only** - der Proxy
schreibt an dieses Geraet grundsaetzlich nichts (Anwendungsfall Hebauer
Phase 1).

Datentypen: `u16`, `s16`, `u32be`, `s32be`, `f32be` (Janitza!) -
zentrale Dekodierfunktion im Proxy, Word-Order pro Typ definiert.

## 3. Zuordnung auf dem Router

Pro Geraeteslot eine Konfigdatei (Setup-UI, bestehendes Muster):

| Datei | Inhalt | Beispiel Brand | Beispiel Hebauer |
|---|---|---|---|
| /etc/tesvolt_dev1_profile | Profil-ID | tesvolt_bat | solis_hybrid |
| /etc/tesvolt_dev1_ip | IP | (Setup) | (Setup) |
| /etc/tesvolt_dev1_en | aktiv 0/1 | 1 | 1 |
| /etc/tesvolt_dev2_profile | Profil-ID | bluesun_udan | kaco_wr |
| /etc/tesvolt_dev3_profile | Profil-ID | (leer) | janitza_umg604 |

Die bisherigen festen Slots T/B gehen darin auf (Migration: ip_t/en_t
-> dev1, ip_b/en_b -> dev2). github_update.sh kopiert profiles/ nach
/usr/local/profiles/ und legt die neuen Konfigdateien mit
uhttpd-Rechten an (Rechte-Schleife erweitern, ZWEIMAL laufen lassen!).

## 4. Was im Proxy umgebaut wird

1. `modbus_proxy.lua`: Tabellen BS/EMS ersetzen durch Profil-Loader
   (`dofile("/usr/local/profiles/<id>.lua")`), generische
   read_value(dev, key) / write_setpoint(dev, p_w) ueber die
   Profilfelder; `style`-Feld waehlt den Schreib-Codepfad
   (udan_ctrl_block, spaeter z.B. sunspec, tesvolt_marketer).
2. `powersplit.lua`: bleibt unveraendert (arbeitet nur mit W, en, Limits).
3. `status.html`/`test.html`: Register-Maps nicht mehr hart kodiert,
   sondern per CGI (`get_profile.cgi?id=...`) aus dem Profil geladen -
   Presets/Plausibilitaetsgrenzen kommen mit ins Profil.
4. Failsafe: `has_watchdog=false` erzwingt Safe-State-Verhalten
   (Regel 13) - nicht mehr BLUESUN-spezifisch.
5. Sicherheit: Profile ohne write-Block koennen NIE beschrieben werden,
   auch nicht ueber test.html (CGI prueft das Profil).

## 5. Startbestand an Profilen

| Profil | Rolle | Quelle | Status |
|---|---|---|---|
| tesvolt_bat | battery | bestehendes EMS-Mapping (Reg 9-13 unverifiziert) | aus Code uebernehmen |
| bluesun_udan | battery | EMS/HMI Modbus485 v1.18 + Herstellerfreigabe 2026-09-04 | aus Code uebernehmen |
| sma_edmm | meter/ems | EDMx-Modbus-TI-de-16 (Unit 2, 31249 PCC, 31393/95) | aus status.html uebernehmen |
| janitza_umg604 | meter | janitza-mal/bhb-umg604pro (19026 Psum, f32be) | read-only, Hebauer + Brand |
| solis_hybrid | inverter+battery | Registerliste FEHLT (Modell klaeren!) | Hebauer Phase 1, read-only |
| kaco_wr | inverter | Registerliste FEHLT (Modell klaeren!) | Hebauer Phase 1, read-only |

## 6. Standort Hebauer - Phase 1 (nur lesen)

Geraete: Solis Hybrid-WR (+ Batterie daran), Kaco-WR, Janitza-Zaehler.
Der Proxy dient als rudimentaeres EMS, schreibt aber NICHTS:
- solis_hybrid: PV-Leistung, AC-Leistung, Batterie-SOC/-Leistung lesen
- kaco_wr: AC-Leistung lesen
- janitza_umg604: Netz-Wirkleistung (Psum) lesen
- status.html zeigt alles an; Split-/Schreiblogik bleibt AUS
  (proxy_mode=passthrough ohne Ziel bzw. kuenftig role-basiert)

VOR der Profilerstellung zu klaeren (Andreas):
1. Solis: genaues Modell (z.B. S5-EH1P / S6-Serie) + wie angebunden?
   (RS485 direkt vs. Solis-Datalogger - NICHT jeder Logger-Stick
   spricht Modbus TCP durch!)
2. Kaco: genaues Modell (z.B. blueplanet NX3) - neuere Kaco sprechen
   SunSpec Modbus TCP, dann waere ein generisches sunspec-Profil sinnvoll
3. Janitza: UMG 604 Pro wie bei Brand? (Registerliste liegt als
   Knowledge vor: 19026 Psum, Float32 Big-Endian, Verifikation offen)
4. Wer soll die Solis-Batterie spaeter STEUERN? (Phase 2 - bestimmt,
   ob ein write-Block ins solis_hybrid-Profil kommt)

## 7. Umsetzungsreihenfolge

1. PR #2 + feature/device-test-ui abschliessen/mergen (erst Bestand sichern)
2. Profil-Loader + profiles/ fuer die BESTEHENDEN Geraete (Brand) -
   Verhalten identisch, nur Struktur (Regressionstest ueber test.html)
3. Setup-UI auf Geraeteslots umstellen (Migration ip_t/ip_b automatisch)
4. Registerlisten Solis/Kaco besorgen -> Profile hebauer erstellen
5. site/-Branches stilllegen, alle Router auf main
