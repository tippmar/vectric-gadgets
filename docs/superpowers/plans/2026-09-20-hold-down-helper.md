# Hold Down Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A VCarve gadget that finds fastener positions clear of all cutting on the active sheet, marks each one with a circle, and creates a drilling toolpath that dimples them with a V-bit.

**Architecture:** One Lua file, `HoldDownHelper/Hold_Down_Helper.lua`, following the shape of `BlumNestingRepair/Blum_Nesting_Repair.lua`: a `main(script_path)` entry point, globals declared at the main chunk, everything else plain global functions. Settings live in one `HoldDown` table, persist to the registry, and are edited in a single `HTML_Dialog`. Placement is computed in two phases — ideal targets first, then a per-target nudge search when the safety test rejects one — and the safety test itself is point-to-segment distance against polygonized copies of every qualifying vector, with a bounding-box pre-reject.

**Tech Stack:** Lua 5.1 as hosted by VCarve Pro V12.5, the Vectric Gadget Lua API, `deploy.ps1` for packaging.

**Spec:** [`docs/superpowers/specs/2026-09-19-hold-down-helper-design.md`](../specs/2026-09-19-hold-down-helper-design.md) — read it before Task 1. This plan argues from that spec and does not repeat its reasoning.

## Global Constraints

- **The file must begin with the exact line `-- VECTRIC LUA SCRIPT`**, or VCarve refuses to run it.
- **Line endings are LF** for this file, matching `BlumNestingRepair/Blum_Nesting_Repair.lua`. (The `BlumDrawerMaker/*.xlua` sources are CRLF; do not copy that here. `sed`/`awk` in this environment strip CR — use `perl` if you ever edit a CRLF source.)
- **American spelling everywhere** — code, comments, dialog copy, docs, commit messages.
- **Single file.** `HoldDownHelper/Hold_Down_Helper.lua` and nothing else in that folder. No shared code with the Blum gadgets.
- **`require "strict"` is in force.** Every global must be assigned at the main chunk before any function reads it. Function definitions at the main chunk are fine.
- **Home position and safe Z must be derived from `MaterialBlock()`** — never a hardcoded number. See Task 7.
- **Target platform is VCarve Pro V12.5.** Nothing in this repo can be run or tested locally; every task ends with the developer packaging the gadget and the user running it in VCarve.
- **Units:** `HoldDown.Cal` is `1.0` in an imperial job and `25.4` in a metric one, set from `MaterialBlock().InMM`, exactly as `GetMaterialSettings()` does at `BlumDrawerMaker/BlumDrawerTools.xlua:1379`. Registry values are stored in **job units**, not normalized to mm, and each unit system has its own hardcoded default table — this is the convention `BlumDrawerRegistry.xlua` follows and this gadget follows it too.
- **Packaging command:** `pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force`, run from the repository root. It writes `Hold_Down_Helper.vgadget` at the root, named after the first `.lua` file in the folder. `*.vgadget` is gitignored.
- **Installing for a test run:** install the `.vgadget` through the Vectric UI, or unpack it into `C:\ProgramData\Vectric\VCarve Pro\V12.5\Gadgets\Hold_Down_Helper\`. Reinstalling replaces the previous copy.
- **VCarve's paste bug:** toolpath and dialog form fields discard pasted values. When the user is asked to enter a number during a test, they must **type it and tab out**, not paste it.
- **Recovering an unknown API signature:** call the method with no arguments inside `pcall`; the luabind error message lists every overload. This is the documented technique in the root `README.md` and Task 2 depends on it.

## Verified API reference

Every call below was read out of this repo at the cited location. Use these spellings; do not improvise.

| Purpose | Call | Source |
| --- | --- | --- |
| Job handle / guard | `VectricJob()`, `job.Exists` | `Blum_Nesting_Repair.lua:196` |
| Simple message | `DisplayMessageBox(text)`, `MessageBox(text)` | `Blum_Nesting_Repair.lua:198`, `:246` |
| Units and sheet size | `MaterialBlock()` → `.InMM`, `.Thickness`, `.Width`, `.Height`, `.MaterialBox` | `BlumDrawerTools.xlua:1379-1397` |
| Material extents | `mtl_block.MaterialBox` → `.BLC`, `.TRC` (each has `.x`, `.y`, `.z`) | `BlumDrawerJoinery.xlua:1250-1255` |
| Sheets | `job.SheetManager`, `.ActiveSheetId`, `:GetSheetIds()`, `:GetSheetName(id)` | `Blum_Nesting_Repair.lua:203-208` |
| UUID comparison | `luaUUID(raw_id):AsString()` | `Blum_Nesting_Repair.lua:19` |
| Layer walk | `job.LayerManager:GetHeadPosition()` / `:GetNext(pos)`, `layer.Name`, `layer.IsSystemLayer`, `layer.IsEmpty` | `Blum_Nesting_Repair.lua:64-80`, `BlumDrawerTools.xlua:1497` |
| Object walk | `layer:GetHeadPosition()` / `:GetNext(pos)`, `object.SheetId`, `object.ClassName` | `Blum_Nesting_Repair.lua:74-78` |
| Contour from object | `object:GetContour()` (nil for groups), `contour.IsOpen` | `BlumDrawerJoinery.xlua:1377-1391` |
| Find / create a layer | `job.LayerManager:FindLayerWithName(name)` (nil if absent), `:GetLayerWithName(name)` (creates) | `BlumDrawerJoinery.xlua:1319`, `BlumDrawerTools.xlua:1497` |
| Remove a layer | `job.LayerManager:RemoveLayer(layer)` | `BlumDrawerTools.xlua:1499` |
| Layer color | `layer:SetColor(red, green, blue)` | `BlumDrawerTools.xlua:1543` |
| Add geometry | `layer:AddObject(CreateCadContour(contour), true)` | `BlumDrawerTools.xlua:1472` |
| Build a circle | `Contour(0.0)`, `:AppendPoint(pt)`, `:ArcTo(pt, 1)`, `Polar2D(pt, degrees, distance)`, `Point2D(x, y)` | `BlumDrawerTools.xlua:1450-1474` |
| Selection | `job.Selection`, `:Clear()`, `:Add(object, true, true)`, `:GroupSelectionFinished()`, `:GetBoundingBox()` | `BlumDrawerJoinery.xlua:1316-1400`, `BlumDrawerTools.xlua:89` |
| Toolpaths | `ToolpathManager()`, `:GetHeadPosition()` / `:GetNext(pos)`, `:GetTailPosition()` / `:GetPrev(pos)`, `:DeleteToolpath(tp)`, `toolpath.Name`, `.Id`, `.SheetId`, `.Tool` | `Blum_Nesting_Repair.lua:29-60` |
| Toolpath position data | `ToolpathPosData()`, `:SetHomePosition(x, y, z)`, `.SafeZGap` | `BlumDrawerJoinery.xlua:1252-1255` |
| Geometry selector | `GeometrySelector()`, `.GeometryFilterUsed`, `.OnlyOnLayers`, `.SelectClosed`, `.SelectOpen`, `:AddLayerName(name)`, `:SaveSelectorData(tp)` | `BlumDrawerJoinery.xlua:1330-1348` |
| Tool | `Tool(name, Tool.VBIT)`, `.InMM`, `.ToolDia`, `.Stepdown`, `.Stepover`, `.RateUnits`, `.FeedRate`, `.PlungeRate`, `.SpindleSpeed`, `.ToolNumber`, `.VBitAngle` | `BlumDrawerJoinery.xlua:1234-1245` |
| Dialog | `HTML_Dialog(true, html, width, height, title)`, `:ShowDialog()` (true = `ButtonOK`, false = `ButtonCancel`) | `Blum_Nesting_Repair.lua:189-190` |
| Dialog fields | `:AddDoubleField(id, v)` / `:GetDoubleField(id)`, `:AddIntegerField` / `:GetIntegerField`, `:AddCheckBox` / `:GetCheckBox`, `:AddLabelField(id, text)` | `BlumDrawerDialog.xlua:1209-1250` |
| Tool picker | `:AddToolPicker(buttonId, labelId, toolDbId)`, `:AddToolPickerValidToolType(buttonId, Tool.VBIT)`, `:GetTool(buttonId)` (falsy when unchanged), `ToolDBId()` | `BlumDrawerDialog.xlua:1016-1018`, `:1046-1063` |
| Redraw | `job:Refresh2DView()` | `Blum_Nesting_Repair.lua:301` |
| Drilling toolpath | `toolpath_manager:CreateDrillingToolpath(name, tool, drill_data, pos_data, geometry_selector, create_2d_preview, interactive)` → UUID, or nil on failure | V12 SDK PDF p.130 |
| Drilling parameters | `DrillParameterData()` → `.StartDepth`, `.StartDepthFormula`, `.CutDepth`, `.CutDepthFormula`, `.DoPeckDrill`, `.PeckRetractGap`, `.ProjectToolpath`, `.Name` | V12 SDK PDF p.171 |

`CreateDrillingToolpath` and `DrillParameterData` are documented in the V12 SDK PDF (`Vectric Lua Interface Documentation.pdf`, from <https://storage.vectric.com/gadgets/V12/Vectric_Gadget_SDK.vgadget>) but have never been called in this repo. The PDF's own sample hardcodes `SetHomePosition(0, 0, 5.0)` and `SafeZGap = 5.0` — that is the exact bug the spec forbids. Do not copy those two lines from it.

**Unverified, and resolved by Task 2 before anything depends on them:** `Contour:IsPointInside`, `Contour:CreatePolygonizedCopy`, `GetDefaultContourTolerance`, iterating a polygonized contour's points, a contour bounding box, layer visibility, and clearing a non-empty layer.

**Unverified and not resolvable by probing — Task 7 settles these empirically:** whether a drilling toolpath drills at the center of each closed vector, whether `CreateDrillingToolpath` accepts a `Tool.VBIT` tool at all, whether `VBitAngle` affects the cut, and whether VCarve objects to a marker circle that is smaller or larger than the tool. The SDK documents none of it; the spec's Risks section says as much.

---

### Task 1: Gadget skeleton that runs, validates, and reports

Proves packaging, installation and the whole job/sheet/layer walk before any math exists.

**Files:**
- Create: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve (see Global Constraints)

**Interfaces:**
- Consumes: nothing.
- Produces: globals `HoldDown` (table), and the functions `IdKey(raw_id) -> string`, `ReadUnits() -> nil` (sets `HoldDown.Cal`, `HoldDown.InMM`, `HoldDown.UnitLabel`), `IsLayerVisible(layer) -> boolean`, `CollectSheetVectors(job) -> vectors, skipped` where `vectors` is an array of `{contour = Contour, layer = string}` and `skipped` is an array of layer-name strings for objects whose contour could not be read.

- [ ] **Step 1: Create the file with its header and globals**

```lua
-- VECTRIC LUA SCRIPT
--[[
-- Gadgets are an entirely optional add-in to Vectric's core software products.
-- They are provided 'as-is', without any express or implied warranty, and you make use of them entirely at your own risk.
-- In no event will the author(s) or Vectric Ltd. be held liable for any damages arising from their use.
-- ====================================================================================================================================
-- Hold Down Helper: finds places on the active sheet where a screw or nail can be driven into the spoilboard
-- without being hit by a cutter later, marks each one, and creates a drilling toolpath that dimples them with
-- a V-bit. Run that toolpath on its own, drive the fasteners at the dimples, then run the real job WITHOUT
-- re-zeroing -- the dimples are in job coordinates, so a re-zero invalidates every one of them.
]] -- =====================================================]]
require "strict"

