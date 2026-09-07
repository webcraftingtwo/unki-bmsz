# Unki GeoTech

Underground BMSZ marking and face measurement app for Unki Mine
(Valterra Platinum). MRM department, Geological Technicians.

Built against **UNKI-MIN-MRM-STD-201 v2.0** "BMSZ Marking & Face
Measurements" (20/05/2011, AngloAmerican Platinum era). Marking detail
sits in **UNKI-MIN-MRM-PRO-200**, referenced at §9.6.3 — NOT YET
SUPPLIED, ask before assuming anything about marking procedure.

Sister app to **slam-reentry-system**. Same mine, same crews, same
Supabase project. Read that repo's CLAUDE.md before touching anything
here — its hard rules apply to this repo too.

## The rework — read before anything else

The app was cut back to one job: get the tape offsets off the face and
in front of the people who act on them. Basis: **Chief Geologist meeting
notes**, which is the §7.3 authorisation for the deviations below. Where
this section and the rest of this file disagree, this section is current.

- Offsets are stored in **centimetres**. Metres appear at exactly two
  places, both through `toM()`: the width-control report and the
  management screen. Nothing else converts.
- The traverse is **applied, not offered**: 1 m stations, first 1 m off
  the sidewall, **no station zero**, count = face length − 1. The **2 m
  and 5 m** readings are mandatory before save. This overrides §9.8.iv.
- Hangingwall − footwall is **mining height**, not stope width.
- The pre-shift, PPE, tools, transport, register and XRF checklists and
  the hazard form are **gone**. One safety control was kept and it
  blocks: the overseer's declaration that the area was made safe.
- Waste tonnage is **not calculated** — the formula's third term was
  crossed out in the notes and is unconfirmed.

## Stack

- Vanilla HTML / CSS / JS. NO build process, NO framework, NO npm.
- Supabase backend (Postgres + RLS + auth) — the SAME project as SLAM.
- Installable PWA, vendored dependencies, service worker app-shell cache.
- Deliberate, for the same reason as SLAM: runs underground on
  ruggedised tablets with no signal.

## Files

- index.html — field app used by Geological Technicians underground.
- (planned) review.html — Geologist / Chief Geologist review view.
- vendor/ — mirror SLAM's vendoring. Never re-point at a CDN.
- sw.js — app shell only. Never intercept Supabase or non-GET.
- migrations/ — apply BEFORE deploying app code that writes new columns.

## Hard rules — do not break these

Inherited from SLAM, and they are not negotiable here either:

- NEVER add external dependencies, a bundler, or a build step.
- NEVER weaken or bypass RLS. Ask before touching any RLS.
- Preserve the offline sync queue on ALL write paths. Writes queue when
  offline and flush when back online — never silently drop.
- Always escape user input to prevent XSS.
- Never put service-role keys or any secret in this repo. Anon key only.

Specific to this app:

- **The procedure is a locked gate chain. Never add a bypass.** The
  chain is now one gate shorter and starts at the face log: BMSZ
  marking, offsets and structures cannot be reached until a face log
  exists, and a face log cannot be submitted with the area declared not
  made safe or with no overseer named. If a screen becomes reachable out
  of order, that is a bug, not a shortcut.
- **Rule R4 is absolute.** Where channel samples have been requested,
  the BMSZ shall NOT and will NOT be marked as a continuous line. Only
  indicative marks. §9.7 is emphatic. Enforce it in code, not in copy.
- **Never overwrite an observation.** What the technician measured and
  what a geologist later interprets are separate values, both retained,
  both attributed. Corrections are new rows.
- Every requirement traces to a clause. If you add a checklist item or a
  rule, cite the clause. If the standard is silent, mark it DERIVED so
  the Chief Geologist can rule on it. Do not invent Unki policy.
- Marking accountability cannot be delegated (§9.1). A "second opinion"
  record must NOT transfer responsibility — it notifies the Section
  Geologist and the originating technician stays accountable.
- Deviation from the standard requires Chief Geologist authorisation
  (§7.3). Record it; never let the app grant it.

## Integration with slam-reentry-system

GeoTech is not a sibling receiving a feed. It is a **missing stage in
SLAM's existing Bord Cycle Tracker**.

