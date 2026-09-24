# Unki GeoTech

Underground BMSZ marking and face measurement app for Unki Mine
(Valterra Platinum). MRM department, Geological Technicians.

Built against **UNKI-MIN-MRM-STD-201 v2.0** "BMSZ Marking & Face
Measurements" (20/05/2011, AngloAmerican Platinum era). Marking detail
sits in **UNKI-MIN-MRM-PRO-200**, referenced at §9.6.3 — NOT YET
SUPPLIED, ask before assuming anything about marking procedure.

Sister app to **slam-reentry-system**. Same mine, same crews, but a
**separate Supabase project** — see the hard rules. Read that repo's
CLAUDE.md before touching anything here; its hard rules apply to this
repo too.

## REWORK 3 — the board is gone, and how rendering works

- **The re-entry board is removed.** The workplace screen (`renderPlace`)
  is the only way into a shift: the technician names the face and types
  its parameters. Sign in → **Workplace** → Acknowledgement → Face log →
  Offsets / Structures → Shift report → Sign out.
- **What went with it**, recorded so it is not discovered by surprise:
  re-entry status no longer gates entry at all; SLAM's Bord Cycle
  Tracker queues work nowhere; advance, peg and face dimensions are
  self-asserted rather than carried from the blast record.
- There is no mock feed and no `fetchReentryFeed()`. If the feed
  returns, it belongs behind one function that fills `place` — nothing
  else in the file ever knew where `place` came from.

### Rendering — the rule that stops a whole class of bug

A full render replaces `main.innerHTML`, which destroys every element
inside it **including the one being typed in**. Any text field whose
`oninput` called `render()` lost focus and caret on every keystroke.
That was a real, reported bug: typing a miner's name was one character
per tap.

Two rules, in order:

1. **Never re-render on a keystroke.** Text fields update state only,
   and whatever depends on them is patched in place — `refreshAckGate()`,
   `refreshChannelFlag()`, the workplace traverse preview. Use
   `addEventListener('input', …)`, never `oninput = … render()`.
2. **A full render carries focus across it.** `render()` wraps the swap
   in `captureFocus()` / `restoreFocus()` — id, caret range and scroll.
   That is the safety net for anything rule 1 misses.

Also: a view change no longer rebuilds the shell. `setView()` swaps only
the content region, patches the nav, and plays the enter animation.
Online/offline patches the net pill rather than redrawing the screen
under the technician.

Motion lives in four tokens — `--ease`, `--t-fast`, `--t`, `--t-slow` —
and everything interactive transitions the same way, on transform,
opacity and colour only. All of it is disabled under
`prefers-reduced-motion`.

## REWORK 2

A second round of handwritten notes, confirmed by the technician's
superiors, so the §7.3 authorisation chain holds. Where this section and
anything below disagree, this section is current.

(Screen order was revised again by REWORK 3 above.)

- **The BMSZ marking screen is gone.** With it went Rule R4 — see the
  hard rules below, because this changes one of them.
- ~~The re-entry board is optional.~~ REWORK 3 removed it entirely.
  Blast number and hardness are still not collected. Every face now
  carries `place.source = 'manual'` and has **not** been cleared for
  entry by anything.
- **Acknowledgement is its own screen and is the gate**: end readiness,
  team on face, miner acknowledgement. It cannot be passed with the area
  declared not made safe or with no miner named.
- **"End is cleaned to the footwall" was removed** from readiness. §9.2's
  wording — *"No end will be marked unless it is cleaned to the
  footwall"* — is therefore no longer enforced by this app.
- **Offsets are TWO ROUNDS**: the same stations walked at **2 m** from
  the face, then again at **5 m**. Both must be complete before save.
  Tape set-up confirmation removed.
- **F/W readings are forced negative** at the keypad.
- **Mean F/W excess (cm) added**; **height range removed**.
- **The 9 m channel rule now flags for sampling** rather than only
  warning. It still never blocks.
- **Face photo with mark-up** added to Structures — this reverses the
  old "no photography" rule.
- **Notes / log book and the Management screen are gone.** The report is
  renamed **Shift report**.
- Face log keeps advance, face length/width/height, survey peg, channel
  ID and TARP class. XRF reading and the design-cut pair were removed.

## The first rework