HoldDown = {}
HoldDown.ProgramVersion = "1.0"
HoldDown.RegName = "HoldDownHelper" .. HoldDown.ProgramVersion
HoldDown.LayerName = "Hold Down"
HoldDown.ToolpathName = "Hold Down Dimples"
HoldDown.job = nil
HoldDown.Cal = 1.0
HoldDown.InMM = false
HoldDown.UnitLabel = "inches"
```

- [ ] **Step 2: Add the unit and identity helpers**

```lua
-- =====================================================]]
function IdKey(raw_id) -- String form of a UUID, usable as a table key
    return luaUUID(raw_id):AsString()
end
-- =====================================================]]
function ReadUnits()
    -- Units come from the job's material block, the same source GetMaterialSettings uses in Blum Drawer Maker.
    -- Cal is 1.0 in an imperial job and 25.4 in a metric one.
    local mtl_block = MaterialBlock()
    if mtl_block.InMM then
        HoldDown.InMM = true
        HoldDown.Cal = 25.4
        HoldDown.UnitLabel = "mm"
    else
        HoldDown.InMM = false
        HoldDown.Cal = 1.0
        HoldDown.UnitLabel = "inches"
    end
end
```

- [ ] **Step 3: Add layer visibility, failing safe**

Visibility is the spec's escape hatch: a hidden layer is excluded from the safety test. Nothing in this repo reads a layer's visibility, so the property name is unverified until Task 2. Until then this helper treats an unreadable layer as **visible**, which fails safe — an unreadable layer still blocks fasteners rather than silently allowing one through a part.

```lua
-- =====================================================]]
function IsLayerVisible(layer)
    -- Unverified until the Task 2 probe confirms the property name. Failing to read it means
    -- "visible", so an unknown layer still blocks fasteners instead of being ignored.
    local ok, visible = pcall(function()
        return layer.IsVisible
    end)
    if ok and visible ~= nil then
        return visible
    end
    return true
end
```

- [ ] **Step 4: Add the vector inventory**

A grouped part returns `nil` from `GetContour()`. Skipping it silently is the exact failure this gadget exists to prevent — a screw driven through a grouped part — so every skip is counted and reported.

```lua
-- =====================================================]]
function CollectSheetVectors(job)
    -- Every visible vector on the active sheet, on any layer, except the gadget's own layer.
    local sheet_key = IdKey(job.SheetManager.ActiveSheetId)
    local layer_manager = job.LayerManager
    local vectors = {}
    local skipped = {}
    local pos = layer_manager:GetHeadPosition()
    while pos ~= nil do
        local layer
        layer, pos = layer_manager:GetNext(pos)
        if (not layer.IsSystemLayer) and layer.Name ~= HoldDown.LayerName and IsLayerVisible(layer) then
            local object_pos = layer:GetHeadPosition()
            while object_pos ~= nil do
                local object
                object, object_pos = layer:GetNext(object_pos)
                if IdKey(object.SheetId) == sheet_key then
                    local contour = object:GetContour()
                    if contour ~= nil then
                        table.insert(vectors, {contour = contour, layer = layer.Name})
                    else
                        table.insert(skipped, layer.Name)
                    end
                end
            end
        end
    end
    return vectors, skipped
end
```

- [ ] **Step 5: Add `main`**

```lua
-- =====================================================]]
function main(script_path)
    local job = VectricJob()
    if not job.Exists then
        DisplayMessageBox("Hold Down Helper needs a job.\n\nOpen or create one, then run the gadget again.")
        return false
    end
    HoldDown.job = job
    ReadUnits()

    local vectors, skipped = CollectSheetVectors(job)
    if #vectors == 0 then
        DisplayMessageBox("There are no visible vectors on the active sheet, so there is nothing to keep clear of.\n\n" ..
            "Hold Down Helper made no changes.")
        return false
    end

    local mtl_block = MaterialBlock()
    local message = "Hold Down Helper\n\n" ..
        "Units: " .. HoldDown.UnitLabel .. "\n" ..
        "Sheet: " .. string.format("%.3f", mtl_block.Width) .. " x " .. string.format("%.3f", mtl_block.Height) ..
        " x " .. string.format("%.3f", mtl_block.Thickness) .. "\n" ..
        "Vectors to keep clear of: " .. #vectors
    if #skipped > 0 then
        message = message .. "\n\nWARNING: " .. #skipped .. " object(s) have no readable outline and were ignored. " ..
            "Grouped vectors do this. Ungroup them before trusting the result."
    end
    MessageBox(message)
    return true
end
-- =============== End of File =========================]]
```

- [ ] **Step 6: Package it**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

Expected: `Hold_Down_Helper.vgadget` appears at the repository root.

- [ ] **Step 7: Have the user verify in VCarve**

Ask the user to install the `.vgadget` and run the gadget four times:

| Case | Expected |
| --- | --- |
| No job open | "Hold Down Helper needs a job." and no changes |
| A job with an empty active sheet | "no visible vectors on the active sheet" and no changes |
| A job with parts on the active sheet | The report, with a plausible vector count and the sheet size in the job's own units |
| The same job with one layer of parts hidden | *May* still count the hidden layer's vectors — Task 2 resolves this. Note the number either way; it is the before-reading for Task 2's visibility check. |

Do not proceed until the user confirms the third case reports a sensible count.

- [ ] **Step 8: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Add the Hold Down Helper skeleton, reporting the vectors it must clear."
```

