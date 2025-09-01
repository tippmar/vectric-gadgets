# Blum Drawer Maker Gadget

This folder contains the Blum Drawer Maker gadget for Vectric CNC software products (Aspire / VCarve, etc.). The gadget streamlines design and toolpath generation for custom Blum-style drawer components, automating:

- Parametric sizing (width / height / depth) with gap allowances
- Joinery selection (finger joints, blind/through variants, captive bottoms, etc.)
- Milling settings (tools, clearances, dado configurations, soft-close drilling options)
- Automated layer creation, vector generation, and toolpath processing
- Export / import of drawer configuration profiles
- Bill of materials and supporting images/help content

## Attribution

Original concept and implementation: EasyDrawerMaker Gadget by [JimAndIGadgets](https://www.gadgets.jimandi.com/details.php?details=124)

Current maintenance and enhancements: Community contributors via this GitHub repository.

License terms: See `License.txt` in this directory. The gadget is provided "as-is" without warranty.

## Repository

This gadget is now maintained at:

https://github.com/tippmar/vectric-gadgets

## Packaging / Deployment

Use the repository root `deploy.ps1` script to package this folder into a `.vgadget` archive for installation:

```powershell
pwsh ./deploy.ps1 -SourceFolder BlumDrawerMaker -Force
```

The script derives the output gadget filename from the first `.lua` file it finds.

## Directory Overview

- `Blum_Drawer_Maker.lua` – Main entry point and orchestration logic
- `BlumDrawerDialog.xlua` – UI dialog definitions and event handlers
- `BlumDrawerTools.xlua` – Calculation, geometry, and path assembly helpers
- `BlumDrawerJoinery.xlua` – Joinery generation and toolpath logic
- `BlumDrawerImages.xlua` – Image registration / references
- `BlumDrawerRegistry.xlua` – Persistence (registry / settings IO)
- `Help/` – Help pages and images bundled with the gadget
- `License.txt` – License and warranty disclaimer

## Contributing

Pull requests are welcome. Suggested contribution areas:

- Additional joinery options or hardware hole patterns
- Improved error handling and diagnostics
- Unit or regression tests for geometry math (if a test harness is introduced)
- Documentation refinements / screenshots

## Support / Issues

Open an issue on the GitHub repository with:

- Vectric product & version
- Gadget version (commit hash or package date)
- Steps to reproduce
- Log or error dialog details

## Disclaimer

The gadget is provided without any express or implied warranty. Use at your own risk. Always preview toolpaths and verify machining parameters before running a job.
