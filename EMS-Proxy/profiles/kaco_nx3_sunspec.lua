-- =====================================================================
-- Profil: Kaco blueplanet NX3 10 kW (PV-Wechselrichter)
-- Standort: Hebauer. Phase 1: NUR LESEN - kein write-Block!
--
-- QUELLEN:
--  * KACO blueplanet NX1/NX3 SunSpec-Implementierungsliste
--    (Firmware V07 bis V.xy, Modbus TCP + RTU)
--  * SunSpec Device Information Model Specification v1.2.1
--
-- Von KACO BESTAETIGT implementierte SunSpec-Modelle (NX1/NX3,
-- inkl. 10.0 NX3 M2):
--    001 Common | 103 Inverter Three Phase | 120 Nameplate |
--    121 Basic Settings | 123 Immediate Controls |
--    160 Multiple MPPT Inverter Extension |
--    701 DER AC Measurement | 702 DER Capacity |
--    704 DER AC Controls | 714 DER Enter Service |
--    715 DER Frequency-Watt
--
-- WICHTIG (KACO-Vorgabe): KEINE festen absoluten Registeradressen
-- verwenden - die Adressen gelten nur fuer eine konkrete Firmware!
-- Modelle und Startadressen MUESSEN per SunSpec Model Scan zur
-- Laufzeit ermittelt werden. Deshalb enthaelt dieses Profil nur
-- Modell-relative Offsets (model + offset), keine Absolutadressen.
-- Schreibzugriff erfordert bei KACO eine separate Aktivierung am
-- Geraet - fuer Phase 1 (read-only) irrelevant.
--
-- SunSpec-Regeln (Spec v1.2.1):
--  * "SunS"-Marker (0x53756E53) an Adresse 0, 40000 ODER 50000.
--  * Modellkette: je Modell [ID u16][Laenge u16][Daten...];
--    Ende = Modell-ID 0xFFFF, Laenge 0.
--  * sunssf: s16, -10..+10, NOT IMPLEMENTED = 0x8000.
--    Echtwert = Rohwert * 10^SF. SF ist statisch -> beim Start
--    lesen und cachen.
--  * NOT-IMPLEMENTED-Sentinels: u16=0xFFFF, s16=0x8000,
--    u32=0xFFFFFFFF, s32=0x80000000 -> als "kein Wert" verwerfen.
-- =====================================================================

return {
  id           = "kaco_nx3_sunspec",
  name         = "Kaco blueplanet NX3 10kW (SunSpec Model Scan)",
  role         = "inverter",
  conn         = "tcp",
  port         = 502,
  unit_id      = 1,        -- am Geraet verifizieren (SunSpec oft 1 oder 126)
  min_gap_ms   = 100,
  has_watchdog = true,     -- irrelevant, read-only
  unverified   = true,     -- bis Model Scan am Geraet gelaufen ist

  -- SunSpec-Discovery: der Profil-Loader MUSS scannen (KACO-Vorgabe).
  sunspec = {
    scan_required   = true,                  -- keine Absolutadressen!
    base_candidates = { 40000, 0, 50000 },   -- "SunS"-Marker suchen
    end_model_id    = 0xFFFF,                -- Kettenende
    sf_not_impl     = 0x8000,                -- sunssf NOT IMPLEMENTED
    sf_static       = true,                  -- SF einmalig lesen + cachen
    -- Von KACO bestaetigte Modelle (Implementierungsliste NX1/NX3):
    models_expected = { 1, 103, 120, 121, 123, 160, 701, 702, 704, 714, 715 },
  },

  -- Messpunkte MODELL-RELATIV: model = SunSpec-Modell-ID,
  -- offset = Register-Offset ab Modell-Datenbeginn (nach ID+Laenge).
  -- Absolutadresse = ScanErgebnis(model).data_start + offset.
  -- Offsets lt. SunSpec-Standardmodell 103 (Inverter Three Phase):
  read = {
    -- Modell 103: W (Offset 14), W_SF (15), Hz (16), Hz_SF (17), St (36)
    ac_power = { model = 103, offset = 14, fc = 3, type = "s16", unit = "W",
                 sf_offset = 15, not_impl = 0x8000 },
    ac_freq  = { model = 103, offset = 16, fc = 3, type = "u16", unit = "Hz",
                 sf_offset = 17, not_impl = 0xFFFF },
    status   = { model = 103, offset = 36, fc = 3, type = "u16", unit = "",
                 not_impl = 0xFFFF },  -- St (enum16)
    -- Modell 701 (DER AC Measurement) als Alternative/Ergaenzung
    -- nach dem Scan pruefen - liefert W direkt in Watt-Aufloesung.
  },

  ui = {
    plaus = { ac_power = { -1000, 12000 } },
  },

  -- KEIN write-Block: read-only. Schreibzugriff wuerde bei KACO
  -- ohnehin separate Aktivierung am Geraet erfordern (Phase 2).
}