---

### Task 2: Probe the unverified APIs and record what they are

Every remaining task depends on an API this repo has never called. Resolve them all in one VCarve round trip rather than discovering them one failure at a time. This is the technique the root `README.md` documents: calling a method with no arguments inside `pcall` makes luabind list every overload in the error message.

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua` (add `Probe()` and a temporary call to it; both removed in Step 6)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `HoldDown`, `IdKey`, `CollectSheetVectors` from Task 1.
- Produces: no functions. Produces a comment block at the top of the file recording each resolved signature, which every later task reads instead of guessing.

- [ ] **Step 1: Add the probe**

```lua
-- =====================================================]]
function ProbeLine(label, fn)
    -- Calls fn and reports what came back. A luabind error from a no-argument call lists every
    -- overload of the method, which is how an undocumented signature is recovered.
    local ok, result = pcall(fn)
    if ok then
        return label .. " => OK: " .. tostring(result)
    end
    return label .. " => " .. tostring(result)
end
-- =====================================================]]
function Probe()
    local job = HoldDown.job
    local vectors = CollectSheetVectors(job)
    local contour = vectors[1] and vectors[1].contour or nil
    local layer = job.LayerManager:GetLayerWithName(HoldDown.LayerName)
    local toolpath_manager = ToolpathManager()
    local lines = {}

    table.insert(lines, ProbeLine("GetDefaultContourTolerance()", function()
        return GetDefaultContourTolerance()
    end))
    table.insert(lines, ProbeLine("contour:CreatePolygonizedCopy() no-arg", function()
        return contour:CreatePolygonizedCopy()
    end))
    table.insert(lines, ProbeLine("contour:IsPointInside() no-arg", function()
        return contour:IsPointInside()
    end))
    table.insert(lines, ProbeLine("contour.IsClosed", function()
        return contour.IsClosed
    end))
    table.insert(lines, ProbeLine("contour:GetBoundingBox()", function()
        return contour:GetBoundingBox()
    end))
    table.insert(lines, ProbeLine("contour.BoundingBox", function()
        return contour.BoundingBox
    end))
    table.insert(lines, ProbeLine("contour.NumberOfSpans", function()
        return contour.NumberOfSpans
    end))
    table.insert(lines, ProbeLine("contour:GetSpan() no-arg", function()
        return contour:GetSpan()
    end))
    table.insert(lines, ProbeLine("contour:GetHeadPosition()", function()
        return contour:GetHeadPosition()
    end))
    table.insert(lines, ProbeLine("layer.IsVisible", function()
        return layer.IsVisible
    end))
    table.insert(lines, ProbeLine("layer.Visible", function()
        return layer.Visible
    end))
    table.insert(lines, ProbeLine("layer:RemoveObject() no-arg", function()
        return layer:RemoveObject()
    end))
    table.insert(lines, ProbeLine("layer:Clear()", function()
        return layer:Clear()
    end))
    -- Documented in the SDK PDF, never called in this repo: confirm they exist in this build
    table.insert(lines, ProbeLine("DrillParameterData()", function()
        return DrillParameterData()
    end))
    table.insert(lines, ProbeLine("toolpath_manager.CreateDrillingToolpath present", function()
        return type(toolpath_manager.CreateDrillingToolpath)
    end))

    local path = (os.getenv("TEMP") or "C:\\Temp") .. "\\HoldDownHelper_probe.txt"
    local file = io.open(path, "w")
    if file ~= nil then
        file:write(table.concat(lines, "\n"))
        file:close()
    end
    MessageBox("Probe results written to:\n" .. path .. "\n\n" .. table.concat(lines, "\n"))
end
```

- [ ] **Step 2: Call it from `main`**

Insert immediately before the `MessageBox(message)` line added in Task 1 Step 5:

```lua
    Probe()
```

- [ ] **Step 3: Package and have the user run it**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

Ask the user to run the gadget on a job with parts on the active sheet and send back `%TEMP%\HoldDownHelper_probe.txt`.

- [ ] **Step 4: Read the results and resolve each signature**

For each line, the outcome is one of:
- `OK: <value>` — the call works as written. A `userdata` result means an object came back.
- An error naming candidate overloads — read the argument types out of the list.
- An error saying the method or property does not exist — that name is wrong; use one of the alternatives probed alongside it.

Expect exactly one of `layer.IsVisible` / `layer.Visible` to work, and at most one of the three contour-iteration forms.

- [ ] **Step 5: Record the answers in the file**

Add this block directly below the `require "strict"` line, filled in with the real results. Later tasks read it instead of guessing.

```lua
-- Resolved against VCarve Pro V12.5 by the Task 2 probe on <DATE>. The SDK PDF does not document
-- all of these; these are the signatures the running application actually accepts.
--   GetDefaultContourTolerance()          -> <result>
--   Contour:CreatePolygonizedCopy(<args>) -> <result>
--   Contour:IsPointInside(<args>)         -> <result>
--   Contour bounding box                  -> <the form that worked>
--   Contour point iteration               -> <the form that worked>
--   Layer visibility                      -> <the property that worked>
--   Clearing a layer                      -> <the form that worked>
--   DrillParameterData()                  -> <result>
```

If `DrillParameterData()` or `CreateDrillingToolpath` is missing from this build, stop and tell the user before starting Task 7 — the spec's output requirement cannot be met without them, and that is a design decision, not an implementation one.

- [ ] **Step 6: Delete the probe**

Remove `ProbeLine`, `Probe`, and the `Probe()` call from `main`. The comment block is the deliverable; the probe itself is not shipped.

- [ ] **Step 7: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Record the Vectric API signatures the Hold Down Helper needs."
```

---

### Task 3: Settings, with per-unit defaults, persisted to the registry

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `HoldDown`, `ReadUnits` from Task 1.
- Produces: `SettingsRead() -> nil` and `SettingsWrite() -> nil`, both operating on these fields of `HoldDown`, all in job units: `ToolDiameter`, `HeadDiameter`, `Margin`, `EdgeInset`, `PerimeterSpacing`, `FieldCount` (integer), `MaxSearch`, `DimpleDepth`, `MarkerDiameter`. Also `ClearanceRadius() -> number`.

- [ ] **Step 1: Add the default tables**

The metric column is not the imperial column times 25.4 — 0.25" maps to a 6 mm bit, not 6.35 — so the two are independent tables, the same way `BlumDrawerRegistry.xlua` keeps separate metric and imperial blocks.

```lua
-- =====================================================]]
-- Defaults are per unit system and are stored in job units, never normalized to mm. The metric
-- column is the sensible metric equivalent, not a conversion: a 0.25" bit becomes a 6mm bit.
local IMPERIAL_DEFAULTS = {
    ToolDiameter = 0.25,
    HeadDiameter = 0.25,
    Margin = 0.125,
    EdgeInset = 1.25,
    PerimeterSpacing = 16.0,
    FieldCount = 4,
    MaxSearch = 3.0,
    DimpleDepth = 0.1,
    MarkerDiameter = 0.125
}
local METRIC_DEFAULTS = {
    ToolDiameter = 6.0,
    HeadDiameter = 6.0,
    Margin = 3.0,
    EdgeInset = 32.0,
    PerimeterSpacing = 406.4,
    FieldCount = 4,
    MaxSearch = 76.2,
    DimpleDepth = 2.5,
    MarkerDiameter = 3.0
}
-- =====================================================]]
function SettingDefaults()
    if HoldDown.InMM then
        return METRIC_DEFAULTS
    end
    return IMPERIAL_DEFAULTS
end
```

- [ ] **Step 2: Add the reader**

Registry keys are suffixed by unit system, so a user who works in both does not get an imperial edge inset applied to a metric job.

