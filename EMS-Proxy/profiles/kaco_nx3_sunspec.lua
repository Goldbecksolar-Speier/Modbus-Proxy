-- =====================================================================
-- Profil: Kaco blueplanet NX3 10 kW (PV-Wechselrichter)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- ACHTUNG: VORLAEUFIG - Kaco-Registerdoku liegt noch nicht vor!
-- Annahme: NX3 spricht SunSpec Modbus TCP (Port 502).
--
-- SunSpec-Regeln (Quelle: SunSpec Device Information Model
-- Specification v1.2.1):
--  * Basisadresse: "SunS"-Marker (0x53756E53) an Adresse 0, 40000
--    ODER 50000 - alle drei scannen, bis der Marker gefunden ist.
--  * Danach Modellkette: je Modell [ID u16][Laenge u16][Daten...];
--    Ende der Kette = Modell-ID 0xFFFF mit Laenge 0.
--  * SCALE FACTOR (sunssf): s16, gueltiger Bereich -10..+10,
--    NOT-IMPLEMENTED-Wert = 0x8000 (-32768).
--    Echtwert = Rohwert * 10^SF (SF negativ = Komma nach links).
--    SF-Register sind STATISCH (aendern sich zur Laufzeit nicht) -
--    duerfen einmal beim Start gelesen und gecacht werden.
--  * NOT-IMPLEMENTED-Sentinels: u16=0xFFFF, s16=0x8000,
--    u32=0xFFFFFFFF, s32=0x80000000 -> als "kein Wert" behandeln,
--    NICHT als Messwert anzeigen.
--
-- Die u.a. Adressen gelten fuer die UEBLICHE Kette Common(1)@40002 +
-- WR-Modell 103 (dreiphasig)@40069 - AM GERAET VERIFIZIEREN
-- (Modellkette scannen!), bevor die Werte in der Status-UI als
-- gueltig behandelt werden. Kaco kann abweichende Offsets nutzen.
-- =====================================================================

return {
  id           = "kaco_nx3_sunspec",
  name         = "Kaco blueplanet NX3 10kW (SunSpec, VORLAEUFIG)",
  role         = "inverter",
  conn         = "tcp",
  port         = 502,
  unit_id      = 1,        -- SunSpec-Default oft 1 oder 126 - verifizieren!
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- UI soll Werte als UNGEPRUEFT kennzeichnen

  -- SunSpec-Discovery-Hinweise fuer den Profil-Loader:
  sunspec = {
    base_candidates = { 40000, 0, 50000 },  -- "SunS"-Marker suchen
    end_model_id    = 0xFFFF,               -- Kettenende
    sf_not_impl     = 0x8000,               -- sunssf NOT IMPLEMENTED
    sf_static       = true,                 -- SF einmalig lesen + cachen
  },

  read = {
    sunspec_id = { addr = 40000, fc = 3, type = "u32be", scale = 1, unit = "",
                   expect = 0x53756E53 },  -- "SunS" - Verifikations-Anker
    -- Modell 103 (VORLAEUFIG): Wert = Rohwert * 10^SF(sf_addr).
    -- Loader-Regeln: sf_type = s16 (sunssf); sf == 0x8000 ODER
    -- Rohwert == NOT-IMPLEMENTED-Sentinel -> Wert verwerfen.
    ac_power    = { addr = 40083, fc = 3, type = "s16", scale = 1, unit = "W",
                    sf_addr = 40084, not_impl = 0x8000 },   -- W + W_SF
    ac_freq     = { addr = 40085, fc = 3, type = "u16", scale = 1, unit = "Hz",
                    sf_addr = 40086, not_impl = 0xFFFF },   -- Hz + Hz_SF
    status      = { addr = 40107, fc = 3, type = "u16", scale = 1, unit = "",
                    not_impl = 0xFFFF },                     -- St (enum16)
  },

  ui = {
    plaus = { ac_power = { -1000, 12000 } },
  },

  -- KEIN write-Block: read-only.
}