The app was cut back to one job: get the tape offsets off the face and
in front of the people who act on them. Basis: **Chief Geologist meeting
notes**, the §7.3 authorisation for the deviations below.

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
- Supabase backend (Postgres + RLS + auth) — GeoTech's OWN project,
  `GeoTech` (`finnereptajssuzshrrc`), **wired and live**. NOT SLAM's.
  See the hard rules. No client library: the API is HTTPS + JSON and
  `fetch` is enough, so there is no bundle to vendor or maintain.
- Installable PWA, vendored dependencies, service worker app-shell cache.
- Deliberate, for the same reason as SLAM: runs underground on
  ruggedised tablets with no signal.

## Files

- index.html — field app used by Geological Technicians underground.
- review.html — management / Geologist review dashboard. READ ONLY.
- seed-demo.html — writes ten invented faces into the device store so the
  dashboard has something to show. NOT part of the app: not linked from
  either page, never deployed to a working tablet. Every row it writes
  carries `demo:true`, review.html says so in a banner and tags each
  affected row, and its "remove" touches nothing without that flag.
- vendor/ — mirror SLAM's vendoring. Never re-point at a CDN.
- sw.js — app shell only. Never intercept Supabase or non-GET.
- migrations/ — apply BEFORE deploying app code that writes new columns.
  0001 (schema), 0002 (profile provisioning), 0003 (helpers out of the
  public API) are all **applied** to the GeoTech project.
  `verify_0001.sql` runs 0001 against a throwaway Postgres and asserts
  58 checks including the NS3 regression target — run that, do not
  review the schema by reading it.

## Hard rules — do not break these

Inherited from SLAM, and they are not negotiable here either:

- NEVER add external dependencies, a bundler, or a build step.
- NEVER weaken or bypass RLS. Ask before touching any RLS.
- **NEVER touch SLAM's Supabase project.** GeoTech has its own:
  `GeoTech` (`finnereptajssuzshrrc`), eu-central-1, created 2026-09-24. The
  project `valterra-slam-reentry` (`qdlaaiofcrfkrsujhisg`) is
  slam-reentry-system's production database — 18 tables, RLS on all of
  them, live rows including `audit_log`, `gas_readings` and
  `phase_progress`. It is read-only reconnaissance at most, and only
  when there is a reason. No migration, no DDL, no seed, no writes.
  Any other project in the account is likewise off limits unless it was
  created for this app and named as such.
- Preserve the offline sync queue on ALL write paths. Writes queue when
  offline and flush when back online — never silently drop.
- Always escape user input to prevent XSS.
- Never put service-role keys or any secret in this repo. Anon key only.

Specific to this app:

- **The procedure is a locked gate chain. Never add a bypass.** The
  chain is: acknowledgement → face log → offsets and structures.
  **Moving to a different bord clears the acknowledgement.** "The area was
  made safe" is a statement about one end by a named miner who stood at it;
  letting it carry to the next face would open that face's log on a
  declaration nobody made about it. Correcting the same face keeps it. The
  acknowledgement screen cannot be passed with the area declared not made
  safe or with no miner named; until it is passed the face log is
  unreachable, and until a face log exists offsets and structures are
  unreachable. If a screen becomes reachable out of order, that is a bug,
  not a shortcut.
- **Rule R4 is no longer enforced by this app.** §9.7 blocks marking a
  continuous line where channel samples have been requested. That block
  lived on the BMSZ marking screen, which REWORK 2 removed on
  instruction. Nothing else here records a marking decision, so nothing
  else can enforce it. This is a known, authorised gap, not an oversight
  — if a marking decision ever returns to this app, the R4 block returns
  with it, in code and not in copy.
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

Contract — **NOT IMPLEMENTED.** REWORK 3 removed the re-entry board, so
none of the following is wired up today. It is kept as the design intent
for if and when the feed returns.

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

These need an RLS migration on **GeoTech's own** project. Apply it
before shipping anything that writes with these roles — `migrations/`
runs before app code, always.

### Accounts and sign-in

The pick-a-name-and-any-4-digit-PIN login is gone. People create an
account (name, employee number, section, role, password) and sign in
with employee number + password.

- Passwords are never stored. Each account keeps a random 16-byte salt
  and a **PBKDF2-SHA-256** derivation at **210,000 iterations**;
  sign-in re-derives and compares in **constant time**.
- **Auth fails closed.** If `crypto.subtle` is missing the app refuses
  to create or check a password. Never add a weaker fallback — a cheap
  hash is worse than a refusal, because a refusal gets noticed.
- 5 failed attempts locks the account for 15 minutes, and the lockout
  holds against the correct password too.
- One message covers "no such account" and "wrong password". Telling
  them apart enumerates who works here.
