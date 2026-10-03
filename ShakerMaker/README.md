# Shaker Maker

A VCarve Pro V12.5 gadget that carves a shaker look into a solid slab, such as MDF: the center panel is
recessed and the rails and stiles are left standing as a raised frame. It draws the parts and creates their
toolpaths. The dialog's **Help** button covers every setting.

- **Panel edge**: straight (square wall, corners at the radius of the smallest clearing bit) or V-bit (beveled
  wall with sharp corners, cut by a flat-bottomed V-carve).
- **Bit geometry**: the V-bit's bevel is `depth x tan(angle / 2)` wide. Rail and stile widths are measured to the
  bottom of the bevel (the frame, bevel included, is the entered width) or to the top of it (the flat face is).
- **Middle stile**: optional, for tall doors; a stile-wide member centered top to bottom, giving two equal panels.
- **Several clearing bits**: a bulk bit, as large as the floor allows, clears the panel; up to two smaller corner
  bits each pocket a square in every floor corner to take out the round the bit before them left.
- Parts go on a sheet named for their thickness, right of anything already drawn, so repeated runs build up a
  batch; toolpaths are layer-associated and recalculated rather than duplicated, and sequenced by tool.

This gadget shares no code or registry settings with the other gadgets in this repository.

## Folder overview

- `Shaker_Maker.lua`: entry point, panel geometry (`RecomputeDerived`) and validation.
- `ShakerDialog.xlua`: the settings dialog and tool pickers.
- `ShakerGeometry.xlua`: sheet handling, drawing helpers, and the parts themselves.
- `ShakerToolpaths.xlua`: pocket, V-carve and profile toolpaths; layer association, recalculation, sequencing.
- `ShakerRegistry.xlua`: settings persistence under the `ShakerMaker` registry section.
- `Help/HelpMain.xlua`: the Help button's page.

## Packaging

From the repository root:

```powershell
pwsh ./deploy.ps1 -SourceFolder ShakerMaker
```

This writes `Shaker_Maker.vgadget` at the repository root.

## Attribution

Shaker Maker borrows its dialog look, sheet handling and toolpath plumbing from this repository's Box Joint Runs and
Blum Drawer Maker gadgets; the latter is based on Easy Drawer Maker, originally written by JimAndi Gadgets of
Houston, Texas, 2019.
