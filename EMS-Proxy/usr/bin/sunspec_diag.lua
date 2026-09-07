-- =====================================================================
-- sunspec_diag.lua - SunSpec-Diagnose (READ-ONLY)
--
-- Aufruf: lua /usr/local/bin/sunspec_diag.lua <ip> [port] [unit]
-- Beispiel: lua /usr/local/bin/sunspec_diag.lua 192.168.20.171 502 3
--
-- Ablauf:
--  1. 3x Marker-Read auf Basis 40000 (Erwartung: OK 21365 28243 = "SunS")
--     mit echter Fehlermeldung (connect/timeout/EXC) statt Sammelfehler
--  2. Kompletter Modell-Scan (Basen 40000/0/50000) mit Modellliste
-- =====================================================================

local L = dofile("/usr/local/bin/profile_loader.lua")

local ip   = arg and arg[1]
local port = tonumber(arg and arg[2]) or 502
local unit = tonumber(arg and arg[3]) or 1

if not ip then
  print("Aufruf: lua sunspec_diag.lua <ip> [port] [unit]")
  os.exit(1)
end

print("Ziel: " .. ip .. ":" .. port .. " unit " .. unit)

print("-- Schritt 1: 3x Marker-Read auf 40000 --")
for i = 1, 3 do
  local w, e = L.read_regs(ip, port, unit, 3, 40000, 2)
  if w then
    local a, b = w[1], w[2]
    local marker = (a == 0x5375 and b == 0x6E53) and " = SunS-Marker OK" or " = KEIN SunS-Marker!"
    print("Versuch " .. i .. ": OK " .. a .. " " .. b .. marker)
  else
    print("Versuch " .. i .. ": " .. tostring(e))
  end
  L.sleep(2)
end

print("-- Schritt 2: Modell-Scan --")
local s, e = L.sunspec_scan(ip, port, unit)
if not s then
  print(tostring(e))
  os.exit(1)
end
print("BASE=" .. s.base)
local ids = {}
for id in pairs(s.models) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do
  local m = s.models[id]
  print("MODEL=" .. id .. " start=" .. m.data_start .. " len=" .. m.len)
end
