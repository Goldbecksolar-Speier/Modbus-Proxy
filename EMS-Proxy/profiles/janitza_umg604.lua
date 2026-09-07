-- =====================================================================
-- Profil: Janitza UMG 604 (Netzanschlusszaehler, OHNE 'Pro')
-- Standort: Hebauer (Brand nutzt UMG 604 Pro - Registerlage lt. Doku
-- weitgehend identisch). Phase 1: NUR LESEN - kein write-Block!
--
-- Quelle: janitza-mal/bhb-umg604 (Knowledge): Modbus TCP Port 502,
-- Float32-Block ab 19000: 19000/19002/19004 = UL1/UL2/UL3-N,
-- 19012/19014/19016 = I L1/L2/L3,
-- 19020/19022/19024 = P L1/L2/L3, 19026 = Psum. Alles BIG-ENDIAN.
--
-- VERIFIZIERT am Geraet (Hebauer, 2026-09-06):
--  * U L-N ~227 V plausibel -> Registerlage + f32be Word-Order OK
--  * P: L1+L2+L3 ~ Psum (124,2 ~ 128,3 W) -> intern konsistent
--  * Unit-ID 1, Port 502 via devices.html/device_poll bestaetigt
-- Plausibilitaetscheck Stroeme: I ~ P / U je Phase (bei cos phi ~1).
-- =====================================================================

return {
  id           = "janitza_umg604",
  name         = "Janitza UMG 604 (Netzzaehler)",
  role         = "meter",
  unit_id      = 1,        -- am Geraet bestaetigt (2026-09-06)
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only

  read = {
    u_l1n = { addr = 19000, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L1-N
    u_l2n = { addr = 19002, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L2-N
    u_l3n = { addr = 19004, fc = 3, type = "f32be", scale = 1, unit = "V" },  -- Spannung L3-N
    i_l1  = { addr = 19012, fc = 3, type = "f32be", scale = 1, unit = "A" },  -- Strom L1
    i_l2  = { addr = 19014, fc = 3, type = "f32be", scale = 1, unit = "A" },  -- Strom L2
    i_l3  = { addr = 19016, fc = 3, type = "f32be", scale = 1, unit = "A" },  -- Strom L3
    p_sum = { addr = 19026, fc = 3, type = "f32be", scale = 1, unit = "W" },  -- Wirkleistung Summe
    p_l1  = { addr = 19020, fc = 3, type = "f32be", scale = 1, unit = "W" },
    p_l2  = { addr = 19022, fc = 3, type = "f32be", scale = 1, unit = "W" },
    p_l3  = { addr = 19024, fc = 3, type = "f32be", scale = 1, unit = "W" },
  },

  ui = {
    plaus = { p_sum = { -150000, 150000 }, u_l1n = { 180, 260 } },
  },

  -- KEIN write-Block: read-only.
}
