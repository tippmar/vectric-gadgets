# Hold Down Helper — design

Date: 2026-09-19
Status: approved for planning

## Problem

Screwing or nailing a full sheet to the spoilboard means guessing where a fastener will not
be hit by a cutter later. Getting it wrong destroys a bit, the part, or both, and there is no
feedback until the cut reaches the screw.

## Workflow this supports

1. Lay the sheet on the spoilboard and align it approximately.
2. Zero X and Y.
3. Run **only** the toolpath this gadget produces, with a V-bit. It marks shallow dimples.
4. Drive screws at the dimples.
5. Load and run the real job toolpaths, **without re-zeroing**.

Step 5 is load bearing: the dimples are in job coordinates, so a re-zero between steps 3 and
5 invalidates every one of them. The completion message says so.

## Scope

In scope: finding fastener positions clear of all cutting on the active sheet, drawing a
marker per position, and creating one drilling toolpath over those markers.

Out of scope: driving the fasteners, posting the toolpath, multi-sheet operation (active
sheet only), and proving that the material under a fastener stays attached to the sheet (see
Limitations).

## Files

```
HoldDownHelper/
    Hold_Down_Helper.lua     -- entry point; must begin with "-- VECTRIC LUA SCRIPT"
    Help/
        HelpMain.xlua        -- the Help button's page, loaded on demand
```

The code is a single file. The help page follows Blum Drawer Maker's pattern: a `Help/*.xlua`
file that builds the page's HTML, loaded with `loadfile` when the dialog's Help button is
pressed. The gadget shares no code with the two Blum gadgets and does not depend on
them. Packaged with the existing `deploy.ps1 -SourceFolder HoldDownHelper`.

## Safety test

A candidate point is **unsafe** if, for any qualifying vector on the active sheet, either:

- the vector is closed and `Contour:IsPointInside(point, tolerance)` returns true, or
- the minimum distance from the point to that vector is less than `R`

where

```
R = assumed tool diameter + (screw head diameter / 2) + margin
```

At the defaults (0.25 tool, 0.25 head, 0.125 margin) `R` is 0.5". The full tool diameter, not half of
it, is required because an outside profile runs the cutter center a half-diameter outside the vector, so
the cutter's far edge reaches a full diameter beyond the vector; `R` must cover that reach.

The inside test forbids fasteners through a part. The distance test forbids fasteners in the
band the cutter sweeps around a vector, and in a gap between two parts too narrow to take one.

### Why distance rather than offset contours

Offsetting every vector outward and testing containment was considered and rejected.
`Contour:IsPointInside` is documented as returning an undefined value for open contours, so
an offset-based test would mishandle any open vector on the sheet without saying so.
Distance is well defined for open and closed contours alike.

Distance is computed against `Contour:CreatePolygonizedCopy(GetDefaultContourTolerance())`
using point-to-segment math in Lua. Vectors whose bounding box is further than `R` from the
candidate are skipped without polygonizing, so the per-candidate cost stays proportional to
the vectors actually near it.

### Qualifying vectors

Every **visible** vector on the active sheet, on any layer, except those on the gadget's own
`Hold Down` layer. Visibility is the deliberate escape hatch: hiding a layer of part labels
or construction lines excludes it from the test, which is the documented way to recover
usable area when placement fails.

## Placement

Targets are computed first, then nudged if the safety test rejects them.

### Perimeter