```lua
-- =====================================================]]
function SettingsKey(name)
    if HoldDown.InMM then
        return "Metric." .. name
    end
    return "Imperial." .. name
end
-- =====================================================]]
function SettingsRead()
    local registry = Registry(HoldDown.RegName)
    local defaults = SettingDefaults()
    HoldDown.ToolDiameter = registry:GetDouble(SettingsKey("ToolDiameter"), defaults.ToolDiameter)
    HoldDown.HeadDiameter = registry:GetDouble(SettingsKey("HeadDiameter"), defaults.HeadDiameter)
    HoldDown.Margin = registry:GetDouble(SettingsKey("Margin"), defaults.Margin)
    HoldDown.EdgeInset = registry:GetDouble(SettingsKey("EdgeInset"), defaults.EdgeInset)
    HoldDown.PerimeterSpacing = registry:GetDouble(SettingsKey("PerimeterSpacing"), defaults.PerimeterSpacing)
    HoldDown.FieldCount = registry:GetInt(SettingsKey("FieldCount"), defaults.FieldCount)
    HoldDown.MaxSearch = registry:GetDouble(SettingsKey("MaxSearch"), defaults.MaxSearch)
    HoldDown.DimpleDepth = registry:GetDouble(SettingsKey("DimpleDepth"), defaults.DimpleDepth)
    HoldDown.MarkerDiameter = registry:GetDouble(SettingsKey("MarkerDiameter"), defaults.MarkerDiameter)
end
```

- [ ] **Step 3: Add the writer**

```lua
-- =====================================================]]
function SettingsWrite()
    local registry = Registry(HoldDown.RegName)
    registry:SetDouble(SettingsKey("ToolDiameter"), HoldDown.ToolDiameter)
    registry:SetDouble(SettingsKey("HeadDiameter"), HoldDown.HeadDiameter)
    registry:SetDouble(SettingsKey("Margin"), HoldDown.Margin)
    registry:SetDouble(SettingsKey("EdgeInset"), HoldDown.EdgeInset)
    registry:SetDouble(SettingsKey("PerimeterSpacing"), HoldDown.PerimeterSpacing)
    registry:SetInt(SettingsKey("FieldCount"), HoldDown.FieldCount)
    registry:SetDouble(SettingsKey("MaxSearch"), HoldDown.MaxSearch)
    registry:SetDouble(SettingsKey("DimpleDepth"), HoldDown.DimpleDepth)
    registry:SetDouble(SettingsKey("MarkerDiameter"), HoldDown.MarkerDiameter)
end
```

`BlumDrawerRegistry.xlua` only ever calls `SetString`, so `SetDouble` and `SetInt` are paired-by-name with the verified `GetDouble`/`GetInt` but not themselves exercised in this repo. Step 6 checks them. If either is rejected, fall back to `registry:SetString(key, tostring(value))` and parse with `tonumber(registry:GetString(key, tostring(default)))` throughout.

- [ ] **Step 4: Add the clearance radius**

This is the `R` the whole safety test is built on.

```lua
-- =====================================================]]
function ClearanceRadius()
    -- R = half the cutter + half the screw head + margin. At the imperial defaults this is 0.375".
    return (HoldDown.ToolDiameter * 0.5) + (HoldDown.HeadDiameter * 0.5) + HoldDown.Margin
end
```

- [ ] **Step 5: Wire it into `main` and report it**

After `ReadUnits()` add `SettingsRead()`, and extend the message built in Task 1 Step 5 with a line before `MessageBox(message)`:

```lua
    message = message .. "\nClearance radius R: " .. string.format("%.4f", ClearanceRadius())
```

Then, immediately before `MessageBox(message)`, add `SettingsWrite()` so a run round-trips the values even before the dialog exists.

- [ ] **Step 6: Package and have the user verify**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

| Case | Expected |
| --- | --- |
| First run, imperial job | `Clearance radius R: 0.3750` |
| First run, metric job | `Clearance radius R: 9.0000` |
| Second run | Same value, no error — proves `SetDouble`/`SetInt` were accepted |

If the second run raises a luabind error on `SetDouble` or `SetInt`, apply the `SetString`/`tonumber` fallback from Step 3 and re-verify.

- [ ] **Step 7: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Persist Hold Down Helper settings per unit system."
```

---

### Task 4: The settings dialog, with a V-bit picker

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `HoldDown`, `SettingsRead`, `SettingsWrite` from Task 3.
- Produces: `ShowSettingsDialog() -> boolean` (false when the user cancels), and the global `HoldDown.Tool` — a tool object with `.Name`, `.ToolDia`, `.InMM`, `.VBitAngle`, `.Stepdown`, `.Stepover`, `.RateUnits`, `.FeedRate`, `.PlungeRate`, `.SpindleSpeed`, `.ToolNumber` — or a table whose `.Name` is `"Tool Not Selected"` when none has been chosen.

- [ ] **Step 1: Declare the tool globals at the main chunk**

`ToolDBId()` must outlive the dialog, so it is a main-chunk global exactly as `Tool_ID1` is in `Blum_Drawer_Maker.lua:37`. Add below the `HoldDown.UnitLabel` line from Task 1:

```lua
HoldDownToolId = ToolDBId()
HoldDown.Tool = {Name = "Tool Not Selected"}
```

- [ ] **Step 2: Add the dialog HTML**

```lua
-- =====================================================]]
function SettingsHtml()
    local unit = HoldDown.UnitLabel
    return [[<html><head><style>
body { font-family: Arial, sans-serif; font-size: 12px; background-color: #F0F0F0; }
table { border-collapse: collapse; }
td { padding: 2px 6px; }
td.label { text-align: right; }
td.unit { color: #666666; }
.note { background-color: #FFF4CE; border: 1px solid #D9A400; padding: 6px; margin-top: 8px; }
.buttons { text-align: right; margin-top: 8px; }
</style></head><body>
<table>
<tr><td class="label"><label title="The V-bit that cuts the dimples">V-Bit:</label></td>
    <td bgcolor="#33FFFF"><span id="ToolNameLabel">-</span></td>
    <td><input id="ToolChooseButton" class="ToolPicker" type="button" value="Tool"></td></tr>
<tr><td class="label"><label title="Largest cutter used anywhere in the job">Assumed tool diameter:</label></td>
    <td><input type="text" id="ToolDiameter" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Diameter of the fastener head">Screw head diameter:</label></td>
    <td><input type="text" id="HeadDiameter" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Extra clearance added on top of the cutter and head">Margin:</label></td>
    <td><input type="text" id="Margin" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="How far in from the sheet edge perimeter fasteners sit">Edge inset:</label></td>
    <td><input type="text" id="EdgeInset" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Target spacing between perimeter fasteners">Perimeter spacing target:</label></td>
    <td><input type="text" id="PerimeterSpacing" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Fasteners placed in the middle of the sheet">Field count:</label></td>
    <td><input type="text" id="FieldCount" size="10" maxlength="10" /></td><td class="unit">&nbsp;</td></tr>
<tr><td class="label"><label title="How far a rejected position may move looking for a safe one">Max nudge search:</label></td>
    <td><input type="text" id="MaxSearch" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="How deep the V-bit cuts each dimple">Dimple depth:</label></td>
    <td><input type="text" id="DimpleDepth" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Size of the marker circle drawn per position">Marker diameter:</label></td>
    <td><input type="text" id="MarkerDiameter" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
</table>
<div class="note"><b>Type values, do not paste them.</b> VCarve discards a pasted value unless you type it
and tab out of the field.</div>
<p class="buttons"><input id="ButtonOK" class="FormButton" type="button" value="Mark Positions">
<input id="ButtonCancel" class="FormButton" type="button" value="Cancel"></p>
</body></html>]]
end
```

- [ ] **Step 3: Add the dialog function**

`ButtonOK` and `ButtonCancel` are magic ids the `HTML_Dialog` runtime recognizes; the button labels are cosmetic. `GetTool` returns something falsy when the user did not pick a tool this time round, so the guard preserves the previous choice.

```lua
-- =====================================================]]
function ShowSettingsDialog()
    local dialog = HTML_Dialog(true, SettingsHtml(), 470, 430, "Hold Down Helper (" .. HoldDown.UnitLabel .. ")")
    dialog:AddLabelField("ToolNameLabel", HoldDown.Tool.Name)
    dialog:AddToolPicker("ToolChooseButton", "ToolNameLabel", HoldDownToolId)
    dialog:AddToolPickerValidToolType("ToolChooseButton", Tool.VBIT)
    dialog:AddDoubleField("ToolDiameter", HoldDown.ToolDiameter)
    dialog:AddDoubleField("HeadDiameter", HoldDown.HeadDiameter)
    dialog:AddDoubleField("Margin", HoldDown.Margin)
    dialog:AddDoubleField("EdgeInset", HoldDown.EdgeInset)
    dialog:AddDoubleField("PerimeterSpacing", HoldDown.PerimeterSpacing)
    dialog:AddIntegerField("FieldCount", HoldDown.FieldCount)
    dialog:AddDoubleField("MaxSearch", HoldDown.MaxSearch)
    dialog:AddDoubleField("DimpleDepth", HoldDown.DimpleDepth)
    dialog:AddDoubleField("MarkerDiameter", HoldDown.MarkerDiameter)
    if not dialog:ShowDialog() then
        return false
    end
    if dialog:GetTool("ToolChooseButton") then
        HoldDown.Tool = dialog:GetTool("ToolChooseButton")
    end
    -- Every distance is a magnitude; a negative one is always a typo, never a signed offset.
    HoldDown.ToolDiameter = math.abs(dialog:GetDoubleField("ToolDiameter"))
    HoldDown.HeadDiameter = math.abs(dialog:GetDoubleField("HeadDiameter"))
    HoldDown.Margin = math.abs(dialog:GetDoubleField("Margin"))
    HoldDown.EdgeInset = math.abs(dialog:GetDoubleField("EdgeInset"))
    HoldDown.PerimeterSpacing = math.abs(dialog:GetDoubleField("PerimeterSpacing"))
    HoldDown.FieldCount = math.abs(dialog:GetIntegerField("FieldCount"))
    HoldDown.MaxSearch = math.abs(dialog:GetDoubleField("MaxSearch"))
    HoldDown.DimpleDepth = math.abs(dialog:GetDoubleField("DimpleDepth"))
    HoldDown.MarkerDiameter = math.abs(dialog:GetDoubleField("MarkerDiameter"))
    SettingsWrite()
    return true
end
```

- [ ] **Step 4: Add validation**

The spec requires the gadget to refuse to run without a V-bit, to reject a zero perimeter spacing (which would divide by zero in Task 5), and to warn on a small sheet without blocking.

```lua
-- =====================================================]]
function ValidateSettings()
    -- Returns an error string, or nil when the settings can be used.
    if HoldDown.Tool == nil or HoldDown.Tool.Name == "Tool Not Selected" then
        return "Choose a V-bit before marking positions.\n\n" ..
            "The gadget needs one to create the dimpling toolpath."
    end
    if HoldDown.Tool.InMM ~= HoldDown.InMM then
        return "The V-bit's units do not match the job's units.\n\n" ..
            "Choose a bit defined in " .. HoldDown.UnitLabel .. "."
    end
    if HoldDown.PerimeterSpacing <= 0.0 then
        return "Perimeter spacing target must be greater than zero."
    end
    if HoldDown.MarkerDiameter <= 0.0 then
        return "Marker diameter must be greater than zero."
    end
    if ClearanceRadius() <= 0.0 then
        return "Tool diameter, screw head diameter and margin cannot all be zero."
    end
    return nil
