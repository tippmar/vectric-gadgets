# vectric-gadgets

Gadgets for use with Vectric CNC software, developed and tested against **VCarve Pro V12.5**.

| Gadget | Folder | What it does |
|---|---|---|
| Blum Drawer Maker | [`BlumDrawerMaker/`](BlumDrawerMaker/) | Designs drawer boxes for Blum under-mount slides: draws the parts and creates their toolpaths. |
| Blum Nesting Repair | [`BlumNestingRepair/`](BlumNestingRepair/) | Run after nesting to fix toolpaths that nesting left behind on the wrong sheets. |

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
