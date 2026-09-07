-- =====================================================================
-- sunspec_diag.lua - SunSpec-Diagnose (READ-ONLY)
--
-- Aufruf: lua /usr/local/bin/sunspec_diag.lua <ip> [port] [unit]
-- Beispiel: lua /usr/local/bin/sunspec_diag.lua 192.168.20.171 502 3
--
-- Ablauf:
--  1. 3x Marker-Read auf Basis 40000 (Erwartung: OK 21365 28243 = "SunS")
--  2. Manueller Modell-Ketten-Walk ab Basis+2:
--     * 5 s Timeout, 0.5 s Pause, 3 Versuche pro Header
--     * bei Timeout: Sondierung addr-2 .. addr+4 (Laengen-Abweichung?)
-- =====================================================================

local L = dofile("/usr/local/bin/profile_loader.lua")

local ip   = arg and arg[1]
local port = tonumber(arg and arg[2]) or 502
local unit = tonumber(arg and arg[3]) or 1
local TMO  = 5

if not ip then
  print("Aufruf: lua sunspec_diag.lua <ip> [port] [unit]")
  os.exit(1)
end

print("Ziel: " .. ip .. ":" .. port .. " unit " .. unit)

local function read2_retry(addr)
  local last
  for t = 1, 3 do
    local w, e = L.read_regs(ip, port, unit, 3, addr, 2, TMO)
    if w then return w, nil, t end
    last = e
    L.sleep(1)
  end
  return nil, last, 3
end

print("-- Schritt 1: 3x Marker-Read auf 40000 --")
local base = nil
for i = 1, 3 do
  local w, e = L.read_regs(ip, port, unit, 3, 40000, 2, TMO)
  if w then
    local a, b = w[1], w[2]
    if a == 0x5375 and b == 0x6E53 then
      print("Versuch " .. i .. ": OK " .. a .. " " .. b .. " = SunS-Marker OK")
      base = 40000
    else
      print("Versuch " .. i .. ": OK " .. a .. " " .. b .. " = KEIN SunS-Marker!")
    end
  else
    print("Versuch " .. i .. ": " .. tostring(e))
  end
  L.sleep(2)
end

if not base then
  print("ABBRUCH: kein stabiler SunS-Marker auf 40000")
  os.exit(1)
end

print("-- Schritt 2: Modell-Ketten-Walk ab " .. (base + 2) .. " --")
local addr = base + 2
for n = 1, 60 do
  L.sleep(0.5)
  local h, e, tries = read2_retry(addr)
  if not h then
    print("Kette gestoppt bei addr=" .. addr .. ": " .. tostring(e))
    print("-- Schritt 3: Sondierung um addr=" .. addr .. " --")
    for _, off in ipairs({-2, -1, 1, 2, 3, 4}) do
      local a2 = addr + off
      L.sleep(0.5)
      local w2, e2 = L.read_regs(ip, port, unit, 3, a2, 2, TMO)
      if w2 then
        print("PROBE addr=" .. a2 .. ": OK " .. w2[1] .. " " .. w2[2])
      else
        print("PROBE addr=" .. a2 .. ": " .. tostring(e2))
      end
    end
    os.exit(1)
  end
  local id, len = h[1], h[2]
  if id == 0xFFFF then
    print("ENDE der Kette (0xFFFF) bei addr=" .. addr)
    break
  end
  local note = (tries > 1) and (" (erst Versuch " .. tries .. ")") or ""
  print("MODEL=" .. id .. " header=" .. addr .. " data_start=" .. (addr + 2)
        .. " len=" .. len .. note)
  addr = addr + 2 + len
end
print("Scan fertig.")
