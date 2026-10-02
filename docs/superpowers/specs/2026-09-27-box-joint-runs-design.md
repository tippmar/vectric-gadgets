# Box Joint Runs — design

Date: 2026-09-27
Status: approved for planning

## Problem

Some builds need a run of finger-jointed 90° corners of arbitrary length: pieces joined end to end, each
corner a through finger joint, the run either open (an L or U) or closed (a four-sided frame).

The immediate driver: drawer boxes built with Blum Drawer Maker need a U-shaped notch in the back to clear
plumbing under a vanity sink. In plan view:

```
  side ┃━━━━━┓       ┏━━━━━┃ side     ← existing back, middle removed
       ┃     ┃ notch ┃     ┃
       ┃     ┗━━━━━━━┛     ┃          ← 3 new pieces: notch side, notch front, notch side
       ┃                   ┃
       ┃━━━━━━━━━━━━━━━━━━━┃ front
```

The backs are already cut. The existing back becomes two stubs that still sit in the side dados; the run is
stub → notch side → notch front → notch side → stub. The gadget must therefore both cut new pieces and add
finger ends to a piece that already exists.

## Scope

In scope:

- a chain of 1 to 4 new pieces, open or closed, with through finger joints at every corner;
- adding finger ends to an existing Blum back (removing its middle) or to a single existing end;
- a test cut that proves the joint on scrap;
- an optional through bottom groove on new pieces, matching a Blum back's bottom dado.

Out of scope: blind joint styles, corners other than 90°, pieces of differing width or thickness, the bottom
panel (cut with its U removed separately), quantity, cut lists, and profile import/export.

This is a separate gadget. It copies what it needs from Blum Drawer Maker and shares no code or registry
settings with it.

## Files

```
BoxJointRuns/
    Box_Joint_Runs.lua        -- entry point and mode dispatch; must begin with "-- VECTRIC LUA SCRIPT"
    BoxJointDialog.xlua       -- the HTML dialog, tool pickers and validation
    BoxJointGeometry.xlua     -- the finger end, pieces, and the four modes' drawings
    BoxJointToolpaths.xlua    -- toolpath creation, layer association, recalculate and sequencing
    BoxJointRegistry.xlua     -- settings read/write under the BoxJointRuns registry section
    Help/
        HelpMain.xlua         -- the Help button's page
    License.txt               -- as the other gadgets ship
    README.md                 -- attribution, packaging and folder overview
```

Packaged with `pwsh ./deploy.ps1 -SourceFolder BoxJointRuns` into `Box_Joint_Runs.vgadget`. The repository
README gains a table row and a section.

## Shared settings

These apply to every mode.

- **Stock:** thickness T; width W, the dimension the fingers run across (a drawer's height).
- **Finger count:** automatic by default, or a manual count behind an override checkbox.
  - Automatic is Blum Drawer Maker's `AutoFingerCount`: round(W / 1 inch), capped so the finger width is
    at least finger bit diameter / 0.70, and never below 3.
  - Finger width is W / n.
  - Finger depth is T, since all pieces share one thickness.
- **Joint style:** Through, Dog Bone, or T-Bone. Blind styles are excluded, so any piece can be flipped
  face for face.
- **Finger clearance**, applied as Blum Drawer Maker applies it.
- **Bottom groove:** on/off, inset from the bottom edge, width, depth, and which way it faces once folded (Inside or Outside).
- **Tools:** profile bit, finger bit, finger clear bit, dado bit; the finger, dado and profile finish passes each take an allowance as in Blum
  Drawer Maker; part gap; profile tabs; optional profile finishing pass.
- **Mode:** Chain, Existing back, Existing end, or Test cut.

## The phase rule

Every finger end is one of two phases, named by what sits at the piece's **bottom (groove) edge**:

- **Finger at bottom**: band 0 (at the bottom edge) is a finger.
- **Gap at bottom**: band 0 is a gap.

W is divided into n bands of width W / n, counted from the bottom edge. Alternate bands are fingers and
gaps. Two mating ends are always opposite phases. Because phase is measured from the bottom edge, a stub
end and a new piece line up whichever way either is lying on the machine.

## Modes

### Chain

- Rows for Pieces 1 to 4. Each row has an enabled checkbox and an overall length, tip to tip including
  fingers. Piece 1 is always enabled; Piece N can be enabled only while Piece N−1 is.
- At each internal joint the earlier piece's end is **finger at bottom** and the later piece's end is
  **gap at bottom**.
- **Start of Piece 1** and **end of the last piece** each have a dropdown: None (plain square end),
  Finger at bottom, or Gap at bottom.
- **Close loop** is offered only with 4 pieces enabled. It joins the end of Piece 4 to the start of Piece 1
  using the internal-joint rule, and replaces both end dropdowns. It warns, without blocking, when
  Piece 1 ≠ Piece 3 or Piece 2 ≠ Piece 4.

For the U-notch, the three notch pieces are a 3-piece chain whose start and end dropdowns are set opposite
to the phase chosen for the stub ends.

### Existing back

Setup, fixed by the Blum back's shape (its bottom corners carry the Blum runner cutouts, so neither bottom
corner can be the zero):

- the back lies with its **bottom edge away from the operator**, so its top edge runs along Y = 0;
- zero is the operator's lower-left corner, which is the back's top-right corner;
- X runs along the back's top edge.