SLAM's cycle is Drilling → Blasting → Lashing → Support → Complete →
Repeat. STD-201 §9.2 says ends are marked "as soon as they have been
supported and lashed to the footwall" and "no end will be marked unless
it is cleaned to the footwall". That is exactly the state after Support:

```
Blasting → Lashing → Support → [BMSZ MARKING] → Drilling → ...
```

Contract:

- A bord reaching **Support complete** surfaces to the Geological
  Technician for that section. Nothing else queues work to GeoTech.
- The cycle **must not advance to Drilling** until a marking record
  exists for that blast — that is the whole point. A drilled-out end
  with no BMSZ line is the failure mode this app exists to prevent.
- Re-entry status still gates entry: a bord that is held or pending
  cannot be opened, and the button is disabled, not merely warned about.
- Blast number, advance, peg reference and face dimensions carry across
  from the SLAM record. The technician never retypes them.
- The gas-safety trigger stays server-side. Do not read gas state
  client-side to make an entry decision.

OPEN: whether GeoTech writes back a cycle state to SLAM, or SLAM reads a
marking-exists flag. Decide before building the write path.

## Section compartmentalization

Identical to SLAM — sections are exactly "14 South" and "16 North",
zones are 14S B1–B8, 16N B1–B9, and 16N Strike. Nothing else.

- Same RLS enforcement. Client-side scoping is a UI mirror, NOT the
  enforcement. Never treat it as such.
- Shifts are A / B / C (6-on/3-off). shift_type stores 'A'/'B'/'C'.
- Crew display names ("Challengers", "Pioneers") come from
  crew-names.js. Never store a crew name in a section column.
- §9.1 assigns each Geological Technician two half levels — 6 bords and
  one strike belt in each. Map this onto the existing zone list; do not
  invent a parallel hierarchy.

NOTE: the supplied face marking sheets use working places 2NB3, NS3 and
MM. These are 2010-era and predate the pilot. Do not seed them as real
zones — they are sample data only.

## Roles

SLAM has miners, shift_boss, supervisor, safety_officer, she_manager,
admin. GeoTech adds:

- `geological_technician` — capture. Cannot alter validated
  interpretations.
- `section_geologist` — review, comment, notified on doubtful calls.
- `chief_geologist` — authorise deviations, version limit sets, full read.
- `mrm_manager` — read and report, signs stopped-end log.

These need an RLS migration on the shared project. Apply it before
shipping anything that writes with these roles.

## The offset module — read this before changing it

"Offset" in this app means **deviation of the blasted profile from the
design cut**. Over-break and under-break caused by the blast. It is NOT
geological displacement — faults and dykes go in the structures table.

This is the app's reason to exist. Measured against limits:

All values are **centimetres**.

| Heading type | H/W limit | F/W limit | Source |
|---|---|---|---|
| Bord / ledging decline | +45 | −135 | Sheet 2NB3 12-07-10 |
| Decline / strike drive | +150 | −100 | Sheets MM 26-04-10, NS3 12-07-10 |

A face with any station above **200 cm** mining height is flagged once
at save, not recomputed per report, and the management screen opens on
flagged faces first.

The "mining cut" series on the NS3 chart plots at exactly these limit
values, which confirms the limits ARE the design cut envelope.

Worked evidence from the supplied sheets:

- NS3: 8/8 stations over on BOTH walls. Design cut 2.50 m, actual
  3.80 m — 52% over, ~61 t waste from one blast.
- 2NB3: 12/12 over on H/W, 6/12 on F/W. 1.80 m design, 2.12 m actual —
  18% over. Expected grade 4.14 vs actual 3.36.

Limit sets are versioned data, never hard-coded constants. Changing one
requires Chief Geologist authorisation and an audit row.

Measurement geometry is fixed by §9.8 and must not be relaxed:
1 m from the face, first station 1 m from the sidewall, down-dip to
up-dip, 50 m tape taut top to bottom of bord. Station spacing is the one
part of §9.8 the rework overrides — see the rework section above.

Verified against sheet NS3 12-07-10, a 7.2 m face on decline limits:
6 offsets · mean H/W 245.33 · mean F/W −134.5 · mean mining height
379.83 (range 376–383) · mean over-break 95.33 cm · 3.80 m to
management. Those figures are the regression target for any change to
`osStats()`.

## Deliberately absent

- **No photography.** No camera, no face-mapping canvas, no image
  columns. Removed on instruction. Do not reintroduce.
