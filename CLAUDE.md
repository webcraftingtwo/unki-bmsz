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

- **The procedure is a locked gate chain. Never add a bypass.** A
  technician cannot reach face log, marking or offsets without the SHE
  record and access certification being complete and attributable. If a
  screen becomes reachable out of order, that is a bug, not a shortcut.
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

| Heading type | H/W limit | F/W limit | Source |
|---|---|---|---|
| Bord / ledging decline | +0.45 | −1.35 | Sheet 2NB3 12-07-10 |
| Decline / strike drive | +1.50 | −1.00 | Sheets MM 26-04-10, NS3 12-07-10 |

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
up-dip, 50 m tape taut top to bottom of bord.

## Deliberately absent

- **No photography.** No camera, no face-mapping canvas, no image
  columns. Removed on instruction. Do not reintroduce.
- **No sampling module.** Sample IDs, bags and lengths are out of scope.
  The *channel sampling request* stays — it is not a sampling feature,
  it is the gate that triggers the R4 block on continuous marking.

## Data model sketch

`face_logs` (peg, peg_distance, advance, face_length, bord_width,
bord_height, conditions) · `bmsz_markings` (visual_id, xrf profile, ppv,
confidence, mark_type continuous|indicative, sample_requested) ·
`offset_sets` + `offset_stations` (dist, hw, fw, width, cause) ·
`structures` · `hazards` · `shift_records` · `she_checklists` ·
`audit_log`.

Every row carries observer, timestamp, device, sync state, version.

## Open decisions — blocking full spec

Do not silently resolve these. Ask.

1. **Is STD-201 v2.0 still the governing standard under Valterra?** It
   is a 2011 AngloAmerican document and §5.0 requires annual review.
   SLAM is built against Valterra UNK-MIN-MIN-PRO-0002 v6.0. This is now
   the most urgent question in the project.
2. Station interval: §9.8.iv says 2 m; every supplied sheet records at
   1 m. Both are offered in the UI pending a ruling.
3. Station numbering starts at 0 on the sheets but §9.8.ii says the
   first station is 1 m off the sidewall. Is station 0 that 1 m point?
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

## When making changes

This is safety-critical software supporting a statutory geological
standard. Explain what you're changing and why before editing anything
that touches the gate chain, the R4 block, limit sets, RLS or the sync
queue. All diffs are reviewed before they ship.

This app is a data-capture and information tool. It does not replace
mine safety procedures, ground control, survey standards, formal hazard
reporting or competent-person interpretation. It is not an official Unki
Mine system unless formally authorised.
