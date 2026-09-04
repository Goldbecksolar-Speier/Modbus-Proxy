#!/usr/bin/lua
-- =====================================================================
-- test_bluesun.cgi - Dosierte Direkt-Tests am BLUESUN/UDAN-EMS
-- (fuer die Geraete-Testseite test.html; laeuft AM PROXY VORBEI)
--
-- Aktionen (QUERY_STRING):
--   action=status                     liest 0x1500..0x1505 (read-only)
--   action=init&confirm=1             0x1503=1 -> 0x1500=2 -> 0x1505=1
--   action=setpower&confirm=1&kw=X    X>0 Entladen (0x1501=2), X<0 Laden (=1)
--   action=standby                    0x1501=3 + 0x1502=0 (immer erlaubt)
--   action=heartbeat                  Failsafe-Heartbeat der Testseite
--
-- Sicherheit:
--   * Limit |kw| <= /etc/tesvolt_test_max_kw (Default 10)
--   * min. 200 ms Abstand zwischen Modbus-Messages (Herstellervorgabe)
--   * Auto-Standby-Guard: bluesun_test_guard.sh schreibt Standby+0kW,
--     wenn 60 s kein Heartbeat kommt (UDAN-EMS hat KEINEN Watchdog!)
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

local ip    = cfg("/etc/tesvolt_ip_b", "")
local unit  = tonumber(cfg("/etc/tesvolt_unit_b", "10")) or 10
local maxkw = tonumber(cfg("/etc/tesvolt_test_max_kw", "10")) or 10

if ip == "" then print("ERR:BLUESUN-IP nicht gesetzt (Setup-Seite)") os.exit(0) end

local qs      = os.getenv("QUERY_STRING") or ""
local action  = qs:match("action=(%w+)") or ""
local confirm = qs:match("confirm=1") ~= nil

local HB     = "/tmp/bluesun_test_hb"
local ACTIVE = "/tmp/bluesun_test_active"

-- Register (dezimal)
local R_MODE  = 5376  -- 0x1500 ControlMode (2 = Manual)
local R_CAT   = 5377  -- 0x1501 Command Category (1=Laden 2=Entladen 3=Standby)
local R_PWR   = 5378  -- 0x1502 ExpectedPower (0,1 kW, Betrag)
local R_PRIO  = 5379  -- 0x1503 ControlPriority (1=lokal)
local R_START = 5381  -- 0x1505 PCS Start/Stop (1=Start)

local function pause()
  if ok_socket and socket.sleep then socket.sleep(0.25) else os.execute("sleep 1") end
end

local function mb_read(addr)
  local p = io.popen(string.format(
    "/usr/bin/lua /usr/local/bin/mb_cli.lua read %s 502 %d 3 %d", ip, unit, addr))
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

local function heartbeat()
  local f = io.open(HB, "w")
  if f then f:write(tostring(os.time())) f:close() end
end

local function set_active()
  heartbeat()
  local f = io.open(ACTIVE, "w")
  if f then f:write("1") f:close() end
  -- Guard starten, falls er nicht laeuft
  os.execute("pgrep -f bluesun_test_guard >/dev/null 2>&1 || " ..
             "(/usr/local/bin/bluesun_test_guard.sh >/dev/null 2>&1 &)")
end

local function clear_active()
  os.remove(ACTIVE)
end

if action == "status" then
  local regs = { {R_MODE, "0x1500 ControlMode"}, {R_CAT, "0x1501 Category"},
                 {R_PWR, "0x1502 ExpectedPower(0.1kW)"}, {R_PRIO, "0x1503 Priority"},
                 {R_START, "0x1505 PCS Start"} }
  for i, r in ipairs(regs) do
    if i > 1 then pause() end
    print(r[2] .. " = " .. mb_read(r[1]))
  end

elseif action == "init" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  set_active()
  print("0x1503=1 -> " .. mb_write(R_PRIO, 1)); pause()
  print("0x1500=2 -> " .. mb_write(R_MODE, 2)); pause()
  print("0x1505=1 -> " .. mb_write(R_START, 1))
  print("Init-Sequenz gesendet. Failsafe-Guard aktiv (60 s).")

elseif action == "setpower" then
  if not confirm then print("ERR:confirm fehlt") os.exit(0) end
  local kw = tonumber(qs:match("kw=(-?%d+%.?%d*)"))
  if not kw then print("ERR:kw fehlt/ungueltig") os.exit(0) end
  if math.abs(kw) > maxkw then
    print(string.format("ERR:Limit ueberschritten (|%.1f| > %.1f kW aus /etc/tesvolt_test_max_kw)", kw, maxkw))
    os.exit(0)
  end
  local cat = 3
  if kw > 0 then cat = 2 elseif kw < 0 then cat = 1 end
  local val = math.floor(math.abs(kw) * 10 + 0.5)
  set_active()
  print("0x1500=2 -> " .. mb_write(R_MODE, 2)); pause()
  print(string.format("0x1501=%d -> %s", cat, mb_write(R_CAT, cat))); pause()
  print(string.format("0x1502=%d (%.1f kW) -> %s", val, math.abs(kw), mb_write(R_PWR, val)))
  print("Sollwert gesendet. Failsafe-Guard aktiv (60 s ohne Heartbeat -> Standby).")

elseif action == "standby" then
  print("0x1501=3 -> " .. mb_write(R_CAT, 3)); pause()
  print("0x1502=0 -> " .. mb_write(R_PWR, 0))
  clear_active()
  print("Standby gesetzt, Testmodus beendet.")

elseif action == "heartbeat" then
  heartbeat()
  print("OK:heartbeat")

else
  print("ERR:unbekannte action")
end
