#!/usr/bin/lua
-- =====================================================================
-- mb_cli.lua - Minimaler Modbus-TCP-Client fuer RUTOS (luasocket)
-- Ersetzt das auf RUTOS NICHT vorhandene 'modbus_cli'.
--
-- Aufrufe:
--   lua mb_cli.lua read  <ip> <port> <unit> <fc> <addr>
--   lua mb_cli.lua write <ip> <port> <unit> <addr> <value>
--
-- Ausgabe (eine Zeile):
--   OK:<wert>   Lesen ok (s16) bzw. Schreiben bestaetigt (OK:<value>)
--   EXC:<code>  Modbus-Exception vom Geraet/Proxy (Geraet LEBT!)
--   ERR:<text>  Transportfehler (connect/timeout - Geraet tot)
-- Exitcode immer 0; Auswertung ueber das Praefix.
-- =====================================================================
local ok_socket, socket = pcall(require, "socket")
if not ok_socket then print("ERR:luasocket fehlt") os.exit(0) end

local function hi(v) return math.floor(v / 256) % 256 end
local function lo(v) return v % 256 end

local cmd = arg[1]
local ip, port, unit = arg[2], tonumber(arg[3]), tonumber(arg[4])

local pdu, fc
if cmd == "read" then
  fc = tonumber(arg[5])
  local addr = tonumber(arg[6])
  if not (ip and port and unit and fc and addr) then
    print("ERR:usage read <ip> <port> <unit> <fc> <addr>") os.exit(0)
  end
  pdu = string.char(fc, hi(addr), lo(addr), 0, 1)
elseif cmd == "write" then
  fc = 6
  local addr  = tonumber(arg[5])
  local value = tonumber(arg[6])
  if not (ip and port and unit and addr and value) then
    print("ERR:usage write <ip> <port> <unit> <addr> <value>") os.exit(0)
  end
  if value < 0 then value = value + 65536 end
  pdu = string.char(6, hi(addr), lo(addr), hi(value), lo(value))
else
  print("ERR:unknown cmd") os.exit(0)
end

local c = socket.tcp()
c:settimeout(2)
local ok, err = c:connect(ip, port)
if not ok then print("ERR:connect " .. tostring(err)) os.exit(0) end

local mbap = string.char(0, 1, 0, 0, 0, #pdu + 1, unit)
c:send(mbap .. pdu)

local h = c:receive(7)
if not h then c:close() print("ERR:timeout header") os.exit(0) end
local len  = h:byte(5) * 256 + h:byte(6)
local body = c:receive(len - 1)
c:close()
if not body then print("ERR:timeout body") os.exit(0) end

if body:byte(1) == fc + 0x80 then print("EXC:" .. body:byte(2)) os.exit(0) end
if body:byte(1) ~= fc then print("ERR:bad fc " .. body:byte(1)) os.exit(0) end

if cmd == "write" then
  print("OK:" .. (body:byte(4) * 256 + body:byte(5)))
else
  local v = body:byte(3) * 256 + body:byte(4)
  if v > 32767 then v = v - 65536 end
  print("OK:" .. v)
end
