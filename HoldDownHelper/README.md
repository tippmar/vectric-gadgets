# Hold Down Helper Gadget

This folder contains the Hold Down Helper gadget for Vectric CNC software products (VCarve Pro / Aspire). It finds
places on the active sheet where a screw can be driven into the spoilboard without being hit by a cutter later,
marks each one on a `Hold Down` layer, and creates a `Hold Down Dimples` drilling toolpath that dimples them with a
V-bit.

- Clearance tested against every visible vector on the active sheet, including grouped vectors
- Perimeter and field positions, nudged along their edge or outward when a position is blocked
- A report naming what blocked each position it could not place
- Settings remembered per unit system, including the chosen V-bit
- A Help page in the dialog covering the workflow, every setting, and the gotchas

See the [top-level README](../README.md#hold-down-helper) for the workflow and the gadget's limitations.

## Attribution

Original gadget, written for this repository. It shares no code with the Blum gadgets and does not depend on them.

Current maintenance and enhancements: Community contributors via this GitHub repository.

License terms: See `License.txt` in this directory. The gadget is provided "as-is" without warranty.

## Repository

This gadget is maintained at:

https://github.com/tippmar/vectric-gadgets

## Packaging / Deployment

Use the repository root `deploy.ps1` script to package this folder into a `.vgadget` archive for installation:

```powershell
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

The script derives the output gadget filename from the first `.lua` file it finds, so the archive is
`Hold_Down_Helper.vgadget` and installs as `Hold_Down_Helper`.

## Directory Overview

- `Hold_Down_Helper.lua` – The whole gadget: dialog, settings, safety test, placement, markers and toolpath
- `Help/HelpMain.xlua` – The Help button's page, loaded on demand
- `License.txt` – License and warranty disclaimer