end
```

- [ ] **Step 5: Replace the Task 1 report in `main` with the dialog loop**

Substitute this for the message-building block, keeping the no-job and no-vectors guards above it:

```lua
    SettingsRead()
    while true do
        if not ShowSettingsDialog() then
            return false
        end
        local problem = ValidateSettings()
        if problem == nil then
            break
        end
        DisplayMessageBox(problem)
    end

    local mtl_block = MaterialBlock()
    local small = 24.0 * HoldDown.Cal
    if mtl_block.Width < small or mtl_block.Height < small then
        DisplayMessageBox("This sheet is smaller than 24 x 24.\n\n" ..
            "Hold Down Helper is intended for full sheets. It will carry on, but check the positions it marks.")
    end

    MessageBox("Hold Down Helper\n\nV-bit: " .. tostring(HoldDown.Tool.Name) ..
        "\nClearance radius R: " .. string.format("%.4f", ClearanceRadius()) ..
        "\nVectors to keep clear of: " .. #vectors)
    return true
```

- [ ] **Step 6: Package and have the user verify**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

| Case | Expected |
| --- | --- |
| Open the dialog | Ten rows, values at the defaults for the job's units, the paste warning visible |
| Click **Tool** | The tool database opens showing **only V-bits** |
| Press **Cancel** | Gadget exits, nothing changed |
| Press **Mark Positions** with no bit chosen | "Choose a V-bit before marking positions" then the dialog reopens |
| Choose a bit, change Margin by typing, press **Mark Positions** | Report shows the bit name and an R reflecting the new margin |
| Run again | The changed Margin is still there |
| A metric bit in an imperial job | "The V-bit's units do not match the job's units" |
| A 12 x 12 sheet | The small-sheet warning, then the report |

- [ ] **Step 7: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Add the Hold Down Helper settings dialog and its V-bit picker."
```

---

### Task 5: Target positions and markers, with idempotent re-runs

Draws markers at the ideal positions with **no safety test yet**, so the layout itself can be checked against a real sheet before the rejection logic is layered on.

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `HoldDown`, `ClearanceRadius` from Task 3, `ShowSettingsDialog` from Task 4.
- Produces:
  - `SheetBounds() -> min_x, min_y, max_x, max_y`
  - `PerimeterTargets(min_x, min_y, max_x, max_y) -> array of {x, y, kind = "perimeter", edge = "bottom"|"top"|"left"|"right"}`
  - `FieldTargets(min_x, min_y, max_x, max_y) -> array of {x, y, kind = "field"}`
  - `ClearHoldDownLayer() -> nil`
  - `DrawMarker(layer, x, y) -> nil`

- [ ] **Step 1: Add the sheet bounds**

```lua
-- =====================================================]]
function SheetBounds()
    local mtl_box = MaterialBlock().MaterialBox
    return mtl_box.BLC.x, mtl_box.BLC.y, mtl_box.TRC.x, mtl_box.TRC.y
end
```

- [ ] **Step 2: Add the perimeter targets**

`count = max(2, round(side_length / spacing))` puts 3 on a 48" side at the 16" default. The `(i - 0.5) / count` fractions keep every position off the corners, and the inset holds them `edge_inset` in from the sheet edge.

```lua
-- =====================================================]]
function PerimeterCount(side_length)
    local count = math.floor((side_length / HoldDown.PerimeterSpacing) + 0.5)
    if count < 2 then
        count = 2
    end
    return count
end
-- =====================================================]]
function PerimeterTargets(min_x, min_y, max_x, max_y)
    local inset = HoldDown.EdgeInset
    local width = max_x - min_x
    local height = max_y - min_y
    local targets = {}

    local across = PerimeterCount(width)
    for i = 1, across do
        local fraction = (i - 0.5) / across
        local x = min_x + (width * fraction)
        table.insert(targets, {x = x, y = min_y + inset, kind = "perimeter", edge = "bottom"})
        table.insert(targets, {x = x, y = max_y - inset, kind = "perimeter", edge = "top"})
    end

    local up = PerimeterCount(height)
    for i = 1, up do
        local fraction = (i - 0.5) / up
        local y = min_y + (height * fraction)
        table.insert(targets, {x = min_x + inset, y = y, kind = "perimeter", edge = "left"})
        table.insert(targets, {x = max_x - inset, y = y, kind = "perimeter", edge = "right"})
    end
    return targets
end
```

- [ ] **Step 3: Add the field targets**

The field is the center 50% of the sheet — the middle 24x24 of a 48x48. `field_count` is laid out as the nearest grid that fits, filling rows first: 4 becomes 2x2, whose cells sit at the quarter points of the region, and 6 becomes 2 rows of 3.

```lua
-- =====================================================]]
function FieldTargets(min_x, min_y, max_x, max_y)
    local count = HoldDown.FieldCount
    if count < 1 then
        return {}
    end
    -- Center 50% of the sheet
    local width = (max_x - min_x) * 0.5
    local height = (max_y - min_y) * 0.5
    local region_x = min_x + ((max_x - min_x) * 0.25)
    local region_y = min_y + ((max_y - min_y) * 0.25)

    local columns = math.ceil(math.sqrt(count))
    local rows = math.ceil(count / columns)
    local targets = {}
    local placed = 0
    for row = 1, rows do
        for column = 1, columns do
            if placed < count then
                placed = placed + 1
                table.insert(targets, {
                    x = region_x + (width * ((column - 0.5) / columns)),
                    y = region_y + (height * ((row - 0.5) / rows)),
                    kind = "field"
                })
            end
        end
    end
    return targets
end
```

- [ ] **Step 4: Add marker drawing and layer clearing**

`DrawCircle` in `BlumDrawerTools.xlua:1450` is the model: two 180-degree arcs between the points at 0 and 180 degrees from the center.

```lua
-- =====================================================]]
function DrawMarker(layer, x, y)
    local center = Point2D(x, y)
    local radius = HoldDown.MarkerDiameter * 0.5
    local left = Polar2D(center, 180.0, radius)
    local right = Polar2D(center, 0.0, radius)
    local circle = Contour(0.0)
    circle:AppendPoint(left)
    circle:ArcTo(right, 1)
    circle:ArcTo(left, 1)
    layer:AddObject(CreateCadContour(circle), true)
end
-- =====================================================]]
function ClearHoldDownLayer()
    -- Re-running must rebuild rather than accumulate. Removing the layer wholesale is the form this
    -- repo already uses (BlumDrawerTools.xlua:1499); GetLayerWithName then recreates it empty.
    -- Replace this body with whatever the Task 2 probe showed actually clears a non-empty layer.
    local layer = HoldDown.job.LayerManager:FindLayerWithName(HoldDown.LayerName)
    if layer ~= nil then
        HoldDown.job.LayerManager:RemoveLayer(layer)
    end
end
-- =====================================================]]
function HoldDownLayer()
    local layer = HoldDown.job.LayerManager:GetLayerWithName(HoldDown.LayerName)
    layer:SetColor(255, 0, 255) -- magenta: not a color the Blum gadgets use, so markers stand out
    return layer
end
```

**Before writing this**, read the Task 2 probe result for "Clearing a layer". If `RemoveLayer` on a non-empty layer was rejected or left the objects behind, use the form the probe confirmed instead. Do not ship a clear that does not clear — accumulating markers across runs would put stale positions in the drilling toolpath.

- [ ] **Step 5: Wire it into `main`**

Keep the dialog loop and the small-sheet warning from Task 4 Step 5. Replace only the final `MessageBox(...)` call and its `return true` with:

```lua
    local min_x, min_y, max_x, max_y = SheetBounds()
    local targets = PerimeterTargets(min_x, min_y, max_x, max_y)
    for _, target in ipairs(FieldTargets(min_x, min_y, max_x, max_y)) do
        table.insert(targets, target)
    end

    ClearHoldDownLayer()
    local layer = HoldDownLayer()
    for _, target in ipairs(targets) do
        DrawMarker(layer, target.x, target.y)
    end
    HoldDown.job:Refresh2DView()

    MessageBox("Hold Down Helper\n\nMarked " .. #targets .. " position(s) on layer '" .. HoldDown.LayerName ..
        "'.\n\nThese are the ideal positions; nothing has been checked for clearance yet.")
    return true
```

- [ ] **Step 6: Package and have the user verify**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

| Case | Expected |
| --- | --- |
| A 48x48 imperial sheet, field count 4 | 16 markers: 3 per side inset 1.25" from each edge, none in a corner, plus 4 at the quarter points of the middle 24x24 (x and y of 18 and 30) |
| A 48x96 sheet | 3 markers on each short side, 6 on each long side, plus the 4 field markers |
| Field count 6 | 6 field markers as 2 rows of 3 |
| Field count 0 | Perimeter markers only, no error |
| Run the gadget twice | Still 16 markers, not 32 — the layer was cleared |
| Check the layer list | One layer named `Hold Down`, magenta |

Ask the user to confirm the marker circles measure `marker_diameter` across.

- [ ] **Step 7: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Place hold-down targets around the perimeter and across the field."
```

---

### Task 6: The safety test and the nudge search

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `CollectSheetVectors` from Task 1, `ClearanceRadius` from Task 3, `PerimeterTargets` / `FieldTargets` from Task 5.
- Produces:
  - `PointSegmentDistance(px, py, ax, ay, bx, by) -> number`
  - `PrepareObstacles(vectors) -> array of {points = {x1,y1,x2,y2,...}, closed = boolean, contour = Contour, min_x, min_y, max_x, max_y}`
  - `IsPointSafe(obstacles, x, y, radius) -> boolean`
  - `NudgePerimeter(obstacles, target, radius) -> x, y or nil`
  - `NudgeField(obstacles, target, radius) -> x, y or nil`
  - `PlaceTargets(obstacles, targets, radius) -> placed, rejected` where `placed` is an array of `{x, y}` and `rejected` is an array of `{x, y, kind}`

- [ ] **Step 1: Add point-to-segment distance**

The spec chose distance over offset contours because `IsPointInside` is undefined for open contours while distance is well defined for both.

```lua
-- =====================================================]]
function PointSegmentDistance(px, py, ax, ay, bx, by)
    -- Distance from (px,py) to the segment ab, clamping the projection to the segment's ends.
    local dx = bx - ax
    local dy = by - ay
    local length_squared = (dx * dx) + (dy * dy)
    local t = 0.0
    if length_squared > 0.0 then
        t = (((px - ax) * dx) + ((py - ay) * dy)) / length_squared
        if t < 0.0 then
            t = 0.0
        elseif t > 1.0 then
            t = 1.0
        end
    end
    local cx = ax + (t * dx)
    local cy = ay + (t * dy)
    return math.sqrt(((px - cx) * (px - cx)) + ((py - cy) * (py - cy)))
