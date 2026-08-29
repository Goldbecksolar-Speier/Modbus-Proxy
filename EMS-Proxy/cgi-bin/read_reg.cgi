#!/usr/bin/lua
-- =====================================================================
-- read_reg.cgi - Liest ein EMS-Register ueber den lokalen Proxy
-- (127.0.0.1:1502). Testet damit immer die komplette Kette:
--   Web-UI -> Proxy -> Tesvolt-Batterie
--
-- Aufruf:  /cgi-bin/read_reg.cgi?reg=30001
-- Adress-Konvention:
--   3xxxx -> FC04 (Input Register),  addr = reg - 30001
--   4xxxx -> FC03 (Holding Register), addr = reg - 40001
-- Ausgabe (eine Zeile):
--   OK:<wert>   Wert gelesen (s16)
--   EXC:<code>  Modbus-Exception (10 = Proxy unkonfiguriert, 11 = Ziel down)
--   ERR:<text>  Transportfehler (Proxy nicht erreichbar, Timeout)
-- =====================================================================
local ok_socket, socket = pcall(require, "socket")

print("Content-Type: text/plain")
print("")

if not ok_socket then print("ERR:luasocket fehlt") os.exit(0) end

local qs  = os.getenv("QUERY_STRING") or ""
local reg = tonumber(qs:match("reg=(%d+)"))
if not reg then print("ERR:no reg") os.exit(0) end

local fc, addr
if reg >= 40001 and reg < 50000 then
  fc, addr = 3, reg - 40001
elseif reg >= 30001 and reg < 40000 then
  fc, addr = 4, reg - 30001
else
  fc, addr = 4, reg
end

local function hi(v) return math.floor(v / 256) % 256 end
local function lo(v) return v % 256 end

local c = socket.tcp()
c:settimeout(1.5)
local ok, err = c:connect("127.0.0.1", 1502)
if not ok then print("ERR:proxy " .. tostring(err)) os.exit(0) end

local pdu  = string.char(fc, hi(addr), lo(addr), 0, 1)
local mbap = string.char(0, 1, 0, 0, 0, #pdu + 1, 1)
c:send(mbap .. pdu)

local h = c:receive(7)
if not h then c:close() print("ERR:timeout header") os.exit(0) end
local len  = h:byte(5) * 256 + h:byte(6)
local body = c:receive(len - 1)
c:close()
if not body then print("ERR:timeout body") os.exit(0) end

if body:byte(1) == fc + 0x80 then print("EXC:" .. body:byte(2)) os.exit(0) end
if body:byte(1) ~= fc then print("ERR:bad fc " .. body:byte(1)) os.exit(0) end

local v = body:byte(3) * 256 + body:byte(4)
if v > 32767 then v = v - 65536 end
print("OK:" .. v)