- Sessions carry an expiry of one shift (12 h). An expired session is
  dropped at boot; captured work is untouched and still syncs.

**Accounts are per-device and are NOT the enforcement boundary.** RLS
is. A signed-in role in `index.html` never authorises reading another
section's data. Role at registration is **self-declared** and stored as
`roleSource:'self-declared'` — it grants nothing, and §7.3 deviation
authorisation still belongs to the Chief Geologist.

Four functions were the whole Supabase seam, and they are now wired.
Nothing else in `index.html` knows the backend exists, except
`syncNow()`, which pushes records.

| Function | Is now |
|---|---|
| `findAccount()` | the cached offline credential for this device |
| `createAccount()` | `POST /auth/v1/signup` |
| `authenticate()` | `POST /auth/v1/token`, then a `profiles` read |
| `newSession()` | the tokens auth returns, plus the 12 h shift expiry |

### How sign-in actually works

- **Employee number, not e-mail.** Supabase auth is keyed on an address;
  the mine signs in with a number. `sbEmail()` maps one to the other:
  `UK-4471` → `uk-4471@geotech.unki.invalid`. `.invalid` is reserved by
  RFC 2606 and can never route, which is the point — these are handles,
  not mailboxes.
- **Therefore e-mail confirmation must stay OFF** for the project
  (Authentication → Providers → Email). A confirmation to a `.invalid`
  address can never arrive, so every account would be stranded.
- **The profile row is created by a trigger on `auth.users`**, not by the
  client. The app has no INSERT on `profiles` and must never be given
  one.
- **Role is set by the server and the form does not ask.** Everyone is
  created `geological_technician`. A self-declared `chief_geologist`
  would otherwise hold §7.3 deviation authority and the right to version
  limit sets. Elevation is an admin `update` against the database — the
  SQL is in migration 0002.
- **Section IS believed**, because nobody could sign up otherwise, and it
  is recorded as `section_source = 'self-declared'`. Section is the RLS
  read boundary, so this is the weakest point in the design — see open
  decision 36.
- **Offline sign-in still works, after the first time.** Once the server
  has verified someone on a device, a PBKDF2 record of that password is
  cached locally (same 210k iterations as before) and used when there is
  no signal. It can only ever say yes to a password the server has
  already accepted on that device; it is a cached verdict, not a second
  authority. A first sign-in on a new device needs a connection.
- **The server's answer is final.** When the server is reachable and says
  no, there is no local fallback — otherwise a revoked password would
  outlive its revocation.

### The write path

Capture goes to the device store first, always, and is pushed
afterwards. Underground there is no signal, and a capture that depended
on the network would be a capture that did not happen.

- A record is marked `synced` **only** after the server returns the row
  it stored. A failure leaves it queued, with `syncError` set, to be
  retried. Nothing is ever dropped.
- Order follows the foreign keys: shift, face log, offset set with its
  stations, structures. The shift row is created lazily on first need,
  because face logs reference a shift long before sign-out writes it.
- **Only one push may be in flight.** `syncNow()` holds a promise and a
  second caller awaits the first. This is not tidiness: reconnecting
  fires the automatic flush at the same moment as a press of the sync
  button, both runs read the same unsynced records, and the same face
  measurement is inserted twice. Two identical rows in a statutory
  record are worse than a failed sync, because nothing about them looks
  wrong. Found in testing; do not remove the guard.
- Reconnecting flushes the queue by itself. The `online` listener does
  it, rather than leaving it to whoever remembers the button.
- **The face photograph does not sync yet.** The schema holds
  `photo_path`, a reference into Storage, and there is no bucket (open
  decision 29). The written record goes up complete; the image stays on
  the device. This is survivable only because the photo was always
  defined as an addition to that record, never a replacement for it.

## Running it in a browser

    python3 -m http.server 8000     # from the repo root
    # field app:  http://localhost:8000/index.html
    # dashboard:  http://localhost:8000/review.html

Serve it — do not open the files with `file://`. Browsers give `file://`
pages an opaque origin, so the two pages get separate storage and the
dashboard sees nothing.

### Where records live

Three backends, picked once in this order. Key shape is identical across
all three (`PFX:kind:id`), and nothing above the storage block knows
which is in use.

| Backend | When | Persists? |
|---|---|---|
| `window.storage` | the host provides it (installed PWA, tablet shell) | yes — always wins |
| `localStorage` | a plain browser over http | yes, per browser+origin |
| memory | site data blocked (private window) | **no** — one sitting only |

