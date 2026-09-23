# Clearance reference — Blum Drawer Maker

How the fit settings and the pocket allowances relate, and the arithmetic behind the numbers.
Derived 2026-09-19/20 from caliper measurements of real cuts.

**The machine errors below belong to one machine and two specific bits, and they drift as a
bit dulls.** Take the method rather than the numbers: measure a cut of your own, then work it
through the same formulas.

All values in inches. Sign convention for pocket allowance, confirmed against Vectric's docs:
positive leaves material, negative enlarges the pocket, and **the value is applied to each
side of the pocket equally** — so the total width change is `2 x allowance`.

## Measured machine error

Both measured on real cuts, not assumed. Per-bit; changes with sharpening or bit replacement.

| Bit | Evidence | Total | Per side |
| --- | --- | --- | --- |
| Dado (MillTool2) | drawn 0.495 -> cut 0.475 | 0.020 | 0.010 |
| Finger (MillTool4, 1/8") | drawn finger 0.9861 -> cut 1.0001 | 0.0140 | 0.0070 |

A pocket cutting narrow makes the notch narrow **and** the material between notches wide.
That is why the error counts twice in a finger joint and once in a dado.

## Dados

Groove is drawn at `panel_thickness + C`. The bottom grooves use `Drawer.BottomThickness`
with `C = DadoClearance`; the groove in the sides that holds the back panel uses
`Drawer.PanelThickness` with `C = BackDadoClearance`, split out 2026-09-20 because the two
joints want different fits. Both are cut by the same bit, so they share one allowance.

```
cut = drawn - 0.020 - 2a
fit = C - 0.020 - 2a
```

### In-progress job (0.490 panel, DadoClearance 0.005, 0.2415 bottom entered as 0.250)

| Toolpath | Cuts | Allowance | Fit |
| --- | --- | --- | --- |
| Front Dado, Back Dado | bottom groove only | -0.009 | 0.0115 |
| Side Dado | bottom groove AND back groove | -0.010 | 0.0135 bottom / 0.005 back |

Side Dado is a compromise because a single toolpath cuts two different groove widths. That
only happens because the bottom thickness was entered 0.0085 over its measured size; with
measured thicknesses the allowance is panel-independent and one value serves every dado.

### Going forward

- With `PocketAllowance`: allowance **-0.010** (cancels the machine), `DadoClearance`
  **0.012** and `BackDadoClearance` **0.004** (carry the fits). Canceling the machine
  reduces the relation to `fit = C`, so each setting reads as the fit it produces.
- Without it: add the machine error to each -- `DadoClearance` **0.032**,
  `BackDadoClearance` **0.024**. Identical cut, but the settings stop meaning what their
  names say, and a bit change breaks every job at once.

## Finger joints

`pitch = Drawer.Height / finger_count`. `MySideFingers` moves each notch edge out by
`FingerClearance / 2`, so drawn finger is `pitch - C` and drawn notch is `pitch + C`.

```
fit = 2C - 2E - 4a          E = 0.0140, a negative
```

Verified: opening height 7.75 -> `Drawer.Height` 6.9375 -> `AutoFingerCount` 7 -> pitch
0.99107. Drawn finger `0.99107 - 0.005 = 0.9861`, matching the measured part exactly,
which confirms both the finger count and the symmetric application of C.

| Setup | C | a | Fit |
| --- | --- | --- | --- |
| As cut (needed a hammer) | 0.005 | 0 | -0.018 |
| Interim fix, no allowance | 0.016 | 0 | 0.004 |
| Clean split | 0.002 | -0.0070 | 0.004 |

`-0.0070` is exactly `E/2`, which cancels the machine error and reduces the relation to
`fit = 2C`.

## Profile deflection and the finishing pass

Finding (2026-09-22, from test cuts): a finger joint that is off size is not always machine
error that an allowance can cancel. On the side and front profiles the bit runs in air
between the fingers, then bites into each finger end and deflects. How much it deflects
depends on how much material it meets, so it is not a constant offset, and neither an
allowance nor a clearance cancels it reliably. A finger-depth ("recess") setting was tried
and dropped for the same reason: it moved the tip, not the deflection.

`ProfileFinishAllowance` (Milling menu, default 0 = off) splits the side and front profiles
into two toolpaths:

```
<Side|Front>-Profile (t)          roughing, Allowance = ProfileFinishAllowance, tool stepdown
<Side|Front>-Profile (t) Finish   Allowance = 0, full depth in one pass
```

Both use the same vectors, tool and tabs. The finishing pass takes an even skin of
`ProfileFinishAllowance`, so the load, and with it the deflection, is small and uniform.
Back and bottom profiles have no fingers and stay single-pass.

- Start at 0.010 to 0.020 in (0.25 to 0.5 mm).
- Turn this on **before** retuning `FingerAllowance`. Values tuned without it may have been
  absorbing part of the deflection, and will read differently once it is gone.
- Existing toolpaths keep their old passes when recalculated. Delete and regenerate them after
  changing it.

## Superseded advice

- A finger allowance of **-0.012** was given for the in-progress job, on an explicit
  instruction to assume the dado bit's 0.020, because the job could not stop for a test cut.
  The real finger-bit error is 0.0140, so that job's joints land at `2(0.005) - 2(0.0140) +
  4(0.012)` = **0.030** — loose with visible gaps, not scrap.
- An earlier single global `PocketAllowance` was proposed before the two bits were measured
  separately. Superseded: dado and finger need independent values.

## Target fits

- Drawer bottom in its groove: 0.011 to 0.015 total. Captive on four sides, wants to float.
- Back panel in its groove: 0.003 to 0.005 total. Glued, wants to be snug.
- Finger joint: 0.004 total for a snug slip fit assembled by hand.

## Sensitivity

- Dado: 0.001 of allowance moves the fit 0.002.
- Finger: 0.001 of allowance moves the fit 0.004, and 0.001 of `FingerClearance` moves it
  0.002. Do not round casually.

## Standing principle

Allowance cancels machine error; `DadoClearance` and `FingerClearance` carry the fit. Once
that split is in place, a bit change or resharpen only requires retuning the allowance, and
every fit setting keeps meaning what its name says.
