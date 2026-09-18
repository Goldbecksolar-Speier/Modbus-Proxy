#!/usr/bin/lua
-- =====================================================================
-- test_solis.cgi - Dosierter Batterie-Sollwert-Test am Solis S6 Hybrid
-- (fuer die Geraete-Testseite test.html; laeuft AM PROXY VORBEI, reiner
-- Geraetetest, hat nichts mit dem EMS-Proxy/Status-Hauptseite zu tun)
--
-- Solis "Remote Dispatch Mode - Real-Time Control" (Doku S.89-91).
-- UMGESTELLT 2026-09-18 (Learning): urspruenglich wurde das "Remote
-- Active Power Control"-Register (44280+) benutzt (Kapitel "Frequency
-- Control Ancillary Service", S.109-110) - Schreibbefehle wurden vom
-- Geraet mit OK bestaetigt, hatten aber KEINE Wirkung. Vermutlicher
-- Grund: Register 44105 ("Control Mode") stand per Default auf 1 =
-- "Battery Standby control (no charging/discharging)" und blockierte
-- damit vermutlich jede Batterieaktion, egal ueber welches Register.
-- Jetzt stattdessen das dafuer vorgesehene, allgemeine Register-Set:
--   44100: Hauptschalter (Remote Dispatch Mode Switch)
--   44101: Failsafe-Intervall in Minuten (Default 5)
--   44105: Control Mode - 1=Battery Standby (Default!), 2=Battery
--          charge/discharge control (das, was wir wollen)
--   44106~44107 (S32, 10W): Sollwert - nur wirksam wenn 44105=2;
--          + = Laden, - = Entladen
--   Nur EIN Sollwert-Registerpaar unabhaengig davon, ob 1 oder 2
--   Batterie-Anschluesse physisch verkabelt sind - bei kombiniertem
--   Anschluss verdoppelt sich nur der zulaessige Wertebereich.
--
-- Aktionen (QUERY_STRING):
--   action=status                  liest die relevanten Register (read-only)
--   action=init&confirm=1          aktiviert die Fernsteuerung
--   action=setpower&confirm=1&kw=X X>0 Laden, X<0 Entladen
--   action=standby                 deaktiviert die Fernsteuerung (immer erlaubt)
--   action=heartbeat               Failsafe-Heartbeat der Testseite
--
-- Sicherheit:
--   * Limit |kw| <= /etc/tesvolt_solis_test_max_kw (Default 10, konservativ)
--   * >= 700 ms Abstand zwischen Schreibbefehlen (Solis-Herstellervorgabe)
--   * Auto-Standby-Guard: solis_test_guard.sh setzt nach 60 s ohne
--     Heartbeat automatisch zurueck (zusaetzlich zum geraeteeigenen
--     5-Minuten-Timeout - unser Guard ist die engere Absicherung)
--   * Schreibaktionen (ausser Standby) nur mit confirm=1
-- =====================================================================
local ok_socket, socket = pcall(require, "socket")

print("Content-Type: text/plain")
print("")

local function cfg(path, def)
  local f = io.open(path, "r")
  if not f then return def end
  local v = f:read("*l")
  f:close()
  if v == nil or v == "" then return def end
  return (v:gsub("%s+$", ""))
end

local ip     = cfg("/etc/tesvolt_ip_ems_s", "")
local unit   = tonumber(cfg("/etc/tesvolt_dev1_unit", "1")) or 1
local maxkw  = tonumber(cfg("/etc/tesvolt_solis_test_max_kw", "10")) or 10

if ip == "" then print("ERR:Solis-IP nicht gesetzt (Setup-Seite: Solis EMS IP)") os.exit(0) end

local qs      = os.getenv("QUERY_STRING") or ""
local action  = qs:match("action=(%w+)") or ""
local confirm = qs:match("confirm=1") ~= nil

local HB     = "/tmp/solis_test_hb"
local ACTIVE = "/tmp/solis_test_active"

local R_DISPATCH = 44100  -- Remote Dispatch Mode Switch (Hauptschalter fuer 44100-44199!)
local R_FAILSAFE = 44101  -- Failsafe-Intervall in Minuten (Default 5)
local R_CTRLMODE = 44105  -- Control Mode: 1=Standby, 2=Battery charge/discharge control
local R_PWR_HI   = 44106  -- Power Setting S32 Hi-Word, Einheit 10 W!
local R_PWR_LO   = 44107  -- Power Setting S32 Lo-Word, Einheit 10 W!

local function pause()
  if ok_socket and socket.sleep then socket.sleep(0.7) else os.execute("sleep 1") end
