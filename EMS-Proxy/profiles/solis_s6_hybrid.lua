-- =====================================================================
-- Profil: Solis S6 Hybrid 50 kW (Energiespeicher-Wechselrichter)
-- Quelle: RS485_MODBUS ESINV-33000ID Hybrid Inverter v3.4 (FC04)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- Anbindung: Solis-Datalogger S2-WL-ST (LAN-Anschluss).
-- Der S2-WL-ST unterstuetzt Modbus TCP NATIV (Herstellerangabe,
-- Solis "Modbus TCP Communication Guide for S2-WL-ST"):
--  * Modbus-TCP-Server auf Port 502 (Default)
--  * Direktanschluss-Default-IP: 10.10.100.254 (im LAN per DHCP,
--    statische IP ueber SolisCloud-App "LAN Settings" empfohlen)
--  * Register-Adressierung im Guide beginnt bei 0 -> ggf. Offset -1
--    gegenueber der Protokollliste testen (33139 vs. 33138)!
-- Timing lt. Protokoll: >= 300 ms zwischen Lese-Frames,
-- max. 50 Register pro Frame (RTU-Seite 9600 8N1).
--
-- Vorzeichen-/Richtungskonventionen (WICHTIG):
--  * Batterie: 33149/50 ist der BETRAG; Richtung kommt aus 33135
--    (0 = Laden, 1 = Entladen). Proxy-Konvention (>0 = Entladen)
--    wird per bat_dir_reg hergestellt.
--  * AC-Grid-Port 33151/52: + = Leistung fliesst aus dem WR raus.
--  * Meter 33263/64: + = Einspeisung ins Netz, - = Netzbezug.
-- =====================================================================

return {
  id           = "solis_s6_hybrid",
  name         = "Solis S6 Hybrid 50kW (ESINV-33000ID v3.4)",
  role         = "inverter_battery",
  conn         = "tcp",     -- via S2-WL-ST Datalogger, Port 502
  port         = 502,
  unit_id      = 1,        -- Slave-Adresse am Datalogger; am Geraet pruefen!
  min_gap_ms   = 300,      -- Herstellervorgabe Lese-Intervall
  max_regs     = 50,       -- max. Register pro Frame
  has_watchdog = true,     -- irrelevant solange read-only (kein write-Block)

  read = {
    pv_power     = { addr = 33057, fc = 4, type = "u32be", scale = 1,    unit = "W"  },  -- Total PV Input Power
    ac_power     = { addr = 33079, fc = 4, type = "s32be", scale = 1,    unit = "W"  },  -- Active Power Inverter
    grid_freq    = { addr = 33094, fc = 4, type = "u16",   scale = 0.01, unit = "Hz" },
    status       = { addr = 33095, fc = 4, type = "u16",   scale = 1,    unit = ""   },  -- Appendix 3 (M33095)
    fault        = { addr = 33070, fc = 4, type = "u16",   scale = 1,    unit = ""   },  -- mit 33095 kombinieren
    bat_voltage  = { addr = 33133, fc = 4, type = "u16",   scale = 0.1,  unit = "V"  },
    bat_current  = { addr = 33134, fc = 4, type = "s16",   scale = 0.1,  unit = "A"  },  -- Betrag, Richtung 33135
    bat_dir      = { addr = 33135, fc = 4, type = "u16",   scale = 1,    unit = ""   },  -- 0=Laden, 1=Entladen
    bat_soc      = { addr = 33139, fc = 4, type = "u16",   scale = 1,    unit = "%"  },
    bat_soh      = { addr = 33140, fc = 4, type = "u16",   scale = 1,    unit = "%"  },
    bat_power    = { addr = 33149, fc = 4, type = "s32be", scale = 1,    unit = "W",
                     dir_reg = 33135, dir_discharge = 1 },                               -- Betrag; >0 Entladen via dir_reg
    grid_port_p  = { addr = 33151, fc = 4, type = "s32be", scale = 1,    unit = "W"  },  -- + aus WR raus
    meter_power  = { addr = 33263, fc = 4, type = "s32be", scale = 1,    unit = "W"  },  -- + Einspeisung, - Bezug
    house_load   = { addr = 33147, fc = 4, type = "u16",   scale = 1,    unit = "W"  },  -- netzseitige Last (>65kW: +34343)
  },

  ui = {
    plaus = { bat_soc = { 0, 100 }, ac_power = { -60000, 60000 } },
  },

  -- KEIN write-Block: Profil ist strikt read-only (Hebauer Phase 1).
  -- Phase 2 (Steuerung) nur nach Klaerung: Register 43xxx (FC03/06/10),
  -- Steuer-Intervall >= 700 ms, Freigabe-/Failsafe-Konzept.
}