`STORE.kind` tells you which one is live. In the memory case a save says
*"Held in memory only — will be lost on reload"* rather than "Saved" —
never tell a technician a record is safe when it is not.

The dashboard uses the same picker with no `set()`, so whichever backend
the field app wrote to on that device is the one it reads.

## review.html — the management dashboard

What management sees after a technician has captured a shift. It opens the
same store the field app writes to and **never writes back**: there is no
`put()` in the file. A correction is a new row captured in the field app,
never an edit made here (§9.1).

- **Metres for management, centimetres underneath.** Same boundary rule as
  the field app, through the same `toM()`. The hero figure and the "vs cut"
  column carry both.
- **Two sources, and the page says which.** Reading **this device**, the
  figures are the ones the handset computed at save. Reading **the mine
  server**, they come from `offset_set_stats` — derived by Postgres from the
  stations and that same snapshot, never from what the handset submitted.
  The server view is authoritative and the device view is not.
- **Nothing is recomputed in this file**, on either source. A limit revised
  later must not restate what an old face was judged by, which is why every
  record carries the limit set that judged it.
- Signing in here is a read. There is still no `put()`.
- Structure: hero (mean mining height vs design cut) → KPI row → faces
  ranked against their cut → what is driving the over-break → the table of
  every face, with a station-level drill-in → acknowledgement audit →
  structures with their marked-up photos.

### Chart colour is computed, not chosen

Run through the data-viz validator against the card surface `#1A170F` in
dark mode. Do not eyeball replacements — re-run it.

| Job | Mark | Result |
|---|---|---|
| Diverging (over / under cut) | `#E0553A` / `#3F9C63`, neutral gray midpoint | all PASS; CVD ΔE 6.6 deutan = WARN |
| Magnitude (causes, nominal) | `#B08A1E`, one hue for every bar | all PASS |

The CVD WARN on a red/green pair is unavoidable and is legal **only with
secondary encoding**, so every bar carries its signed value and the words
OVER CUT / WITHIN CUT. Colour never carries meaning alone.

The app's brand yellow `#FFC61A` (L 0.854) and green `#5FB87A` (L 0.711)
fall outside the dark lightness band and are **not** used as chart marks —
they stay as UI accents, where the band does not apply.

Causes are nominal, so they take **one** hue. Never colour those bars by
value: it spends the identity channel re-encoding what bar length shows.

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

Measurement geometry, as amended by REWORK 2: stations at 1 m with the
first 1 m from the sidewall, down-dip to up-dip, no station zero — and
the whole traverse is walked **twice**, standing **2 m** from the face
and then **5 m**. §9.8's "1 m from the face" and §9.8.iv's two-metre
station interval are both overridden, under the §7.3 chain.

Verified against sheet NS3 12-07-10, a 7.2 m face on decline limits, as
round 1: 6 offsets · mean H/W 245.33 · mean F/W −134.5 · mean mining
height 379.83 · mean H/W excess 95.33 cm · **mean F/W excess 34.5 cm** ·
3.80 m to management. Those figures are the regression target for any
change to `statsFor()`.

## Deliberately absent

- **No sampling module.** Sample IDs, bags and lengths are out of scope.

Removed by the first rework:

- **No SHE checklists.** PPE, tools, transport, underground register
  and XRF pre-inspection all duplicated controls the mine runs
  elsewhere.
- **No hazard form and no SOS button.** Hazards go through the mine's
  own reporting system.
- **No waste tonnage.** Unconfirmed formula, see open decision 11.
- **No station-interval choice.** The traverse is applied.

Removed by REWORK 2:

- **No BMSZ marking screen** — and therefore no R4 block. See the hard
  rules.
- **No notes / log book screen.**
- **No Management screen.**
- **No tape set-up confirmation** on offsets.
- **No height range** in the offset summary.
- **No XRF reading or design-cut pair** on the face log.

**Photography is now IN**, reversing the earlier "no photography, do not
reintroduce". REWORK 2 note 7 adds a face photo to Structures that the
technician marks up — waste patches, geological features — so a
geologist can see what was meant. It is a plain file input and a 2D
canvas, no library. Downscaled to 1280 px at quality 0.72, because a
full-resolution photo per structure would fill the device store before
the shift ended. **The photo is an addition to the written record, never
a replacement** — type, strike, dip and distance are still required, and
a drawing is not a measurement.

## Data model sketch