end

-- Kuerzere Pause fuer reine Lesevorgaenge (Herstellervorgabe: >= 300 ms
-- zwischen Lese-Frames, nur Steuerframes brauchen die 700 ms oben).
local function pause_read()
  if ok_socket and socket.sleep then socket.sleep(0.3) else os.execute("sleep 1") end
end

local function mb_read(addr)
  local p = io.popen(string.format(
    "/usr/bin/lua /usr/local/bin/mb_cli.lua read %s 502 %d 3 %d", ip, unit, addr))
  local r = p:read("*l") or "ERR:no output"
  p:close()
  return r
end

-- Messregister (33xxx) sind FC04 (Input), anders als die Steuerregister
-- oben (43xxx/44xxx = FC03 Holding).
local function mb_read4(addr)
  local p = io.popen(string.format(
    "/usr/bin/lua /usr/local/bin/mb_cli.lua read %s 502 %d 4 %d", ip, unit, addr))
  local r = p:read("*l") or "ERR:no output"
  p:close()
  return r
end

local function mb_write(addr, val)
  local p = io.popen(string.format(
    "/usr/bin/lua /usr/local/bin/mb_cli.lua write %s 502 %d %d %d", ip, unit, addr, val))
  local r = p:read("*l") or "ERR:no output"
  p:close()
  return r
end

local function split_s32(v)
  if v < 0 then v = v + 4294967296 end
  local hi = math.floor(v / 65536) % 65536
  local lo = v % 65536
  return hi, lo
end

-- Kehrfunktion: zwei roh gelesene 16-Bit-Woerter (mb_cli liefert sie
-- bereits als signed s16) zu einem s32-Wert zusammensetzen.
local function combine_s32(hiv, lov)
  if hiv < 0 then hiv = hiv + 65536 end
  if lov < 0 then lov = lov + 65536 end
  local v = hiv * 65536 + lov
  if v > 2147483647 then v = v - 4294967296 end
  return v
end

local function heartbeat()
  local f = io.open(HB, "w")
  if f then f:write(tostring(os.time())) f:close() end
end

local function set_active()
  heartbeat()
  local f = io.open(ACTIVE, "w")
  if f then f:write("1") f:close() end
  os.execute("pgrep -f solis_test_guard >/dev/null 2>&1 || " ..
             "(/usr/local/bin/solis_test_guard.sh >/dev/null 2>&1 &)")
end

local function clear_active()
  os.remove(ACTIVE)
end

if action == "status" then
  print("44100 (Hauptschalter) -> " .. mb_read(R_DISPATCH)); pause()
  print("44101 (Failsafe-Min)  -> " .. mb_read(R_FAILSAFE)); pause()
  print("44105 (Control Mode)  -> " .. mb_read(R_CTRLMODE)); pause()
  print("44106 (Sollwert Hi)   -> " .. mb_read(R_PWR_HI)); pause()
  print("44107 (Sollwert Lo)   -> " .. mb_read(R_PWR_LO))

elseif action == "init" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  set_active()
  print("44100=1 (Hauptschalter) -> " .. mb_write(R_DISPATCH, 1)); pause()
  print("44105=2 (Battery charge/discharge control) -> " .. mb_write(R_CTRLMODE, 2))
  print("Init gesendet. Failsafe-Guard aktiv (60 s).")

elseif action == "setpower" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  local kw = tonumber(qs:match("kw=(-?%d+%.?%d*)"))
  if not kw then print("ERR:kw fehlt/ungueltig") os.exit(0) end
  if math.abs(kw) > maxkw then
    print(string.format("ERR:Limit ueberschritten (|%.1f| > %.1f kW)", kw, maxkw))
    os.exit(0)
  end
  -- 44106/107 sind in 10-W-Schritten (anders als das alte 44282/283-Paar,
  -- das 1-W-Schritte nutzte) - deshalb hier durch 10 teilen statt direkt Watt.
  local units10w = math.floor(kw * 100 + (kw >= 0 and 0.5 or -0.5))
  local hi, lo = split_s32(units10w)
  set_active()
  print("44100=1 -> " .. mb_write(R_DISPATCH, 1)); pause()
  print("44105=2 -> " .. mb_write(R_CTRLMODE, 2)); pause()
  print(string.format("44106=%d -> %s", hi, mb_write(R_PWR_HI, hi))); pause()
  print(string.format("44107=%d (%.2f kW) -> %s", lo, kw, mb_write(R_PWR_LO, lo)))
  print("Sollwert gesendet. Failsafe-Guard aktiv (60 s).")