Per side: `count = max(2, round(side_length / 16in))`, giving 3 per side on a 48" sheet and
scaling sensibly on a 48x96. Positions are at the `(i - 0.5) / count` fractions along the
side so none lands in a corner, inset from the sheet edge by `edge_inset` (default 1.25").

### Field

`field_count` targets (default 4) inside the center 50% of the sheet — the middle 24x24 of a
48x48. Four are placed at the quarter points of that region; six become a 2x3 grid. Counts
other than 4 and 6 are laid out as the nearest grid that fits, filling rows first.

### Nudging

A rejected target searches for a nearby safe point, and the search differs by target type:

- **Perimeter targets slide along their own edge**, alternating in `R / 2` steps to either
  side, up to `max_search` (default 3.0"). They never move inward. A perimeter fastener that
  wandered into the field is no longer holding the edge down, which is the job it was there
  to do.
- **Field targets spiral**, testing rings at `R / 2` intervals out to `max_search`, sampling
  8 angles per ring, taking the first safe point found.

A target with no safe point inside `max_search` is reported by coordinate and produces no
marker. It is never silently dropped.

## Output

- One circle of `marker_diameter` (default 0.125") per accepted position, on layer
  `Hold Down`.
- One drilling toolpath named `Hold Down Dimples` over that layer, using the V-bit chosen in
  the dialog, `StartDepth` 0, `CutDepth` = `dimple_depth` (default 0.1"), peck drilling off.
  VCarve drills at the center of each closed vector, which is the marker circle's center.
  `marker_diameter` sizes only that vector. The width of the dimple actually cut is set by
  the V-bit angle and `dimple_depth` — roughly 0.2" for a 90 degree bit at 0.1" deep.
- Home position and safe Z **must** be relative to `MaterialBlock()`: safe Z gap is the
  `safe_z_gap` setting (default 0.25", capped at 1") and home Z is `mtl_box.TRC.z + 2 * safe_z_gap`.
  The gap is a setting rather than a fraction of the thickness because the sheet is not yet
  fastened when the dimples are cut: it may bow or rock, and a first test cut at
  `thickness * 0.1` (0.05") dragged the V-bit between holes. Vectric's sample code hardcodes
  `5.0` here, which is 5mm in the metric sample it came from and 5 **inches** in an imperial
  job. That exact bug produced a rapid to Z+5.5 and a soft limit trip in Blum Drawer Maker.
- A completion message reporting positions placed, positions that could not be placed, and
  the do-not-re-zero warning.

## Re-running

The gadget clears the `Hold Down` layer and deletes any existing `Hold Down Dimples`
toolpath before rebuilding, so running it twice on a job is idempotent rather than
accumulating markers.

## Dialog and settings

| Setting | Imperial default | Metric default |
| --- | --- | --- |
| V-bit | tool picker, no default | — |
| Assumed tool diameter | 0.25 | 6.0 |
| Screw head diameter | 0.25 | 6.0 |
| Margin | 0.125 | 3.0 |
| Edge inset | 1.25 | 32.0 |
| Perimeter spacing target | 16.0 | 406.4 |
| Field count | 4 | 4 |
| Max nudge search | 3.0 | 76.2 |
| Dimple depth | 0.1 | 2.5 |
| Marker diameter | 0.125 | 3.0 |
| Safe Z gap | 0.25 | 6.0 |

Persisted to the registry and restored on open, following the pattern in
`BlumDrawerRegistry.xlua`. Unit handling follows the existing `Drawer.Cal` convention
(1.0 imperial, 25.4 metric).

## Error handling

- No job open, or no vectors on the active sheet: message and exit without changes.
- No V-bit chosen: message and exit without changes.
- Sheet smaller than 24x24: proceed, but warn that the gadget is intended for large sheets.
- Every position rejected: draw nothing, delete nothing, and report why.

## Limitations, stated rather than hidden

**Waste islands are not detected.** Clearance from every vector does not prove the material
under a fastener stays attached to the sheet. A region fully enclosed by cut lines comes free
during the job, and a screw in it is worse than no screw — it releases a loose piece under a
spinning cutter. Solving this needs connectivity analysis over the cut regions and is
deliberately deferred. The user is told to look at the marker positions before drilling.

**One tool diameter is assumed for the whole sheet.** A job mixing a 1/8" and a 1/4" bit is
tested as though the 1/4" ran everywhere. This loses usable area and never errs toward danger.

**Toolpaths are not read.** The test is driven by vectors, so a vector with no toolpath on it
still blocks placement, and a toolpath whose vector was deleted does not.

**Toolpath extras are not modeled.** Lead-ins, ramps, overcuts and machining allowances can move
the cutter beyond anything `R` accounts for. Raise the margin to cover them.

## Risks

- `CreateDrillingToolpath` has a documented SDK sample but has not been exercised in this
  repo. Its behavior with a V-bit, and whether VCarve objects to a marker circle smaller or
  larger than the tool, is unverified.
- Nothing in this repo can be run or tested locally. Every change is packaged, installed and
  tested by the user in VCarve.
