# vectric-gadgets

Gadgets for use with Vectric CNC software, developed and tested against **VCarve Pro V12.5**.

| Gadget | Folder | What it does |
|---|---|---|
| Blum Drawer Maker | [`BlumDrawerMaker/`](BlumDrawerMaker/) | Designs drawer boxes for Blum under-mount slides: draws the parts and creates their toolpaths. |
| Blum Nesting Repair | [`BlumNestingRepair/`](BlumNestingRepair/) | Run after nesting to fix toolpaths that nesting left behind on the wrong sheets. |
| Hold Down Helper | [`HoldDownHelper/`](HoldDownHelper/) | Finds places to screw a sheet to the spoilboard where no cutter will reach, and dimples them with a V-bit. |

The two are meant to be used in sequence: build drawers with Blum Drawer Maker, nest the job, then run Blum Nesting Repair to put the toolpaths back in order.

## Blum Drawer Maker

Draws the sides, back, front and bottom for a Blum under-mount drawer box and creates the pocketing and profiling toolpaths to cut them. See [`BlumDrawerMaker/README.md`](BlumDrawerMaker/README.md) for the parametric options, joinery choices and directory layout.

Beyond drawing the parts, it:

- puts parts for each material thickness on a sheet named for that thickness, placed in open space to the right of anything already drawn, so the gadget can be run repeatedly in one file to build up a batch of drawers;
- associates every toolpath it creates with the layer its vectors live on, so the toolpath picks up new parts when it is recalculated;
- recalculates an existing toolpath rather than creating a duplicate when a later run uses the same material thickness;
- orders the toolpaths to minimize tool changes — clearance passes first, then other cuts, then profiles, with toolpaths sharing a tool kept together;
- holds parts in the sheet with tabs while the profile pass cuts them free, placing them on the two edges of each part that carry no finger joints;
- separates joint fit from machine error: the clearance settings say how a joint should fit, and a pocket allowance per bit cancels a cutter that comes out over or under size (see [`docs/clearance-reference.md`](docs/clearance-reference.md));
- can cut a test pair instead of a drawer — one side stub and one front stub, at the real drawer height so the finger count and finger width match production — to prove the joint on an offcut before committing a sheet;
- writes a cut list.

## Blum Nesting Repair

A toolpath belongs to exactly one sheet, and `Toolpath.SheetId` is read-only. So when nesting moves parts onto a new sheet:

- **parts on the new sheet have no toolpaths**, and Recalculate All will not create them; and
- **toolpaths whose parts all moved away are left empty**, and warn on Recalculate All.

This gadget fixes both. For every toolpath that uses layer association, it gives each sheet holding parts on those layers a copy of the toolpath, and deletes each copy sitting on a sheet with no parts left on its layers. Copies are made from a template of the existing toolpath, so the tools and settings you chose carry over. It then recalculates every toolpath in the job — nesting also leaves the surviving toolpaths pointing at vectors that have moved, and adding the missing ones does not refresh those — and re-sequences them by tool.

It is generic: it handles any toolpath using the **Associate with toolpath** geometry selection, not only ones Blum Drawer Maker creates.

It shows you the planned additions and removals before changing anything.

> **While it runs, VCarve asks "Do you want to apply the template to all sheets?" once per toolpath added. Answer No every time.** The gadget's confirmation dialog says how many prompts to expect. `LoadToolpathTemplate` has a single overload with no way to suppress the prompt, and it is the only API that can place a toolpath on a chosen sheet, so the prompts are unavoidable. Answering Yes copies toolpaths onto sheets that should not have them.

## Hold Down Helper

Screwing a full sheet to the spoilboard means guessing where a fastener will not be hit by a cutter later.
Getting it wrong destroys a bit, the part, or both, and nothing tells you until the cut reaches the screw.

This gadget finds positions on the active sheet that are clear of everything being cut, marks each one with a
circle on a `Hold Down` layer, and creates a single `Hold Down Dimples` drilling toolpath over those markers.

The workflow it supports:

1. Lay the sheet on the spoilboard and align it approximately.
2. Zero X and Y.
3. Run **only** the toolpath this gadget produces, with a V-bit. It marks shallow dimples.
4. Drive screws at the dimples.
5. Load and run the real job toolpaths, **without re-zeroing**.