elseif action == "standby" then
  -- 44100 bewusst NICHT zuruecksetzen: das ist laut Doku der gemeinsame
  -- Hauptschalter fuer den GESAMTEN Bereich 44100-44199 - dort liegt auch
  -- das Netzbezug-Limit-Feature (44100-44104). Faellt dieses Standby, waere
  -- sonst potenziell auch ein parallel aktives Netzbezug-Limit betroffen.
  print("44105=1 (Battery Standby) -> " .. mb_write(R_CTRLMODE, 1))
  clear_active()
  print("Fernsteuerung deaktiviert (44100 bewusst unveraendert gelassen, siehe Kommentar).")

elseif action == "heartbeat" then
  -- WICHTIG: anders als beim BLUESUN/UDAN-EMS (kein eigener Timeout) hat
  -- der Solis einen geraeteseitigen Failsafe-Timeout (Register 44101,
  -- Default 5 Minuten) - der Heartbeat muss deshalb den Control Mode aktiv
  -- am Geraet auffrischen, nicht nur lokal eine Zeitstempel-Datei setzen.
  -- Sonst faellt die Fernsteuerung nach 5 Minuten von selbst zurueck,
  -- waehrend der Sollwert im Register stehen bleibt (Learning 2026-09-18).
  heartbeat()
  if io.open(ACTIVE, "r") then
    print("Refresh 44100 -> " .. mb_write(R_DISPATCH, 1)); pause()
    print("Refresh 44105 -> " .. mb_write(R_CTRLMODE, 2))
  else
    print("OK:heartbeat (inaktiv, kein Refresh)")
  end

elseif action == "getsetpoint" then
  -- Liefert den tatsaechlich am Geraet konfigurierten Sollwert (44106/107)
  -- als einfachen OK:<Watt>-Wert, damit die Seite beim (Neu-)Laden den
  -- echten Zustand anzeigen kann statt immer beim HTML-Default 0 zu starten.
  -- Ohne diesen Abgleich zeigt jeder neue/neu geladene Browser-Tab 0.0 kW,
  -- obwohl am Geraet ein anderer Sollwert aktiv ist - eine Beruehrung des
  -- Reglers in diesem Tab wuerde den echten Sollwert dann unbemerkt
  -- ueberschreiben (Nutzer-Beobachtung 2026-09-18: "wenig, was ich erhoehe"
  -- bei mehreren offenen Browser-Tabs auf derselben Seite).
  local hi_s = mb_read(R_PWR_HI); pause_read()
  local lo_s = mb_read(R_PWR_LO)
  local hi, lo = tonumber(hi_s), tonumber(lo_s)
  if not hi or not lo then print("ERR:Lesefehler (" .. hi_s .. "/" .. lo_s .. ")") os.exit(0) end
  print("OK:" .. (combine_s32(hi, lo) * 10))

elseif action == "power" then
  -- Tatsaechliche Batterieleistung (33149/33150, FC04) + Richtung
  -- (33135: 0=Laden,1=Entladen) - Betrag ist am Register vorzeichenlos,
  -- Richtung kommt separat (Learning, siehe test.html-Hinweise). Gleiche
  -- Vorzeichenkonvention wie der Regler oben: + = Laden, - = Entladen.
  --
  -- EIN Blockread (33135..33150, 16 Register) statt drei Einzelreads ueber
  -- mb_cli.lua: jeder mb_cli-Aufruf oeffnet eine eigene TCP-Verbindung
  -- (kein Pooling) - drei Aufrufe alle 5s haben den Datenlogger nachweislich
  -- ueberlastet (Learning 2026-09-18: >50 TIME_WAIT-Verbindungen, Solis
  -- reagierte traege, SolisCloud-App gestoert). profile_loader.lua liest
  -- den ganzen Bereich in EINER Verbindung (dieselbe Bibliothek, die auch
  -- device_poll.lua benutzt).
  local L = dofile("/usr/local/bin/profile_loader.lua")
  local words, err = L.read_regs_retry(ip, 502, unit, 4, 33135, 16, 3, 2, 0.3)
  if not words then print("ERR:" .. tostring(err)) os.exit(0) end
  local dir = words[1]                      -- 33135
  local hi, lo = words[15], words[16]        -- 33149, 33150 (Offset 14,15)
  if hi > 32767 then hi = hi - 65536 end
  if lo > 32767 then lo = lo - 65536 end
  local mag = math.abs(combine_s32(hi, lo))
  local watt = (dir == 0) and mag or -mag
  print("OK:" .. watt)

else
  print("ERR:unbekannte action")
end
