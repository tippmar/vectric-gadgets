# Box Joint Runs

A VCarve Pro V12.5 gadget that cuts a chain of 1 to 4 through-finger-jointed 90-degree
corners — open or closed — sized from stock thickness and width. It can also add finger
ends to an existing Blum Drawer Maker back (to cut a notch out of its middle) or to a
single existing square end, and it includes a test-cut mode that proves the joint on
scrap before you commit stock to a real run.

This gadget is separate from Blum Drawer Maker: it shares no code and no registry
settings with it. If you use both, enter matching stock and tool values in each.

See `docs/superpowers/specs/2026-09-27-box-joint-runs-design.md` in this repository for
the full design.

## Folder overview

- `Box_Joint_Runs.lua` — entry point and mode dispatch.
- `BoxJointDialog.xlua` — the settings dialog, tool pickers, and validation.
- `BoxJointGeometry.xlua` — the finger-end routine, piece drawing, and the four modes.
- `BoxJointToolpaths.xlua` — toolpath creation, layer association, recalculate, sequencing.
- `BoxJointRegistry.xlua` — settings persistence under the `BoxJointRuns` registry section.
- `Help/HelpMain.xlua` — the Help button's page.

## Packaging

From the repository root:

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

This writes `Box_Joint_Runs.vgadget` at the repository root. Install it through the
Vectric UI, or unpack it into
`C:\ProgramData\Vectric\VCarve Pro\V12.5\Gadgets\Box_Joint_Runs\`.

## Attribution

Box Joint Runs borrows its finger-joint math, layer/toolpath plumbing, and dialog
conventions from this repository's own Blum Drawer Maker gadget, which is itself based
on Easy Drawer Maker, originally written by JimAndi Gadgets of Houston, Texas, 2019.
