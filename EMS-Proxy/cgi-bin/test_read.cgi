#!/usr/bin/lua
-- =====================================================================
-- test_read.cgi - Generischer READ-ONLY Direkt-Zugriff auf ein Geraet
-- (fuer die Geraete-Testseite test.html; laeuft AM PROXY VORBEI)
--
-- Aufruf: /cgi-bin/test_read.cgi?ip=1.2.3.4&port=502&unit=1&fc=3&addr=9
--   fc: 3 = Holding Register, 4 = Input Register
-- Ausgabe: OK:<wert> | EXC:<code> | ERR:<text>  (wie mb_cli.lua)
-- Bewusst KEIN Schreibzugriff - Tesvolt/SMA werden nur gelesen.
-- =====================================================================
print("Content-Type: text/plain")
print("")

local qs = os.getenv("QUERY_STRING") or ""
local ip   = qs:match("ip=([%d%.]+)")
local port = tonumber(qs:match("port=(%d+)")) or 502
local unit = tonumber(qs:match("unit=(%d+)")) or 1
local fc   = tonumber(qs:match("fc=(%d+)")) or 3
local addr = tonumber(qs:match("addr=(%d+)"))

if not ip or not ip:match("^%d+%.%d+%.%d+%.%d+$") then print("ERR:ip fehlt/ungueltig") os.exit(0) end
if not addr then print("ERR:addr fehlt") os.exit(0) end
if fc ~= 3 and fc ~= 4 then print("ERR:fc nur 3 oder 4") os.exit(0) end
if port < 1 or port > 65535 then print("ERR:port ungueltig") os.exit(0) end
if unit < 0 or unit > 255 then print("ERR:unit ungueltig") os.exit(0) end

local p = io.popen(string.format(
  "/usr/bin/lua /usr/local/bin/mb_cli.lua read %s %d %d %d %d", ip, port, unit, fc, addr))
local r = p:read("*l") or "ERR:no output"
p:close()
print(r)
