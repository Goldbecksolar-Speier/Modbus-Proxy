#!/usr/bin/lua
-- =====================================================================
-- sniff_parse.lua - pcap (tcpdump -w) -> Modbus-TCP-Zeilen
-- fuer die Sniffer-Seite (sniffer.html) des EMS-Proxy auf RUTX11
--
-- Aufruf: lua sniff_parse.lua /tmp/emsproxy_sniff.pcap
-- Ausgabe je Modbus-Paket (Port 502):
--   ZEIT|SRC:PORT|DST:PORT|UNIT|FC|TYP|INFO
--   TYP: R = Lese-Request, W = Schreib-Request,
--        A = Antwort,      X = Exception-Antwort
-- Letzte Zeile: #COUNT=<n>
--
-- REIN PASSIV: liest nur die pcap-Datei, sendet nichts.
-- Lua 5.1 kompatibel, keine Bit-Ops, keine externen Libs.
-- Grenzen: nur Linktype Ethernet (br-lan), IPv4/TCP, erste Modbus-PDU
-- je TCP-Segment (fuer Traffic-Analyse ausreichend).
-- =====================================================================

local fn = arg and arg[1] or "/tmp/emsproxy_sniff.pcap"
local f = io.open(fn, "rb")
if not f then print("ERR:pcap-Datei fehlt: " .. fn) os.exit(1) end
local data = f:read("*a")
f:close()
if not data or #data < 24 then print("ERR:pcap leer") os.exit(1) end

-- pcap-Magic: Endianness des Dateiheaders erkennen
local le
local m1, m2 = data:byte(1, 2)
if m1 == 0xd4 or m1 == 0x4d then
    le = true            -- 0xa1b2c3d4 / 0xa1b23c4d little-endian geschrieben
elseif m1 == 0xa1 then
    le = false           -- big-endian
else
    print("ERR:kein pcap-Magic (tcpdump -w nutzen, kein Textformat)")
    os.exit(1)
end

local function u16h(pos)  -- 16 Bit, Header-Endianness
    local a, b = data:byte(pos, pos + 1)
    if not b then return nil end
    if le then return b * 256 + a else return a * 256 + b end
end

local function u32h(pos)  -- 32 Bit, Header-Endianness
    local a, b, c, d = data:byte(pos, pos + 3)
    if not d then return nil end
    if le then return ((d * 256 + c) * 256 + b) * 256 + a
    else return ((a * 256 + b) * 256 + c) * 256 + d end
end

local function n16(pos)   -- 16 Bit Network Byte Order (im Paket immer BE)
    local a, b = data:byte(pos, pos + 1)
    if not b then return nil end
    return a * 256 + b
end

local linktype = u32h(21)
if linktype ~= 1 then
    print("ERR:Linktype " .. tostring(linktype) .. " (erwartet 1 = Ethernet/br-lan)")
    os.exit(1)
end

local pos = 25          -- erster Paket-Header (nach 24 Byte Global-Header)
local count = 0

while pos + 16 <= #data + 1 do
    local ts   = u32h(pos)
    local incl = u32h(pos + 8)
    if not incl then break end
    local p = pos + 16
    pos = p + incl
    if pos > #data + 1 then break end   -- abgeschnittenes letztes Paket

    -- Ethernet-Header (14 Byte, optional VLAN-Tag +4)
    if p + 14 <= #data + 1 then
        local et  = n16(p + 12)
        local off = p + 14
        if et == 0x8100 then et = n16(p + 16); off = p + 18 end

        if et == 0x0800 and off + 20 <= #data + 1 then      -- IPv4
            local vihl  = data:byte(off)
            local ihl   = (vihl % 16) * 4
            local proto = data:byte(off + 9)
            if proto == 6 and off + ihl + 20 <= #data + 1 then  -- TCP
                local sip = string.format("%d.%d.%d.%d", data:byte(off + 12, off + 15))
                local dip = string.format("%d.%d.%d.%d", data:byte(off + 16, off + 19))
                local t     = off + ihl
                local sport = n16(t)
                local dport = n16(t + 2)
                local doff  = math.floor(data:byte(t + 12) / 16) * 4
                local pl    = t + doff                      -- TCP-Payload-Start
                local plen  = (p + incl) - pl               -- erfasste Payload-Laenge
                if plen >= 8 and pl + 7 <= #data
                   and (sport == 502 or dport == 502) then
                    -- MBAP: tid(2) pid(2) len(2) unit(1) fc(1)
                    local unit = data:byte(pl + 6)
                    local fc   = data:byte(pl + 7)
                    local typ, info

                    if dport == 502 then
                        -- ------- Request an den Server -------
                        if fc == 5 or fc == 6 or fc == 15 or fc == 16 then
                            typ = "W"
                        else
                            typ = "R"
                        end
                        if plen >= 12 and pl + 11 <= #data then
                            local addr = n16(pl + 8)
                            local v2   = n16(pl + 10)
                            if fc == 5 or fc == 6 then
                                info = "addr=" .. addr .. " val=" .. v2
                            else
                                info = "addr=" .. addr .. " qty=" .. v2
                            end
                        else
                            info = "(gekuerzt)"
                        end
                    else
                        -- ------- Antwort vom Server -------
                        if fc >= 128 then
                            typ = "X"
                            local exc = 0
                            if plen >= 9 and pl + 8 <= #data then exc = data:byte(pl + 8) end
                            info = "EXC=" .. exc
                            fc = fc - 128
                        else
                            typ = "A"
                            if fc == 3 or fc == 4 then
                                local bc = 0
                                if plen >= 9 and pl + 8 <= #data then bc = data:byte(pl + 8) end
                                info = "bytes=" .. bc
                            elseif (fc == 5 or fc == 6 or fc == 15 or fc == 16)
                                   and plen >= 12 and pl + 11 <= #data then
                                info = "addr=" .. n16(pl + 8) .. " val=" .. n16(pl + 10)
                            else
                                info = ""
                            end
                        end
                    end

                    print(string.format("%s|%s:%d|%s:%d|%d|%d|%s|%s",
                        os.date("%H:%M:%S", ts), sip, sport, dip, dport,
                        unit, fc, typ, info or ""))
                    count = count + 1
                end
            end
        end
    end
end

print("#COUNT=" .. count)