end
```

- [ ] **Step 2: Add obstacle preparation**

Polygonizing every vector once, up front, keeps the per-candidate cost proportional to the vectors actually near it: the bounding box rejects the rest without any segment math.

```lua
-- =====================================================]]
function ContourPoints(contour)
    -- Flat array of x,y pairs along a polygonized contour. Replace the body with the iteration
    -- form the Task 2 probe confirmed; the shape of the return value must not change.
    local points = {}
    local pos = contour:GetHeadPosition()
    while pos ~= nil do
        local span
        span, pos = contour:GetNext(pos)
        local start_point = span.StartPoint
        table.insert(points, start_point.x)
        table.insert(points, start_point.y)
    end
    return points
end
-- =====================================================]]
function PrepareObstacles(vectors)
    local tolerance = GetDefaultContourTolerance()
    local obstacles = {}
    for _, entry in ipairs(vectors) do
        local ok, polygonized = pcall(function()
            return entry.contour:CreatePolygonizedCopy(tolerance)
        end)
        if ok and polygonized ~= nil then
            local points = ContourPoints(polygonized)
            if #points >= 4 then
                local min_x, min_y = points[1], points[2]
                local max_x, max_y = points[1], points[2]
                for i = 3, #points, 2 do
                    local x, y = points[i], points[i + 1]
                    if x < min_x then min_x = x end
                    if x > max_x then max_x = x end
                    if y < min_y then min_y = y end
                    if y > max_y then max_y = y end
                end
                table.insert(obstacles, {
                    points = points,
                    closed = not entry.contour.IsOpen,
                    contour = entry.contour,
                    min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y
                })
            end
        end
    end
    return obstacles
end
```

**Before writing `ContourPoints`**, read the Task 2 probe result for "Contour point iteration" and use the form that worked. The `GetHeadPosition`/`GetNext` form shown is the repo's idiom for every other Vectric collection, which makes it the most likely, but it is not confirmed for `Contour`. If the probe showed `NumberOfSpans` plus an indexed `GetSpan(i)`, write that instead.

- [ ] **Step 3: Add the safety test**

```lua
-- =====================================================]]
function IsPointSafe(obstacles, x, y, radius)
    for _, obstacle in ipairs(obstacles) do
        -- Skip anything whose bounding box is further than R away without polygon math
        if not (x < obstacle.min_x - radius or x > obstacle.max_x + radius or
                y < obstacle.min_y - radius or y > obstacle.max_y + radius) then
            if obstacle.closed then
                local ok, inside = pcall(function()
                    return obstacle.contour:IsPointInside(Point2D(x, y), GetDefaultContourTolerance())
                end)
                if ok and inside then
                    return false -- never through a part
                end
            end
            local points = obstacle.points
            for i = 1, #points - 3, 2 do
                if PointSegmentDistance(x, y, points[i], points[i + 1], points[i + 2], points[i + 3]) < radius then
                    return false -- inside the band the cutter sweeps, or in too narrow a gap
                end
            end
            if obstacle.closed and #points >= 4 then
                -- Close the loop: the last point back to the first
                local last = #points - 1
                if PointSegmentDistance(x, y, points[last], points[last + 1], points[1], points[2]) < radius then
                    return false
                end
            end
        end
    end
    return true