Inputs, all in the machine frame:

- back length;
- first stub length, from zero to the first cut end;
- notch opening, between the two cut ends (equals the notch front piece's overall length);
- phase of the stub ends.

The gadget profiles out the middle — from first stub length to first stub length + opening — as a rectangle,
inside, full depth, with no tabs, and pockets the gap bands behind each new end. The middle comes loose; the
operator screws it down. No groove is cut: the back already has one.

### Existing end

For an end that is already cut square.

- The end being cut is always at X = 0, with zero at that end's corner.
- Input: bottom edge **toward** the operator (on Y = 0) or **away** (on Y = W). The right-hand stub is
  handled by turning it end for end; the gadget mirrors the pattern, so nothing is drawn at negative X.
- Input: phase.

Only the finger pockets are cut. There is no profile and no groove.

### Test cut

Two short stubs at the real W, so the finger count and finger width match production: one with a
**finger at bottom** end, one with a **gap at bottom** end, each about 3 inches long, with the groove when
the groove is on. Drawn and machined like Chain pieces.

## Geometry

- Pieces lie along X. Chain and Test cut pieces have their bottom edge on Y = 0; Existing back has it on
  Y = W; Existing end has either, per its toward/away input.
- **One finger-end routine** draws every finger end, given the end's corner, the direction into the piece,
  which side the bottom edge is on, and the phase. All four modes call it.
- Each gap band is pocketed T deep into the piece from its end. It overshoots past the end, and past the
  long edge when the gap sits on an edge, as Blum Drawer Maker's pockets do. Dog Bone and T-Bone reliefs sit
  at each gap's inside corners exactly as Blum Drawer Maker draws them.
- **Chain and Test cut pieces:** the profile outline is a plain L × W rectangle. The finger pockets clear
  the gaps; the profile trims the finger tips. Tabs go on the long edges, since the ends carry fingers.
- **Groove:** a through dado on the top face at its inset from the bottom edge, running the full length
  plus the dado bit radius at each end, as on a Blum back. New pieces only.
- **Outside grooves:** when the grooves face outside, the finger that holds the bottom band would block the
  mating groove short of the corner. Every finger-at-bottom end at a joint between two new pieces
  (including the close-loop joint and Test cut) then gets a through pocket on the Fingers layer
  at the groove's inset and width, from past the end line to the groove depth plus the finger bit radius in. Start/End
  ends and the Existing modes never get it: they meet a Blum back at an inside corner, where it would show.
- **Layers:** Profile, Fingers, Groove and Labels, named with the thickness tag Blum Drawer Maker uses.
  Existing modes use separate layers (for example, `BJR Existing Fingers`).
- **Labels:** each new piece is labeled, for example "Run – Piece 2 (L × W × T)".

## Placement

- **Chain and Test cut** follow Blum Drawer Maker: parts go on a sheet named for the thickness, laid out
  with the part gap, to the right of anything already there, so repeated runs build up a batch and can sit
  beside Blum parts.
- **Existing back and Existing end** draw at the origin of the active sheet, on their own layers. A re-run
  of either replaces that mode's geometry and toolpaths on the active sheet rather than stacking on top.
  Chain geometry is never touched.

## Toolpaths

| Toolpath | Layer | Tool | Notes |
|---|---|---|---|
| Fingers | Fingers | Finger bit, finger clear bit | Two-tool pocket, through depth, with pocket allowance: the clear bit roughs (VCarve adds a `[Clear]` partner), the finger bit finishes. When both pickers hold the same bit, it runs single-tool |
| Groove | Groove | Dado bit | Pocket to groove depth; Chain and Test cut only |
| Profile | Profile | Profile bit | Outside with tabs for pieces; inside, no tabs, for existing-back waste |
| Profile finish | Profile | Profile bit | Optional finishing pass; pieces only |

- Every toolpath is associated with its layer.
- A later run on the same thickness sheet recalculates an existing toolpath instead of creating a duplicate.
- After each run, toolpaths are re-sequenced by tool: clearance first, then other cuts, then profiles.
- Existing modes use their own toolpath names (for example, `BJR Existing Fingers`).

## Validation

Copied from Blum Drawer Maker where it exists:

- finger width ≥ finger bit diameter / 0.70;
- every chosen bit's units match the job units;
- the profile bit is smaller than the part gap;
- every piece length is greater than 2T, so its two finger ends cannot overlap;
- Existing back: first stub length > T, opening > 0, and first stub length + opening + T < back length.

Each failure explains itself and returns to the dialog.

## Settings persistence

Every setting — the mode, chain rows, end dropdowns, existing-mode inputs and tools — is stored under the
gadget's own `BoxJointRuns` registry section. Nothing is read from Blum Drawer Maker's registry; the user
enters matching values on first run.

## Help

A Help button opens a page covering: the phase labels and how to tell them apart on a board in hand; the
Existing back setup (rotated board, where to zero, screw down the waste); turning a right-hand stub end for
end in Existing end mode; and that the bottom panel is cut separately.

## Verification

Nothing in this repository runs locally. Each implementation task ends with the user packaging the gadget
and running it in VCarve Pro V12.5. Test cut mode is built first, to prove the finger-end geometry and
toolpaths on scrap before the other modes build on them.
