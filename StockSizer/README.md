# Stock Sizer Gadget

This folder contains the Stock Sizer gadget for Vectric CNC software products (VCarve Pro / Aspire). It finds the
bounding box of every visible vector on the active sheet, adds a margin for the cutter, and reports the size of
stock the job needs. It can then resize the sheet to that size, so a job can be drawn on a full 48 x 48 sheet and
the stock size read off afterward.

- Margin is the tool diameter plus an extra allowance, on every side
- Optional round-up to 1/8, 1/4, 1/2 or 1 inch (1, 5, 10, 25 or 50 mm in a metric job)
- Report-only mode, and a confirmation dialog before any resize, because VCarve cannot undo a sheet size change
- The sheet keeps its lower-left corner and the vectors do not move; a warning shows when vectors are closer than the
  margin to the left or bottom edge
- Settings and dialog size remembered per unit system
- Help and About buttons

## Attribution

Original gadget, written for this repository. It shares no code with the Blum gadgets and does not depend on them.

Current maintenance and enhancements: Community contributors via this GitHub repository.

License terms: See `License.txt` in this directory. The gadget is provided "as-is" without warranty.

## Repository

This gadget is maintained at:

https://github.com/tippmar/vectric-gadgets

## Packaging / Deployment

```powershell
pwsh ./deploy.ps1 -SourceFolder StockSizer -Force
```

The archive is `Stock_Sizer.vgadget` and installs as `Stock_Sizer`.

## Directory Overview

- `Stock_Sizer.lua` – The whole gadget: dialogs, bounds, margin, rounding and the resize
- `Help/HelpMain.xlua` – The Help button's page, loaded on demand
- `License.txt` – License and warranty disclaimer