> **Step 5 is load bearing.** The dimples are in job coordinates, so re-zeroing between steps 3 and 5
> invalidates every one of them.

A position is rejected if it falls inside any closed vector, or if it comes within `R` of any vector, where
`R` is the assumed cutter diameter plus half the screw head diameter plus a margin — 0.5" at the defaults.
The full cutter diameter, not half of it, is required because an outside profile's cutter reaches a full
diameter beyond the vector it cuts. Rejected perimeter positions slide along their own edge, never inward;
rejected field positions spiral outward. A position with nowhere safe to go is reported by coordinate rather
than silently dropped.

The completion message states the `R` in use and, for each position it could not place, names the layer and
extent of the vector that blocked it. When far more positions are rejected than expected, check the margin
first: `R` grows with it, and a test value left in the dialog is remembered between runs, as is the chosen
V-bit.

Every **visible** vector on the active sheet is tested, on any layer. Hiding a layer excludes it, which is the
way to recover usable area when too many positions are rejected: hide part labels or construction lines, not
the parts themselves.

Grouped vectors are read member by member. Objects with no outline, such as text that has not been converted
to curves, are listed in a warning rather than silently ignored.

Re-running replaces the active sheet's markers and toolpath rather than adding to them.

What it does not do:

- **It does not detect waste islands.** Clearance from every vector does not prove the material under a
  fastener stays attached to the sheet. A region fully enclosed by cut lines comes free during the job, and a
  screw in it releases a loose piece under a spinning cutter. Look at the positions before drilling.
- **It assumes one tool diameter for the whole sheet.** A job mixing a 1/8" and a 1/4" bit is tested as though
  the 1/4" ran everywhere. That loses usable area and never errs toward danger.
- **It does not read toolpaths.** A vector with no toolpath on it still blocks placement, and a toolpath whose
  vector was deleted does not.
- **It does not model toolpath extras.** Lead-ins, ramps, overcuts and machining allowances can reach beyond
  `R`; raise the margin to cover them.
- **It works on the active sheet only.** Re-running removes only the active sheet's markers and
  `Hold Down Dimples` toolpath; markers and toolpaths on other sheets are left alone.

Do not draw on the `Hold Down` layer: re-running removes everything on it for the active sheet.

The chosen V-bit is remembered as a snapshot; after editing its feeds in the tool database, pick it again.

## Installing

Install a `.vgadget` file through the Vectric UI, or unpack it into:

```
C:\ProgramData\Vectric\VCarve Pro\V12.5\Gadgets\<Gadget_Name>\
```

Reinstalling replaces the previous copy.

## Packaging

`deploy.ps1` packages a gadget folder into a `.vgadget` archive at the repository root. The output filename comes from the first `.lua` file in the folder.

```powershell
pwsh ./deploy.ps1                                    # Blum_Drawer_Maker.vgadget (the default)
pwsh ./deploy.ps1 -SourceFolder BlumNestingRepair    # Blum_Nesting_Repair.vgadget
```

Add `-Force` to overwrite an existing archive without being asked. `*.vgadget` is gitignored.

## Writing gadgets

- A gadget script **must** start with the line `-- VECTRIC LUA SCRIPT`, or VCarve refuses to run it.
- The Vectric Gadget SDK, which contains the Lua interface documentation and samples, is at
  <https://storage.vectric.com/gadgets/V12/Vectric_Gadget_SDK.vgadget>.
- The SDK documentation is incomplete. Some of what these gadgets rely on — the `GeometryFilterUsed` flag behind the "Associate with toolpath" checkbox, `ReorderToolpathList`, `CopyToolpathWithId` — is undocumented. A reliable way to recover a real signature is to call the method with no arguments inside `pcall`: the luabind error lists every overload.

## Disclaimer

Gadgets are an entirely optional add-in to Vectric's core software products. They are provided *as-is*, without any express or implied warranty, and you make use of them entirely at your own risk. In no event will the authors or Vectric Ltd. be held liable for any damages arising from their use.

Always preview toolpaths and verify machining parameters before running a job.