`face_logs` (peg, advance, face_length, face_width, face_height,
channel_id, dist_to_face, sample_flagged, tarp, structural, source,
ack) · `offset_sets` (heading, limits + snapshot, and two `rounds`, each
with `dist` 2 or 5, its `stations` and its own `stats`) ·
`offset_stations` (dist, hw_cm, fw_cm, height_cm, cause) ·
`structures` (+ `photo` as a JPEG data URL, `photo_strokes`) ·
`shift_records` · `audit_log`.

Every row carries observer, timestamp, device, sync state, version.

Every `offset_sets` row also snapshots the limit set that judged it —
`hw_limit`, `fw_limit`, `limit_version`, `limit_label` — so a limit
revised next year cannot silently restate what an old face was measured
against. Never read limits live when displaying a historical record.

Face photos are stored inline as data URLs today. That is fine for a
device store and wrong for Postgres — when the Supabase path is built,
they belong in Storage with the row holding a reference.

### migrations/0001 — where the app's promises become guarantees

Written, verified against a real Postgres 16, **applied to no project**.
It exists because three rules that `index.html` can only ask for
politely are cheap to make structural:

- **"Never overwrite an observation" (§9.1).** The capture tables have
  an INSERT policy and a SELECT policy and nothing else. No UPDATE
  policy, no DELETE policy, and `update`/`delete` revoked from
  `authenticated` outright so the refusal is an error rather than a
  silent "0 rows". That holds against the Chief Geologist too — the
  suite checks it. A correction is a new row.
- **The figures are derived, not submitted.** `offset_set_stats` and
  `offset_round_stats` compute every mean and breach count from the
  stations and the row's own snapshotted limits. The handset's numbers
  land in `reported_stats` and are never read as truth;
  `offset_stat_drift` surfaces any disagreement rather than hiding it.
  The suite pins these to the NS3 sheet: 245.33 / −134.5 / 379.83 /
  95.33 / 34.5 and 3.80 m to management, server-side.
- **Section scoping is RLS,** not the UI mirror. A 14 South technician
  cannot read 16 North's stations even through the views
  (`security_invoker = on`), cannot write a row attributed to anyone
  else, and cannot author a limit set at all.

The standard also lands as constraints: F/W negative, no station zero,
rounds at 2 m and 5 m only, sections exactly the two, interval fixed at
1 m, a station past the cut requires a cause, and a face log cannot be
written with `area_safe` false or no named miner. A bad row is
unwritable rather than merely discouraged.

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
13. ~~The 2 m and 5 m offsets~~ — RULED by REWORK 2. They are two
    ROUNDS, not two stations: the traverse is walked at 2 m from the
    face and again at 5 m.
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

Opened by the sign-in rework:

18. **Should accounts be self-serve at all?** PARTLY RULED by the
    wiring, in the only direction that was safe: sign-up is still
    self-serve, but the server decides what it means. A trigger on
    `auth.users` creates the profile — the client has no INSERT — and
    **role is forced to `geological_technician`**, so a self-declared
    Chief Geologist gets nothing. Still open: whether MRM should
    provision accounts outright rather than let people register.
19. **Role provisioning.** Elevation is an `update` run against the
    database, which nobody can do from the app — not even a Chief
    Geologist, since there is no UPDATE policy or privilege on
    `profiles`. The SQL is in `migrations/0002`. Still open: **who at
    the mine runs it**, and what evidence they need first.
20. **Password policy.** 10 characters minimum, no composition rules,
    5 attempts then a 15-minute lockout. DERIVED — no Unki policy was
    supplied. Confirm against the mine's IT standard.
21. **Session length.** 12 h, chosen to match a shift. Confirm.
22. **Account recovery.** There is none. A technician who forgets a
    password underground cannot sign in and cannot capture. Needs a
    ruling before production — this is the one that will bite first.

Opened by REWORK 2:

23. **R4 has no home.** §9.7's block on continuous marking where samples
    were requested went with the BMSZ screen. Authorised, but the mine
    should know the app no longer enforces it and decide where it now
    lives.
24. **§9.2 "cleaned to the footwall"** is likewise no longer enforced.
    Same question: where does that check live now?
25. **Hand-entered faces bypass re-entry.** A face typed in by hand has
    had no gas or re-entry clearance. The app records `source:'manual'`
    and says so on screen; it cannot do more. Confirm this is acceptable
    and who reviews those records.
26. **Two words from the notes I could not read**, and guessed:
    "O/I Miner" on the team list, and a phrase under the miner
    acknowledgement that looked like "OPP is true" — not built, because
    I could not read it. Confirm both.
