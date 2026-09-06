-- =====================================================================
-- Profil: Kaco blueplanet NX3 10 kW (PV-Wechselrichter)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- ACHTUNG: VORLAEUFIG - Kaco-Registerdoku liegt noch nicht vor!
-- Annahme: NX3 spricht SunSpec Modbus TCP (Port 502).
-- SunSpec-Standard: Basis 40000 (0-basiert 40000 oder 40001 je nach
-- Zaehlung), Kennung "SunS" (0x53756E53) in den ersten 2 Registern,
-- danach Modellketten. Die u.a. Adressen gelten fuer die UEBLICHE
-- Kette Common(1)@40002 + WR-Modell 103 (dreiphasig)@40069 -
-- AM GERAET VERIFIZIEREN (Modellkette scannen!), bevor die Werte
-- in der Status-UI als gueltig behandelt werden.
-- SunSpec nutzt Skalenfaktor-Register (SF, s16, Wert = Basis*10^SF).
-- =====================================================================

return {
  id           = "kaco_nx3_sunspec",
  name         = "Kaco blueplanet NX3 10kW (SunSpec, VORLAEUFIG)",
  role         = "inverter",
  unit_id      = 1,        -- SunSpec-Default oft 1 oder 126 - verifizieren!
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- UI soll Werte als UNGEPRUEFT kennzeichnen

  read = {
    sunspec_id = { addr = 40000, fc = 3, type = "u32be", scale = 1, unit = "",
                   expect = 0x53756E53 },  -- "SunS" - Verifikations-Anker
    ac_power    = { addr = 40083, fc = 3, type = "s16", scale = 1, unit = "W",
                    sf_addr = 40084 },     -- Modell 103 W + W_SF (VORLAEUFIG)
    ac_freq     = { addr = 40085, fc = 3, type = "u16", scale = 1, unit = "Hz",
                    sf_addr = 40086 },     -- Hz + Hz_SF (VORLAEUFIG)
    status      = { addr = 40107, fc = 3, type = "u16", scale = 1, unit = "" }, -- St (VORLAEUFIG)
  },

  ui = {
    plaus = { ac_power = { -1000, 12000 } },
  },

  -- KEIN write-Block: read-only.
}