end
```

- [ ] **Step 4: Add the two nudge searches**

They differ deliberately. A perimeter fastener that wandered into the field is no longer holding the edge down, so it only ever slides along its own edge.

```lua
-- =====================================================]]
function NudgePerimeter(obstacles, target, radius)
    -- Slides along its own edge, alternating to either side in R/2 steps. Never moves inward.
    local step = radius * 0.5
    if step <= 0.0 then
        return nil
    end
    local along_x, along_y = 1.0, 0.0
    if target.edge == "left" or target.edge == "right" then
        along_x, along_y = 0.0, 1.0
    end
    local distance = step
    while distance <= HoldDown.MaxSearch do
        for _, sign in ipairs({1.0, -1.0}) do
            local x = target.x + (along_x * distance * sign)
            local y = target.y + (along_y * distance * sign)
            if IsPointSafe(obstacles, x, y, radius) then
                return x, y
            end
        end
        distance = distance + step
    end
    return nil
end
-- =====================================================]]
function NudgeField(obstacles, target, radius)
    -- Spirals outward, testing rings at R/2 intervals, 8 angles per ring, first safe point wins.
    local step = radius * 0.5
    if step <= 0.0 then
        return nil
    end
    local distance = step
    while distance <= HoldDown.MaxSearch do
        for i = 0, 7 do
            local angle = (math.pi * 2.0 * i) / 8.0
            local x = target.x + (distance * math.cos(angle))
            local y = target.y + (distance * math.sin(angle))
            if IsPointSafe(obstacles, x, y, radius) then
                return x, y
            end
        end
        distance = distance + step
    end
    return nil
end
```

- [ ] **Step 5: Add the placement pass**

A target with no safe point is reported by coordinate and draws no marker. It is never silently dropped.

```lua
-- =====================================================]]
function PlaceTargets(obstacles, targets, radius)
    local placed = {}
    local rejected = {}
    for _, target in ipairs(targets) do
        if IsPointSafe(obstacles, target.x, target.y, radius) then
            table.insert(placed, {x = target.x, y = target.y})
        else
            local x, y
            if target.kind == "perimeter" then
                x, y = NudgePerimeter(obstacles, target, radius)
            else
                x, y = NudgeField(obstacles, target, radius)
            end
            if x ~= nil then
                table.insert(placed, {x = x, y = y})
            else
                table.insert(rejected, {x = target.x, y = target.y, kind = target.kind})
            end
        end
    end
    return placed, rejected
end
```

- [ ] **Step 6: Wire it into `main`**

Replace the drawing block from Task 5 Step 5 with:

```lua
    local min_x, min_y, max_x, max_y = SheetBounds()
    local targets = PerimeterTargets(min_x, min_y, max_x, max_y)
    for _, target in ipairs(FieldTargets(min_x, min_y, max_x, max_y)) do
        table.insert(targets, target)
    end

    local radius = ClearanceRadius()
    local obstacles = PrepareObstacles(vectors)
    local placed, rejected = PlaceTargets(obstacles, targets, radius)

    if #placed == 0 then
        DisplayMessageBox("Every position was rejected: none of the " .. #targets .. " target(s) is at least " ..
            string.format("%.4f", radius) .. " " .. HoldDown.UnitLabel .. " clear of all " .. #obstacles ..
            " vector(s) on this sheet.\n\nNothing was drawn and nothing was deleted.\n\n" ..
            "Hide layers you do not need kept clear, such as part labels or construction lines, and run again.")
        return false
    end

    ClearHoldDownLayer()
    local layer = HoldDownLayer()
    for _, position in ipairs(placed) do
        DrawMarker(layer, position.x, position.y)
    end
    HoldDown.job:Refresh2DView()

    local message = "Hold Down Helper\n\nMarked " .. #placed .. " position(s) on layer '" .. HoldDown.LayerName .. "'."
    if #rejected > 0 then
        message = message .. "\n\nCould not place " .. #rejected .. " position(s):"
        for _, position in ipairs(rejected) do
            message = message .. "\n  " .. position.kind .. " at " ..
                string.format("%.3f", position.x) .. ", " .. string.format("%.3f", position.y)
        end
    end
    if #skipped > 0 then
        message = message .. "\n\nWARNING: " .. #skipped .. " object(s) have no readable outline and were ignored. " ..
            "Grouped vectors do this. Ungroup them before trusting the result."
    end
    MessageBox(message)
    return true
```

- [ ] **Step 7: Package and have the user verify**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

| Case | Expected |
| --- | --- |
| A sheet with a few nested parts | No marker lands on or within R of a part; markers near parts have visibly shifted from the Task 5 positions |
| Measure a marker that moved | At least R from the nearest part outline |
| A perimeter marker that moved | Still on its own edge line — the same distance in from the sheet edge as its neighbors |
| A field marker that moved | Anywhere within `max_search` of where Task 5 put it |
| A sheet packed edge to edge with parts | Rejections listed by coordinate, and no marker drawn for them |
| A sheet completely covered by one huge part | "Every position was rejected", nothing drawn, previous markers left alone |
| A layer of part labels hidden | More positions succeed than with it shown — confirms the visibility escape hatch |
| An open vector (a single line) on the sheet | Markers keep R clear of it and the gadget does not error |

Ask the user to confirm the third row specifically: a perimeter marker must never move inward.

- [ ] **Step 8: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Keep hold-down positions clear of every vector, nudging by target type."
```

---

### Task 7: The drilling toolpath

**Files:**
- Modify: `HoldDownHelper/Hold_Down_Helper.lua`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `HoldDown` (including `HoldDown.Tool` from Task 4), `IdKey` from Task 1, `PlaceTargets` from Task 6.
- Produces:
  - `DeleteDimpleToolpath() -> number` (how many were deleted)
  - `SelectHoldDownMarkers() -> boolean`
  - `CreateDimpleToolpath() -> boolean`

- [ ] **Step 1: Add toolpath deletion**

Only toolpaths on the active sheet are touched. A toolpath of the same name on another sheet belongs to a run this one is not responsible for, and the spec scopes the gadget to the active sheet.

```lua
-- =====================================================]]
function DeleteDimpleToolpath()
    -- Re-running rebuilds rather than accumulates. Walks from the tail because the toolpath being
    -- looked for is the most recently created one; Find(UUID) fails overload resolution in V12.5.
    local toolpath_manager = ToolpathManager()
    local sheet_key = IdKey(HoldDown.job.SheetManager.ActiveSheetId)
    local doomed = {}
    local pos = toolpath_manager:GetTailPosition()
    while pos ~= nil do
        local toolpath
        toolpath, pos = toolpath_manager:GetPrev(pos)
        if toolpath ~= nil and toolpath.Name == HoldDown.ToolpathName and IdKey(toolpath.SheetId) == sheet_key then
            table.insert(doomed, toolpath)
        end
    end
    local deleted = 0
    for _, toolpath in ipairs(doomed) do
        local ok, removed = pcall(function()
            return toolpath_manager:DeleteToolpath(toolpath)
        end)
        if ok and removed then
            deleted = deleted + 1
        end
    end
    return deleted
end
```

- [ ] **Step 2: Add marker selection**

`CreateDrillingToolpath` works on the current selection, exactly as the profiling and pocketing calls do.

```lua
-- =====================================================]]
function SelectHoldDownMarkers()
    local selection = HoldDown.job.Selection
    selection:Clear()
    local layer = HoldDown.job.LayerManager:FindLayerWithName(HoldDown.LayerName)
    if layer == nil then
        return false
    end
    local sheet_key = IdKey(HoldDown.job.SheetManager.ActiveSheetId)
    local selected = false
    local pos = layer:GetHeadPosition()
    while pos ~= nil do
        local object
        object, pos = layer:GetNext(pos)
        if IdKey(object.SheetId) == sheet_key then
            local contour = object:GetContour()
            if contour ~= nil and not contour.IsOpen then
                selection:Add(object, true, true)
                selected = true
            end
        end
    end
    if selected then
        selection:GroupSelectionFinished()
    end
    return selected
end
```

- [ ] **Step 3: Add the toolpath**

Home position and safe Z come from the material block. The SDK's own drilling sample hardcodes `5.0` for both, which means 5 mm in the metric job it was written for and 5 **inches** in an imperial one — the bug that tripped a soft limit in Blum Drawer Maker. Copy the material-block form from `BlumDrawerJoinery.xlua:1250-1255` instead.

