# Profil-Loader (Schritt 2 des Geraeteprofil-Konzepts)

> Stand 2026-09-06, Branch site/hebauer. STRIKT READ-ONLY -
> weder profile_loader.lua noch device_poll.lua enthalten eine
> Schreibfunktion; Profile mit write-Block werden abgewiesen.

## Dateien

| Datei | Zweck |
|---|---|
| EMS-Proxy/usr/bin/profile_loader.lua | Modul: Profil laden (dofile), Modbus-TCP-Multiregister-Read, Typ-Decoder (u16/s16/u32be/s32be/f32be), SunSpec Model Scan, sunssf-Anwendung, NOT-IMPLEMENTED-Sentinels, Richtungsregister (Solis) |
| EMS-Proxy/usr/bin/device_poll.lua | CLI/Poller: liest Slots /etc/tesvolt_devN_*, pollt alle Messpunkte des Profils, schreibt /tmp/emsproxy_devN_status |
| EMS-Proxy/profiles/*.lua | Geraeteprofile (Lua-Tabellen, dofile-kompatibel) |
| EMS-Proxy/www/devices.html | Web-UI: Slot-Konfiguration + Live-Status (Port 8080) |
| EMS-Proxy/cgi-bin/read_dev.cgi | Status/Konfig lesen; poll=1 fordert Sofort-Poll an |
| EMS-Proxy/cgi-bin/set_dev.cgi | Slot-Konfig schreiben (gefilterte Eingaben) |
| EMS-Proxy/usr/bin/ems_watchdog.sh | device_poll_tick(): pollt Slots alle 60 s als root |

## Geraeteslots (N = 1..4)

| Datei | Bedeutung | Pflicht |
|---|---|---|
| /etc/tesvolt_devN_profile | Profilname ohne .lua (z.B. solis_s6_hybrid) | ja |
| /etc/tesvolt_devN_ip | Geraete-IP | ja |
| /etc/tesvolt_devN_port | TCP-Port | nein (Profil bzw. 502) |
| /etc/tesvolt_devN_unit | Modbus Unit-ID | nein (Profil-unit_id bzw. 1) |
| /etc/tesvolt_devN_en | 0/1, 0 = Slot deaktiviert | nein (Default 1) |

github_update.sh legt die Slot-Dateien an und setzt uhttpd-Rechte
(WICHTIG: nach diesem Update ZWEIMAL ausfuehren - Selbst-Update-Effekt).

## Web-UI (devices.html)

http://ROUTER-IP:8080/devices.html - pro Slot: Profil (Auswahl oder
frei), IP, Port, Unit, aktiv-Haken, Speichern; darunter Live-Status
(Badge gruen/orange/rot, Messwerte, Fehlerzeilen rot, Alter des Stands).

Ablauf im Hintergrund:

1. Der WATCHDOG (root) pollt alle 60 s alle belegten Slots
   (device_poll_tick, VOR dem enabled-Check -> laeuft auch bei
   gestopptem Proxy, z.B. Standort Hebauer Phase 1).
2. CGIs laufen als User uhttpd und duerfen wegen des Sticky-Bits in
   /tmp keine root-eigenen Statusdateien ersetzen - deshalb liest
   read_dev.cgi nur und fordert Polls per Marker-Datei an:
   /tmp/emsproxy_poll_req -> Watchdog pollt beim naechsten 5-s-Tick.
3. set_dev.cgi setzt zusaetzlich /tmp/emsproxy_devN_cfgchange ->
   Watchdog verwirft Scan-Cache + Status des Slots (sauberer Neustart
   nach Konfigaenderung, wichtig fuer SunSpec-Scan bei IP/Unit-Wechsel).

## Aufruf auf dem Router (manuell, alternativ zur UI)

    lua /usr/local/bin/device_poll.lua        # alle belegten Slots
    lua /usr/local/bin/device_poll.lua 1      # nur Slot 1
    cat /tmp/emsproxy_dev1_status             # Ergebnis ansehen

Ausgabeformat (key=value):

    ts=1789... slot=1 profile=solis_s6_hybrid enabled=1
    bat_soc=57
    err_ac_power=EXC:2        # Fehler je Punkt: EXC:/ERR:/NA:
    points_ok=13 points_err=1

NA: = Punkt vom Geraet nicht implementiert (SunSpec-Sentinel bzw.
SF=0x8000) - kein Kommunikationsfehler.

## Punktdefinitionen im Profil

Absolut (Solis, Janitza):

    bat_soc = { addr = 33139, fc = 4, type = "u16", scale = 1, unit = "%" }

Modell-relativ (Kaco/SunSpec - Adresse aus dem Model Scan):

    ac_power = { model = 103, offset = 14, fc = 3, type = "s16",
                 sf_offset = 15, not_impl = 0x8000 }

Weitere Attribute: sf_addr (absolutes SF-Register), dir_reg +
dir_discharge (Solis-Richtung: Proxy-Konvention >0 = Entladen),
not_impl (Sentinel), scale (feste Skalierung).

## SunSpec-Scan

Profil verlangt Scan via sunspec.scan_required = true (KACO-Vorgabe:
keine festen Absolutadressen!). Ablauf: "SunS" an 40000/0/50000
suchen -> Modellkette lesen bis ID 0xFFFF -> data_start je Modell
cachen (/tmp/emsproxy_devN_scan). Cache loeschen erzwingt Neu-Scan
(z.B. nach Firmware-Update des WR). SF-Register werden pro Lauf
einmal gelesen (Spec: SF ist statisch).

## Verifikationsplan Hebauer (vor Ort)

1. Update einspielen (ZWEIMAL wegen neuer Konfigdateien):
   /usr/local/bin/github_update.sh site/hebauer (2x)
2. Slots konfigurieren - am einfachsten per UI
   (http://ROUTER-IP:8080/devices.html) oder per SSH:
   echo solis_s6_hybrid > /etc/tesvolt_dev1_profile
   echo <IP-S2-WL-ST>   > /etc/tesvolt_dev1_ip
   echo kaco_nx3_sunspec > /etc/tesvolt_dev2_profile
   echo <IP-KACO>        > /etc/tesvolt_dev2_ip
   echo janitza_umg604   > /etc/tesvolt_dev3_profile
   echo <IP-UMG604>      > /etc/tesvolt_dev3_ip
3. UI: "Jetzt pollen" - oder lua /usr/local/bin/device_poll.lua &&
   cat /tmp/emsproxy_dev*_status
4. Solis: SOC plausibel? Sonst Offset-Test 33138 (Solis-Guide zaehlt ab 0).
5. Kaco: scan_base + Modellliste pruefen (erwartet u.a. 1, 103, 160, 701).
6. Janitza: Psum gegen Anzeige am Zaehler vergleichen.
7. Ergebnisse in docs/Learnings.md nachtragen, unverified-Flags entfernen.

## Offen (Schritt 4+)

* Browser-/Geraetetest der UI vor Ort (devices.html bisher nur
  syntaktisch verifiziert: sh -n, node --check, CGI-Funktionstests).
* Nav-Link "Geraete-Slots" auch in status.html und test.html ergaenzen
  (bewusst zurueckgestellt - beide Dateien sind Brand-lastig und
  wuerden bei site/brand-Merges kollidieren).
* Uebernahme nach main + Brand-Profile (tesvolt_bat, bluesun_udan,
  sma_edmm) nach Merge von PR #2 / feature/device-test-ui.
