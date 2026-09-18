#!/usr/bin/lua
-- =====================================================================
-- test_solis.cgi - Dosierter Batterie-Sollwert-Test am Solis S6 Hybrid
-- (fuer die Geraete-Testseite test.html; laeuft AM PROXY VORBEI, reiner
-- Geraetetest, hat nichts mit dem EMS-Proxy/Status-Hauptseite zu tun)
--
-- Solis "Remote Active Power Control" (V0100, Doku S.109-110):
--   44280 (Bitfeld): BIT00-03 Port-Auswahl - 0=aus, 2=AC-Netz-Port,
--          4=Batterie-Port (exklusiv, nur EINE Auswahl gleichzeitig)
--   44282~44283 (S32, 1W): Sollwert Batterieleistung, + = Laden, - = Entladen
--   43282: Timeout in Minuten (Default 5) - Geraet setzt die Port-Auswahl
--          selbst zurueck, wenn nicht regelmaessig neu geschrieben wird
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

local R_PORTSEL = 44280
local R_PWR_HI  = 44282
local R_PWR_LO  = 44283
local R_TIMEOUT = 43282

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
  print("44280 -> " .. mb_read(R_PORTSEL)); pause()
  print("44282 -> " .. mb_read(R_PWR_HI)); pause()
  print("44283 -> " .. mb_read(R_PWR_LO)); pause()
  print("43282 -> " .. mb_read(R_TIMEOUT))

elseif action == "init" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  set_active()
  print("44280=4 -> " .. mb_write(R_PORTSEL, 4))
  print("Init gesendet. Failsafe-Guard aktiv (60 s).")

elseif action == "setpower" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  local kw = tonumber(qs:match("kw=(-?%d+%.?%d*)"))
  if not kw then print("ERR:kw fehlt/ungueltig") os.exit(0) end
  if math.abs(kw) > maxkw then
    print(string.format("ERR:Limit ueberschritten (|%.1f| > %.1f kW)", kw, maxkw))
    os.exit(0)
  end
  local watt = math.floor(kw * 1000 + (kw >= 0 and 0.5 or -0.5))
  local hi, lo = split_s32(watt)
  set_active()
  print("44280=4 -> " .. mb_write(R_PORTSEL, 4)); pause()
  print(string.format("44282=%d -> %s", hi, mb_write(R_PWR_HI, hi))); pause()
  print(string.format("44283=%d (%.2f kW) -> %s", lo, kw, mb_write(R_PWR_LO, lo)))
  print("Sollwert gesendet. Failsafe-Guard aktiv (60 s).")

elseif action == "standby" then
  print("44280=0 -> " .. mb_write(R_PORTSEL, 0))
  clear_active()
  print("Fernsteuerung deaktiviert.")

elseif action == "heartbeat" then
  heartbeat()
  print("OK:heartbeat")

elseif action == "power" then
  -- Tatsaechliche Batterieleistung (33149/33150, FC04) + Richtung
  -- (33135: 0=Laden,1=Entladen) - Betrag ist am Register vorzeichenlos,
  -- Richtung kommt separat (Learning, siehe test.html-Hinweise). Gleiche
  -- Vorzeichenkonvention wie der Regler oben: + = Laden, - = Entladen.
  local rhi = mb_read4(33149):match("OK:(-?%d+)")
  pause_read()
  local rlo = mb_read4(33150):match("OK:(-?%d+)")
  pause_read()
  local rdir = mb_read4(33135):match("OK:(-?%d+)")
  if not (rhi and rlo and rdir) then print("ERR:Lesefehler") os.exit(0) end
  local mag = math.abs(combine_s32(tonumber(rhi), tonumber(rlo)))
  local watt = (tonumber(rdir) == 0) and mag or -mag
  print("OK:" .. watt)

else
  print("ERR:unbekannte action")
end