```lua
-- =====================================================]]
function CreateDimpleToolpath()
    if not SelectHoldDownMarkers() then
        return false
    end

    local picked = HoldDown.Tool
    local tool = Tool(picked.Name, Tool.VBIT)
    tool.InMM = picked.InMM
    tool.ToolDia = picked.ToolDia
    tool.Stepdown = picked.Stepdown
    tool.Stepover = picked.Stepover
    tool.RateUnits = picked.RateUnits
    tool.FeedRate = picked.FeedRate
    tool.PlungeRate = picked.PlungeRate
    tool.SpindleSpeed = picked.SpindleSpeed
    tool.ToolNumber = picked.ToolNumber
    tool.VBitAngle = picked.VBitAngle
    tool.ClearStepover = picked.ToolDia * 0.5

    -- Home position and safe Z MUST come from the material block. The SDK's drilling sample
    -- hardcodes 5.0 here, which is 5mm in the metric sample it came from and 5 INCHES in an
    -- imperial job -- that exact bug produced a rapid to Z+5.5 and a soft limit trip.
    local mtl_block = MaterialBlock()
    local mtl_box = mtl_block.MaterialBox
    local mtl_box_blc = mtl_box.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_box.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1

    local drill_data = DrillParameterData()
    drill_data.StartDepth = 0.0
    drill_data.CutDepth = HoldDown.DimpleDepth
    drill_data.DoPeckDrill = false
    drill_data.PeckRetractGap = 0.0
    drill_data.ProjectToolpath = false

    local geometry_selector = GeometrySelector()
    local create_2d_previews = true
    local display_warnings = true -- this call is new to this repo; let VCarve say why it refused
    local toolpath_manager = ToolpathManager()
    local ok, toolpath_id = pcall(function()
        return toolpath_manager:CreateDrillingToolpath(HoldDown.ToolpathName, tool, drill_data, pos_data,
            geometry_selector, create_2d_previews, display_warnings)
    end)
    if not ok then
        DisplayMessageBox("Could not create the '" .. HoldDown.ToolpathName .. "' toolpath: " .. tostring(toolpath_id))
        return false
    end
    if toolpath_id == nil then
        DisplayMessageBox("VCarve refused to create the '" .. HoldDown.ToolpathName .. "' toolpath.\n\n" ..
            "The markers are drawn on layer '" .. HoldDown.LayerName .. "'. You can create a drilling " ..
            "toolpath over them by hand.")
        return false
    end
    return true
end
```

- [ ] **Step 4: Wire it into `main` and write the completion message**

Replace the final drawing-and-message block from Task 6 Step 6 with:

```lua
    ClearHoldDownLayer()
    local layer = HoldDownLayer()
    for _, position in ipairs(placed) do
        DrawMarker(layer, position.x, position.y)
    end
    DeleteDimpleToolpath()
    local toolpath_made = CreateDimpleToolpath()
    HoldDown.job:Refresh2DView()

    local message = "Hold Down Helper\n\nMarked " .. #placed .. " position(s) on layer '" .. HoldDown.LayerName .. "'."
    if toolpath_made then
        message = message .. "\nCreated the '" .. HoldDown.ToolpathName .. "' toolpath."
    end
    if #rejected > 0 then
        message = message .. "\n\nCould not place " .. #rejected .. " position(s):"
        for _, position in ipairs(rejected) do
            message = message .. "\n  " .. position.kind .. " at " ..
                string.format("%.3f", position.x) .. ", " .. string.format("%.3f", position.y)
        end
    end
    if #skipped > 0 then
        message = message .. "\n\nWARNING: " .. #skipped .. " object(s) have no readable outline and were ignored. " ..
            "Grouped vectors do this. Ungroup them before trusting the result."
    end
    message = message .. "\n\nLook at the marked positions before you drill. This gadget keeps every fastener " ..
        "clear of every vector, but it cannot tell whether the material under one comes free during the job. " ..
        "A screw in a piece that is cut loose is worse than no screw at all." ..
        "\n\nDO NOT RE-ZERO between running this toolpath and running the job. Zero X and Y, run only " ..
        "'" .. HoldDown.ToolpathName .. "', drive the screws at the dimples, then run the job toolpaths " ..
        "WITHOUT re-zeroing. The dimples are in job coordinates; re-zeroing invalidates every one of them."
    MessageBox(message)
    return true
```

- [ ] **Step 5: Package and have the user verify**

```bash
pwsh ./deploy.ps1 -SourceFolder HoldDownHelper -Force
```

This step settles the four things the SDK does not document. Ask the user for each:

| Check | Expected |
| --- | --- |
| A toolpath named `Hold Down Dimples` appears | It exists and uses the chosen V-bit |
| Is each drill point at a marker's **center**? | Yes — if VCarve instead drills the circle's perimeter or refuses the vector, report back before going further |
| Preview the toolpath | Dimples appear at every marker, none anywhere else |
| Rapid height in the preview | Just above the material, not Z+5 — confirm against the material thickness |
| Cut depth | `dimple_depth` below the surface |
| Dimple width at the default 90-degree bit and 0.1" depth | About 0.2" — confirms the V-bit angle drives the width |
| A marker circle **smaller** than the bit | Does VCarve object? Record the answer |
| A marker circle **larger** than the bit | Does VCarve object? Record the answer |
| Run the gadget twice | One `Hold Down Dimples` toolpath, not two |
| Cancel the dialog on a job that already has markers | Markers and toolpath left exactly as they were |

If VCarve rejects a `Tool.VBIT` tool for a drilling toolpath, stop and report it — the spec's chosen output is then unavailable, and that is a design decision for the user, not a workaround to invent.

- [ ] **Step 6: Record what the checks showed**

Extend the Task 2 comment block with the four answers, so the next person does not have to rediscover them:

```lua
--   Drilling drills at the vector center  -> <yes/no, observed in VCarve on DATE>
--   CreateDrillingToolpath accepts VBIT   -> <yes/no>
--   VBitAngle drives the dimple width     -> <yes/no, measured width at 90deg / 0.1in>
--   Marker circle vs tool diameter        -> <what VCarve objected to, if anything>
```

- [ ] **Step 7: Commit**

```bash
git add HoldDownHelper/Hold_Down_Helper.lua
git commit -m "Dimple the hold-down positions with a V-bit drilling toolpath."
```

---

### Task 8: Document the gadget

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the finished gadget.
- Produces: nothing code depends on.

- [ ] **Step 1: Add the row to the gadget table**

In the table near the top of `README.md`, after the Blum Nesting Repair row:

```markdown
| Hold Down Helper | [`HoldDownHelper/`](HoldDownHelper/) | Finds places to screw a sheet to the spoilboard where no cutter will reach, and dimples them with a V-bit. |
```

The sentence below that table says the two Blum gadgets are meant to be used in sequence. Leave it alone and do not fold the new gadget into it — it is independent of both.

- [ ] **Step 2: Add the section**

Place it after the "Blum Nesting Repair" section and before "Installing":

```markdown
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
`R` is half the assumed cutter diameter plus half the screw head diameter plus a margin — 0.375" at the
defaults. Rejected perimeter positions slide along their own edge, never inward; rejected field positions
spiral outward. A position with nowhere safe to go is reported by coordinate rather than silently dropped.

Every **visible** vector on the active sheet is tested, on any layer. Hiding a layer excludes it, which is the
way to recover usable area when too many positions are rejected: hide part labels or construction lines, not
the parts themselves.

Re-running clears the `Hold Down` layer and rebuilds, so running it twice does not accumulate markers.

What it does not do:

- **It does not detect waste islands.** Clearance from every vector does not prove the material under a
  fastener stays attached to the sheet. A region fully enclosed by cut lines comes free during the job, and a
  screw in it releases a loose piece under a spinning cutter. Look at the positions before drilling.
- **It assumes one tool diameter for the whole sheet.** A job mixing a 1/8" and a 1/4" bit is tested as though
  the 1/4" ran everywhere. That loses usable area and never errs toward danger.
- **It does not read toolpaths.** A vector with no toolpath on it still blocks placement, and a toolpath whose
  vector was deleted does not.
- **It works on the active sheet only**, and clearing the `Hold Down` layer clears it across every sheet. Mark
  one sheet, drill it and run it before moving to the next.
```

- [ ] **Step 3: Check the links and folder names**

```bash
grep -n "Hold Down Helper" README.md
```

Expected: the table row and the section heading. The relative link `HoldDownHelper/` must match the real folder exactly — note that the folder is `HoldDownHelper` while the packaged gadget installs as `Hold_Down_Helper`, because `deploy.ps1` names the archive and its inner folder after the `.lua` file rather than the source folder.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Describe the Hold Down Helper in the top-level README."
```