- **No sampling module.** Sample IDs, bags and lengths are out of scope.
  The *channel sampling request* stays — it is not a sampling feature,
  it is the gate that triggers the R4 block on continuous marking.

Removed by the rework. Do not reintroduce without going back to the
Chief Geologist:

- **No SHE checklists.** PPE, tools, transport, underground register
  and XRF pre-inspection all duplicated controls the mine runs
  elsewhere. The §9.2 end-readiness gate is NOT one of these — it stays,
  on the face log.
- **No hazard form and no SOS button.** Hazards go through the mine's
  own reporting system.
- **No team-engagement screen.** Who was on the face is now four
  role chips on the face log.
- **No waste tonnage.** Unconfirmed formula, see the rework section.
- **No station-interval choice.** The traverse is applied.

## Data model sketch

`face_logs` (peg, peg_distance, face_length, channel_id, dist_to_face,
channel_far, tarp, xrf, design_hw_cm, design_fw_cm, readiness, team,
area_safe, overseer, structural) · `bmsz_markings` (visual_id, xrf
profile, ppv, confidence, mark_type continuous|indicative,
sample_requested) · `offset_sets` + `offset_stations` (dist, hw_cm,
fw_cm, height_cm, mandatory, cause) · `structures` · `shift_records` ·
`audit_log`.

Every row carries observer, timestamp, device, sync state, version.

Every `offset_sets` row also snapshots the limit set that judged it —
`hw_limit`, `fw_limit`, `limit_version`, `limit_label` — so a limit
revised next year cannot silently restate what an old face was measured
against. Never read limits live when displaying a historical record.

## Open decisions — blocking full spec

Do not silently resolve these. Ask.

1. **Is STD-201 v2.0 still the governing standard under Valterra?** It
   is a 2011 AngloAmerican document and §5.0 requires annual review.
   SLAM is built against Valterra UNK-MIN-MIN-PRO-0002 v6.0. This is now
   the most urgent question in the project.
2. ~~Station interval~~ — RULED. 1 m, applied not offered, overriding
   §9.8.iv. Chief Geologist, §7.3.
3. ~~Station numbering~~ — RULED. No station zero; the first station is
   the 1 m point off the sidewall.
4. Sampling cadence parity — §9.6.3 says "every second blast" but does
   not fix which. Current code assumes even blast numbers.
5. Source and timing of Expected vs Actual Grade.
6. Which records must legally remain hard copy, and is a digital
   signature acceptable for the miner's sign-off?
7. Required intrinsic-safety rating for underground tablets. Longest
   lead item — raise with SHE and Engineering early.
8. Niton XL3t export capability: SDK, pairing, or file only?
9. MRM/GMSI interface for stope width control (§9.8.vii).
10. Form STD2.1A (Stope Marking Tally) — not supplied.

Opened by the rework, all recorded rather than guessed at:

11. **Waste tonnage.** `V = face length × mining height × ?`, then
    × 3.21 S.G. The third term was crossed out in the notes. Not built.
12. **Design cut values.** Read as H/W +60 cm and F/W −140 cm for North,
    which would give exactly the 200 cm flag height. Unconfirmed, so
    they are an optional pair of fields rather than a rule.
13. **The 2 m and 5 m offsets.** Built as *both stations mandatory
    before save*. If two extra readings separate from the 1 m traverse
    were meant, that is a different build.
14. **TARP classes 1 / 2 / 3 / S.** The values are recorded; their
    meaning was not given, so no behaviour hangs off the choice. DERIVED.
15. **The 9 m channel limit.** Warns, never blocks. The exact distance
    is approximate in the notes.
16. **BMSZ → offset timer placement.** The notes list it as a face-log
    field; it is recorded on the offset set, which is where both
    endpoints exist. Confirm which was meant.
17. **Reference terminology.** Reef names and structure types are seeded
    placeholders, flagged in code. Not official Unki codes — replace
    before production use.

## When making changes

This is safety-critical software supporting a statutory geological
standard. Explain what you're changing and why before editing anything
that touches the gate chain, the R4 block, limit sets, RLS or the sync
queue. All diffs are reviewed before they ship.

This app is a data-capture and information tool. It does not replace
mine safety procedures, ground control, survey standards, formal hazard
reporting or competent-person interpretation. It is not an official Unki
Mine system unless formally authorised.