27. **"Overminer" vs "Miner" acknowledgement.** Page 1 of the notes says
    Overminer, the design page says Miner. Built as Miner.
28. **Station spacing inside a round** is still 1 m. The notes fix the
    two round distances but say nothing about spacing, so decision 2's
    ruling was carried forward.
29. **Photo retention — and they do not sync.** Face photos are stored
    on the device at 1280 px / q0.72. There is no Storage bucket, so
    `structures.photo_path` is always null and **the photograph never
    leaves the tablet**. A geologist reading the server sees the written
    record without the image. Survivable only because the photo was
    always an addition to that record, never a replacement. Needs a
    bucket, a retention rule and a size cap before production.

Opened by REWORK 3:

30. **Nothing checks re-entry clearance any more.** With the board gone,
    a technician can open any face by typing its name. The gas-safety
    and re-entry gates that CLAUDE.md's integration contract relies on
    are not present in this app. Authorised, but the mine must decide
    where that check now lives.
31. **Face parameters are self-asserted.** Advance, peg and dimensions
    are typed rather than read from the blast record, so a typo is
    indistinguishable from a measurement. Confirm acceptable.

Opened by the dashboard:

32. **The dashboard reads the device store.** Management is not on the
    technician's tablet, so today it only shows what was captured on the
    device it is opened on. It is genuinely useful only once the Supabase
    path exists — `loadAll()` is the one function that changes.
33. **No shift or date filter.** It shows everything in the store. Once
    there is more than a shift or two of data it needs a range control and
    grouping by shift / section / technician.

Opened by the migration:

34. **`shift_type` has no source.** CLAUDE.md fixes shifts as A / B / C
    (6-on/3-off) and the schema has the column, but the field app
    hardcodes `shiftName:'Morning'` and never asks which of the three it
    is. Either the app collects it or the column goes. Do not backfill a
    guess — a wrong shift attribution on a statutory record is worse
    than a blank one.

Opened by seeding the dashboard:

35. **The 200 cm height flag misfires on decline headings.** It is a flat
    threshold, but the design cut is not: bord is 180 cm, so flagging at
    200 catches a face 20 cm over its cut — sensible. Decline is 250 cm,
    so **every decline face trips the flag even when it is exactly on
    cut**, and the management screen opens on flagged faces first. Either
    the flag is `design cut + 20` rather than a constant, or it only
    applies to bord headings, or 200 is right and the decline limits are
    wrong. Related to decision 12, which read the design cut as giving
    "exactly the 200 cm flag height" — that arithmetic works for bord and
    not for decline. Not changed: the flag is a mine threshold and moving
    it is a §7.3 ruling, not a refactor.

Opened by wiring the backend:

36. **Section is self-asserted, and section IS the RLS boundary.** A
    person picks their section at sign-up and the server believes them,
    because otherwise nobody could register and there is no MRM
    provisioning UI. Someone who types "16 North" can read 16 North.
    Every such row carries `section_source = 'self-declared'` so MRM can
    audit and correct it, but that is detection, not prevention. **This
    is the weakest point in the auth design.** It needs the ruling on
    decision 18 before production.
37. **E-mail confirmation must stay OFF, and there is no password
    reset.** Sign-in is by employee number, mapped to a reserved
    `…@geotech.unki.invalid` address that can never receive mail. So
    Supabase's own recovery flow cannot work, which turns decision 22
    from a gap into a certainty: a technician who forgets a password has
    no self-service route back in. Decide who resets it and how they
    verify who is asking.
38. **`limit_sets` is empty on the server.** The table is ready and the
    Chief Geologist's seed was deliberately not run, so `authorised_by`
    is a real person (§7.3). Meanwhile the app still uses its own
    client-side constants and snapshots them onto each record, so
    nothing is broken — but the server holds no authorised copy of the
    limits yet, and the two could drift. Seed it, then decide whether
    the app should read limits from the server rather than carry them.
39. **Nothing reconciles the handset against the server.**
    `offset_stat_drift` exists and will show any face where the two
    disagree, and nothing looks at it. Decide who does, and how often.

## When making changes

This is safety-critical software supporting a statutory geological
standard. Explain what you're changing and why before editing anything
that touches the gate chain, the R4 block, limit sets, RLS or the sync
queue. All diffs are reviewed before they ship.

This app is a data-capture and information tool. It does not replace
mine safety procedures, ground control, survey standards, formal hazard
reporting or competent-person interpretation. It is not an official Unki
Mine system unless formally authorised.
