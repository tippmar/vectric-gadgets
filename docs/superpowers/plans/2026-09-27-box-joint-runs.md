# Box Joint Runs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A VCarve Pro V12.5 gadget that draws and machines a chain of 1 to 4 through-finger-jointed 90° corner pieces (open or closed), adds finger ends to an existing Blum Drawer Maker back or a single existing end, and proves the joint with a test cut — all sized from stock thickness and width the same way Blum Drawer Maker sizes a drawer side.

**Architecture:** Five files under `BoxJointRuns/`, loaded by `loadfile` from the entry point exactly as `Blum_Drawer_Maker.lua` loads its `.xlua` modules. Two global tables hold all state: `Run` (stock, finger/joint/groove settings, mode, chain rows, existing-mode inputs, units) and `Milling` (the job handle, the four picked tools, their pocket allowances, part gap, tabs, profile finish, and layer/toolpath name constants). One routine, `DrawFingerEnd`, draws every finger end in every mode, generalizing Blum Drawer Maker's `MySideFingers`/`MyFrontFingers` over an explicit direction pair instead of hardcoded axes. Geometry and toolpath creation are copied from Blum Drawer Maker where the math already exists there, renamed onto `Run`/`Milling`, and written fresh where the spec's phase rule and four modes have no Blum equivalent.

**Tech Stack:** Lua 5.1 as hosted by VCarve Pro V12.5, the Vectric Gadget Lua API, `deploy.ps1` for packaging.

**Spec:** [`docs/superpowers/specs/2026-09-27-box-joint-runs-design.md`](../specs/2026-09-27-box-joint-runs-design.md) — read it before Task 1. This plan implements it exactly; it adds nothing beyond it.

## Global Constraints

- **`Box_Joint_Runs.lua` must begin with the exact line `-- VECTRIC LUA SCRIPT`**, or VCarve refuses to run it.
- **Line endings are CRLF**, matching every file in `BlumDrawerMaker/`. `sed`/`awk` in this environment strip CR — use `perl -pi -e 's/\r?\n/\r\n/'` on any file you edit here.
- **American spelling everywhere** — code, comments, dialog copy, docs, commit messages.
- **This gadget shares no code and no registry keys with Blum Drawer Maker.** Everything it needs is copied in, renamed onto `Run`/`Milling`, and stored under its own `BoxJointRuns` registry section.
- **`require "strict"` is in force.** Every global must be assigned at the main chunk before any function reads it.
- **Global state lives in exactly two tables:** `Run` for settings and inputs, `Milling` for the job handle and tools. No third global table.
- **Home position and safe Z come from `MaterialBlock()`**, never a hardcoded number — copy the pattern at `BlumDrawerJoinery.xlua:1071-1076`.
- **Units:** `Run.Cal` is `1.0` in an imperial job and `25.4` in a metric one; `Run.InMM` mirrors `MaterialBlock().InMM`. Registry values are stored in **job units**, per unit system, exactly as `BlumDrawerRegistry.xlua` does — no normalizing to mm.
- **Packaging:** `pwsh ./deploy.ps1 -SourceFolder BoxJointRuns` from the repository root, producing `Box_Joint_Runs.vgadget` (gitignored).
- **Installing for a test run:** install the `.vgadget` through the Vectric UI, or unpack it into `C:\ProgramData\Vectric\VCarve Pro\V12.5\Gadgets\Box_Joint_Runs\`. Reinstalling replaces the previous copy.
- **VCarve's paste bug:** dialog fields discard pasted values. Whenever a verification step asks the user to enter a number, type it and tab out — never paste.
- **Nothing in this repository runs locally.** Every task ends with the user packaging the gadget and running it in VCarve Pro V12.5; there is no Lua interpreter here.
- **The phase rule (spec, "The phase rule"):** every finger end is either **Finger at bottom** (band 0, at the bottom/groove edge, is a finger) or **Gap at bottom** (band 0 is a gap). Bands are numbered 0 to n−1 from the bottom edge and alternate. Two mating ends are always opposite phases.

## Verified API reference

Carried over from Hold Down Helper's own verification (`docs/superpowers/plans/2026-09-20-hold-down-helper.md`) and cross-checked again here at the cited `BlumDrawerMaker` lines. Use these spellings.

| Purpose | Call | Source |
| --- | --- | --- |
| Job handle | `VectricJob()`, `job.Exists` | `Blum_Drawer_Maker.lua:67-72` |
| Units and sheet size | `MaterialBlock()` → `.InMM`, `.Thickness`, `.Width`, `.Height`, `.MaterialBox` | `BlumDrawerTools.xlua:1379-1397` |
| Material extents | `mtl_block.MaterialBox` → `.BLC`, `.TRC` | `BlumDrawerJoinery.xlua:1071-1073` |
| Sheets | `job.SheetManager`, `.ActiveSheetId`, `.NumberOfSheets`, `:GetSheetIds()`, `:GetSheetName(id)`, `:RenameSheet(id, name)`, `:CreateNewSheet(name)`, `:ResizeSheet(id, w, h, thickness, bool)` | `BlumDrawerTools.xlua:108-130` |
| Layers | `job.LayerManager:GetLayerWithName(name)` (creates), `:FindLayerWithName(name)` (nil if absent), `:RemoveLayer(layer)`, `layer.IsEmpty`, `layer:SetColor(r,g,b)`, `layer:AddObject(CreateCadContour(contour), true)` | `BlumDrawerTools.xlua:1339,1496-1499,1543,1472` |
| Geometry | `Point2D(x,y)`, `Polar2D(pt, deg, dist)`, `Contour(0.0)`, `:AppendPoint(pt)`, `:LineTo(pt)`, `:ArcTo(pt, bulge)`, `CreateCadContour(contour)` | `BlumDrawerTools.xlua:1334,1418-1445` |
| Selection | `job.Selection`, `:Clear()`, `:Add(obj,true,true)`, `:GroupSelectionFinished()`, `job:SelectAllVectors()`, `selection.IsEmpty`, `:GetBoundingBox().TRC.x` | `BlumDrawerTools.xlua:83-93` |
| Tool | `Tool(name, Tool.END_MILL)`, `.InMM`, `.ToolDia`, `.Stepdown`, `.Stepover`, `.RateUnits`, `.FeedRate`, `.PlungeRate`, `.SpindleSpeed`, `.ToolNumber` | `BlumDrawerJoinery.xlua:1061-1069` |
| Toolpath position/pocket/profile data | `ToolpathPosData()`, `:SetHomePosition(x,y,z)`, `.SafeZGap`, `PocketParameterData()`, `ProfileParameterData()`, `RampingData()`, `lead_in_out_data` (global `LeadInOutData()`) | `BlumDrawerJoinery.xlua:1071-1313` |
| Toolpath creation | `ToolpathManager()`, `:CreatePocketingToolpath(name, tool, area_clear_tool, pocket_data, pos_data, geometry_selector, create_2d_previews, display_warnings)`, `:CreateProfilingToolpath(name, tool, profile_data, ramping_data, lead_in_out_data, pos_data, geometry_selector, create_2d_previews, display_warnings)`, `:GetHeadPosition()`/`:GetNext`, `:GetTailPosition()`/`:GetPrev`, `:DeleteToolpath(tp)`, `:RecalculateToolpath(tp)`, `:ReorderToolpathList(UUID_List)` | `BlumDrawerJoinery.xlua:1000-1435` |
| Geometry selector | `GeometrySelector()`, `.GeometryFilterUsed`, `.OnlyOnLayers`, `.SelectClosed`, `.SelectOpen`, `:AddLayerName(name)`, `:SaveSelectorData(tp)` | `BlumDrawerJoinery.xlua:1356-1378` |
| UUID | `luaUUID(raw_id):AsString()`, `UUID_List()`, `:AddTail(id)` | `BlumDrawerJoinery.xlua:150-193` |
| Dialog | `HTML_Dialog(true, html, w, h, title)`, `:ShowDialog()`, `:AddDoubleField(id,v)`/`:GetDoubleField(id)`, `:AddIntegerField`/`:GetIntegerField`, `:AddCheckBox`/`:GetCheckBox`, `:AddDropDownList(id, current)`/`:GetDropDownListValue(id)`, `:AddLabelField`/`:UpdateLabelField` | `BlumDrawerDialog.xlua:456-486,1195-1250` |
| Tool picker | `:AddToolPicker(buttonId, labelId, toolDbId)`, `:AddToolPickerValidToolType(buttonId, Tool.END_MILL)`, `:GetTool(buttonId)` (falsy when unchanged), `ToolDBId()` | `BlumDrawerDialog.xlua:1017-1062` |
| Registry | `Registry(name)`, `:GetDouble(key, default)`/`:SetDouble`, `:GetInt`/`:SetInt`, `:GetBool`/`:SetBool`, `:GetString`/`:SetString` | `BlumDrawerRegistry.xlua` (pattern throughout) |
| Redraw | `job:Refresh2DView()` | `BlumDrawerTools.xlua:118` |

---

### Task 1: Scaffold, shared dialog, settings persistence

Everything after this task assumes a running gadget with a validated, persisted settings table and a `Mode` field fixed to `"Test Cut"`. No drawing happens yet — pressing OK writes the registry and reports success.

**Files:**
- Create: `BoxJointRuns/Box_Joint_Runs.lua`
- Create: `BoxJointRuns/BoxJointRegistry.xlua`
- Create: `BoxJointRuns/BoxJointDialog.xlua`
- Create: `BoxJointRuns/License.txt`
- Create: `BoxJointRuns/README.md`
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: nothing.
- Produces: globals `Run` (table), `Milling` (table); `main(script_path)`; `GetMaterialSettings() -> nil` (sets `Run.Cal`, `Run.InMM`, `Run.UnitLabel`); `SettingDefaults() -> table` (flat, keyed by field name, chosen per `Run.InMM`); `SettingsKey(name) -> string`; `SettingsRead() -> nil`; `SettingsWrite() -> nil`; `BuildDialog() -> nil` (sets `Run.dialog`); `ShowSettingsDialog() -> boolean`; `ValidateSettings() -> boolean, string_or_nil`; `AutoFingerCount(width) -> integer`; `RecomputeDerived() -> nil` (sets `Run.FingerCount`, `Run.FingerWidth`). Fields on `Run`: `Cal, InMM, UnitLabel, RegName, Mode, StockT, StockW, FingerAuto, FingerCountManual, FingerCount, FingerWidth, JointStyle, FingerClearance, GrooveOn, GrooveInset, GrooveWidth, GrooveDepth, dialog`. Fields on `Milling`: `job, ProfileTool, FingerTool, FingerClearTool, DadoTool, FingerAllowance, FingerClearAllowance, GrooveAllowance, ProfileFinishAllowance, PartGap, ProfileTabs, ProfileFinish`.

- [ ] **Step 1: License and README**

Copy `BlumDrawerMaker/License.txt` to `BoxJointRuns/License.txt` verbatim (it is the zlib-style notice every gadget in this repo ships, with no gadget-specific text in it).

Write `BoxJointRuns/README.md`:

```markdown
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
```

- [ ] **Step 2: The registry module**

```lua
-- VECTRIC LUA SCRIPT
-- =====================================================]]
-- Box Joint Runs is a separate gadget from Blum Drawer Maker: it shares no code and no
-- registry settings with it. Its own settings live under the "BoxJointRuns" section,
-- one row per unit system, exactly as BlumDrawerRegistry.xlua keeps Blum's.
-- =====================================================]]
local IMPERIAL_DEFAULTS = {
    StockT = 0.7500,
    StockW = 6.0000,
    FingerAuto = true,
    FingerCountManual = 5,
    JointStyle = "Through",
    FingerClearance = 0.0050,
    GrooveOn = true,
    GrooveInset = 0.5000,
    GrooveWidth = 0.2500,
    GrooveDepth = 0.2500,
    FingerAllowance = 0.0000,
    FingerClearAllowance = 0.0000,
    GrooveAllowance = 0.0000,
    ProfileFinishAllowance = 0.0000,
    PartGap = 0.7500,
    ProfileTabs = true,
    ProfileFinish = false,
    Mode = "Test Cut"
}
local METRIC_DEFAULTS = {
    StockT = 19.0000,
    StockW = 150.0000,
    FingerAuto = true,
    FingerCountManual = 5,
    JointStyle = "Through",
    FingerClearance = 0.1270,
    GrooveOn = true,
    GrooveInset = 12.7000,
    GrooveWidth = 6.3500,
    GrooveDepth = 6.3500,
    FingerAllowance = 0.0000,
    FingerClearAllowance = 0.0000,
    GrooveAllowance = 0.0000,
    ProfileFinishAllowance = 0.0000,
    PartGap = 19.0500,
    ProfileTabs = true,
    ProfileFinish = false,
    Mode = "Test Cut"
}
-- =====================================================]]
function SettingDefaults()
    if Run.InMM then
        return METRIC_DEFAULTS
    end
    return IMPERIAL_DEFAULTS
end
-- =====================================================]]
function SettingsKey(name)
    if Run.InMM then
        return "Metric." .. name
    end
    return "Imperial." .. name
end
-- =====================================================]]
function SettingsRead()
    local registry = Registry(Run.RegName)
    local defaults = SettingDefaults()
    Run.StockT = registry:GetDouble(SettingsKey("StockT"), defaults.StockT)
    Run.StockW = registry:GetDouble(SettingsKey("StockW"), defaults.StockW)
    Run.FingerAuto = registry:GetBool(SettingsKey("FingerAuto"), defaults.FingerAuto)
    Run.FingerCountManual = registry:GetInt(SettingsKey("FingerCountManual"), defaults.FingerCountManual)
    Run.JointStyle = registry:GetString(SettingsKey("JointStyle"), defaults.JointStyle)
    Run.FingerClearance = registry:GetDouble(SettingsKey("FingerClearance"), defaults.FingerClearance)
    Run.GrooveOn = registry:GetBool(SettingsKey("GrooveOn"), defaults.GrooveOn)
    Run.GrooveInset = registry:GetDouble(SettingsKey("GrooveInset"), defaults.GrooveInset)
    Run.GrooveWidth = registry:GetDouble(SettingsKey("GrooveWidth"), defaults.GrooveWidth)
    Run.GrooveDepth = registry:GetDouble(SettingsKey("GrooveDepth"), defaults.GrooveDepth)
    Run.Mode = registry:GetString(SettingsKey("Mode"), defaults.Mode)
    Milling.FingerAllowance = registry:GetDouble(SettingsKey("FingerAllowance"), defaults.FingerAllowance)
    Milling.FingerClearAllowance = registry:GetDouble(SettingsKey("FingerClearAllowance"), defaults.FingerClearAllowance)
    Milling.GrooveAllowance = registry:GetDouble(SettingsKey("GrooveAllowance"), defaults.GrooveAllowance)
    Milling.ProfileFinishAllowance = registry:GetDouble(SettingsKey("ProfileFinishAllowance"), defaults.ProfileFinishAllowance)
    Milling.PartGap = registry:GetDouble(SettingsKey("PartGap"), defaults.PartGap)
    Milling.ProfileTabs = registry:GetBool(SettingsKey("ProfileTabs"), defaults.ProfileTabs)
    Milling.ProfileFinish = registry:GetBool(SettingsKey("ProfileFinish"), defaults.ProfileFinish)
end
-- =====================================================]]
function SettingsWrite()
    local registry = Registry(Run.RegName)
    registry:SetDouble(SettingsKey("StockT"), Run.StockT)
    registry:SetDouble(SettingsKey("StockW"), Run.StockW)
    registry:SetBool(SettingsKey("FingerAuto"), Run.FingerAuto)
    registry:SetInt(SettingsKey("FingerCountManual"), Run.FingerCountManual)
    registry:SetString(SettingsKey("JointStyle"), Run.JointStyle)
    registry:SetDouble(SettingsKey("FingerClearance"), Run.FingerClearance)
    registry:SetBool(SettingsKey("GrooveOn"), Run.GrooveOn)
    registry:SetDouble(SettingsKey("GrooveInset"), Run.GrooveInset)
    registry:SetDouble(SettingsKey("GrooveWidth"), Run.GrooveWidth)
    registry:SetDouble(SettingsKey("GrooveDepth"), Run.GrooveDepth)
    registry:SetString(SettingsKey("Mode"), Run.Mode)
    registry:SetDouble(SettingsKey("FingerAllowance"), Milling.FingerAllowance)
    registry:SetDouble(SettingsKey("FingerClearAllowance"), Milling.FingerClearAllowance)
    registry:SetDouble(SettingsKey("GrooveAllowance"), Milling.GrooveAllowance)
    registry:SetDouble(SettingsKey("ProfileFinishAllowance"), Milling.ProfileFinishAllowance)
    registry:SetDouble(SettingsKey("PartGap"), Milling.PartGap)
    registry:SetBool(SettingsKey("ProfileTabs"), Milling.ProfileTabs)
    registry:SetBool(SettingsKey("ProfileFinish"), Milling.ProfileFinish)
end
-- =============== End of File =========================]]
```

Chain rows, end dropdowns, and the two existing-mode input blocks are added to this same
file's `IMPERIAL_DEFAULTS`/`METRIC_DEFAULTS`/`SettingsRead`/`SettingsWrite` in Tasks 4-6 —
each of those tasks lists the exact lines to add.

- [ ] **Step 3: The dialog module**

`BoxJointDialog.xlua` builds the HTML dialog and reads it back. Only the shared fields and
a one-option Mode selector exist yet; Tasks 4-6 append fields and `<option>` values here.

```lua
-- VECTRIC LUA SCRIPT
-- =====================================================]]
function BuildDialog()
    local html = [[<!DOCTYPE html><html><head><title>Box Joint Runs</title>
<style>
body { font-family: Arial, sans-serif; font-size: 12px; }
table { border-collapse: collapse; }
td { padding: 3px 6px; }
h2 { font-size: 13px; margin: 8px 0 2px 0; }
</style></head><body>
<table>
<tr><td colspan="4"><h2>Stock</h2></td></tr>
<tr>
  <td><label title="Thickness of every piece in this run.">Thickness (T)</label></td>
  <td><input type="text" id="Run.StockT" size="10"/></td>
  <td><label title="The dimension the fingers run across -- a drawer's height.">Width (W)</label></td>
  <td><input type="text" id="Run.StockW" size="10"/></td>
</tr>
<tr><td colspan="4"><h2>Fingers</h2></td></tr>
<tr>
  <td><label title="Uncheck to enter a finger count by hand.">Automatic count</label></td>
  <td><input type="checkbox" id="Run.FingerAuto"/></td>
  <td><label title="Used only when Automatic count is unchecked.">Manual count</label></td>
  <td><input type="text" id="Run.FingerCountManual" size="10"/></td>
</tr>
<tr>
  <td><label title="Blind styles are excluded: any piece can be flipped face for face.">Joint style</label></td>
  <td>
    <select id="Run.JointStyle" size="1">
      <option value="Through">Through</option>
      <option value="Dog Bone">Dog Bone</option>
      <option value="T-Bone">T-Bone</option>
    </select>
  </td>
  <td><label title="Gap opened beyond the finger's nominal width, split between both sides.">Finger clearance</label></td>
  <td><input type="text" id="Run.FingerClearance" size="10"/></td>
</tr>
<tr><td colspan="4"><h2>Bottom groove</h2></td></tr>
<tr>
  <td><label>Groove on</label></td>
  <td><input type="checkbox" id="Run.GrooveOn"/></td>
  <td><label title="From the bottom edge to the near side of the groove.">Inset</label></td>
  <td><input type="text" id="Run.GrooveInset" size="10"/></td>
</tr>
<tr>
  <td><label>Groove width</label></td>
  <td><input type="text" id="Run.GrooveWidth" size="10"/></td>
  <td><label>Groove depth</label></td>
  <td><input type="text" id="Run.GrooveDepth" size="10"/></td>
</tr>
<tr><td colspan="4"><h2>Tools</h2></td></tr>
<tr>
  <td><label>Profile bit</label></td>
  <td><input id="ToolChooseProfile" class="LuaButton" type="button" value="Choose"/> <label id="ToolNameProfile"></label></td>
  <td colspan="2"></td>
</tr>
<tr>
  <td><label>Finger bit</label></td>
  <td><input id="ToolChooseFinger" class="LuaButton" type="button" value="Choose"/> <label id="ToolNameFinger"></label></td>
  <td><label>Pocket allowance</label></td>
  <td><input type="text" id="Milling.FingerAllowance" size="10"/></td>
</tr>
<tr>
  <td><label>Finger clear bit</label></td>
  <td><input id="ToolChooseFingerClear" class="LuaButton" type="button" value="Choose"/> <label id="ToolNameFingerClear"></label></td>
  <td><label>Pocket allowance</label></td>
  <td><input type="text" id="Milling.FingerClearAllowance" size="10"/></td>
</tr>
<tr>
  <td><label>Dado bit</label></td>
  <td><input id="ToolChooseDado" class="LuaButton" type="button" value="Choose"/> <label id="ToolNameDado"></label></td>
  <td><label>Pocket allowance</label></td>
  <td><input type="text" id="Milling.GrooveAllowance" size="10"/></td>
</tr>
<tr><td colspan="4"><h2>Cutting</h2></td></tr>
<tr>
  <td><label title="Minimum gap left between parts on the sheet.">Part gap</label></td>
  <td><input type="text" id="Milling.PartGap" size="10"/></td>
  <td><label>Tabs</label></td>
  <td><input type="checkbox" id="Milling.ProfileTabs"/></td>
</tr>
<tr>
  <td><label title="Roughs to this allowance, then a full-depth finishing pass takes it off.">Profile finishing pass</label></td>
  <td><input type="checkbox" id="Milling.ProfileFinish"/></td>
  <td><label>Finish allowance</label></td>
  <td><input type="text" id="Milling.ProfileFinishAllowance" size="10"/></td>
</tr>
<tr><td colspan="4"><h2>Mode</h2></td></tr>
<tr>
  <td><label>Mode</label></td>
  <td colspan="3">
    <select id="Run.Mode" size="1">
      <option value="Test Cut">Test cut</option>
    </select>
  </td>
</tr>
<tr><td colspan="4"><hr/></td></tr>
<tr>
  <td><input id="InquiryHelpMain" class="LuaButton" type="button" value="Help"/></td>
  <td class="alert" id="GadgetName.Alert" colspan="2"></td>
  <td><input id="ButtonOK" class="FormButton" type="button" value="OK"/>
      <input id="ButtonCancel" class="FormButton" type="button" value="Cancel"/></td>
</tr>
</table>
</body></html>]]
    Run.dialog = HTML_Dialog(true, html, 620, 560, "Box Joint Runs " .. Run.UnitLabel)
    Run.dialog:AddDoubleField("Run.StockT", Run.StockT)
    Run.dialog:AddDoubleField("Run.StockW", Run.StockW)
    Run.dialog:AddCheckBox("Run.FingerAuto", Run.FingerAuto)
    Run.dialog:AddIntegerField("Run.FingerCountManual", Run.FingerCountManual)
    Run.dialog:AddDropDownList("Run.JointStyle", Run.JointStyle)
    Run.dialog:AddDoubleField("Run.FingerClearance", Run.FingerClearance)
    Run.dialog:AddCheckBox("Run.GrooveOn", Run.GrooveOn)
    Run.dialog:AddDoubleField("Run.GrooveInset", Run.GrooveInset)
    Run.dialog:AddDoubleField("Run.GrooveWidth", Run.GrooveWidth)
    Run.dialog:AddDoubleField("Run.GrooveDepth", Run.GrooveDepth)
    Run.dialog:AddDoubleField("Milling.FingerAllowance", Milling.FingerAllowance)
    Run.dialog:AddDoubleField("Milling.FingerClearAllowance", Milling.FingerClearAllowance)
    Run.dialog:AddDoubleField("Milling.GrooveAllowance", Milling.GrooveAllowance)
    Run.dialog:AddDoubleField("Milling.PartGap", Milling.PartGap)
    Run.dialog:AddCheckBox("Milling.ProfileTabs", Milling.ProfileTabs)
    Run.dialog:AddCheckBox("Milling.ProfileFinish", Milling.ProfileFinish)
    Run.dialog:AddDoubleField("Milling.ProfileFinishAllowance", Milling.ProfileFinishAllowance)
    Run.dialog:AddDropDownList("Run.Mode", Run.Mode)
    Run.dialog:AddToolPicker("ToolChooseProfile", "ToolNameProfile", ToolDBId())
    Run.dialog:AddToolPickerValidToolType("ToolChooseProfile", Tool.END_MILL)
    Run.dialog:AddToolPicker("ToolChooseFinger", "ToolNameFinger", ToolDBId())
    Run.dialog:AddToolPickerValidToolType("ToolChooseFinger", Tool.END_MILL)
    Run.dialog:AddToolPicker("ToolChooseFingerClear", "ToolNameFingerClear", ToolDBId())
    Run.dialog:AddToolPickerValidToolType("ToolChooseFingerClear", Tool.END_MILL)
    Run.dialog:AddToolPicker("ToolChooseDado", "ToolNameDado", ToolDBId())
    Run.dialog:AddToolPickerValidToolType("ToolChooseDado", Tool.END_MILL)
end
-- =====================================================]]
function ShowSettingsDialog()
    BuildDialog()
    if not Run.dialog:ShowDialog() then
        return false
    end
    Run.StockT = math.abs(Run.dialog:GetDoubleField("Run.StockT"))
    Run.StockW = math.abs(Run.dialog:GetDoubleField("Run.StockW"))
    Run.FingerAuto = Run.dialog:GetCheckBox("Run.FingerAuto")
    Run.FingerCountManual = Run.dialog:GetIntegerField("Run.FingerCountManual")
    Run.JointStyle = Run.dialog:GetDropDownListValue("Run.JointStyle")
    Run.FingerClearance = math.abs(Run.dialog:GetDoubleField("Run.FingerClearance"))
    Run.GrooveOn = Run.dialog:GetCheckBox("Run.GrooveOn")
    Run.GrooveInset = math.abs(Run.dialog:GetDoubleField("Run.GrooveInset"))
    Run.GrooveWidth = math.abs(Run.dialog:GetDoubleField("Run.GrooveWidth"))
    Run.GrooveDepth = math.abs(Run.dialog:GetDoubleField("Run.GrooveDepth"))
    Run.Mode = Run.dialog:GetDropDownListValue("Run.Mode")
    -- Allowances are signed, as Blum Drawer Maker's are: no math.abs here.
    Milling.FingerAllowance = Run.dialog:GetDoubleField("Milling.FingerAllowance")
    Milling.FingerClearAllowance = Run.dialog:GetDoubleField("Milling.FingerClearAllowance")
    Milling.GrooveAllowance = Run.dialog:GetDoubleField("Milling.GrooveAllowance")
    Milling.PartGap = math.abs(Run.dialog:GetDoubleField("Milling.PartGap"))
    Milling.ProfileTabs = Run.dialog:GetCheckBox("Milling.ProfileTabs")
    Milling.ProfileFinish = Run.dialog:GetCheckBox("Milling.ProfileFinish")
    Milling.ProfileFinishAllowance = math.abs(Run.dialog:GetDoubleField("Milling.ProfileFinishAllowance"))
    if Run.dialog:GetTool("ToolChooseProfile") then
        Milling.ProfileTool = Run.dialog:GetTool("ToolChooseProfile")
    end
    if Run.dialog:GetTool("ToolChooseFinger") then
        Milling.FingerTool = Run.dialog:GetTool("ToolChooseFinger")
    end
    if Run.dialog:GetTool("ToolChooseFingerClear") then
        Milling.FingerClearTool = Run.dialog:GetTool("ToolChooseFingerClear")
    end
    if Run.dialog:GetTool("ToolChooseDado") then
        Milling.DadoTool = Run.dialog:GetTool("ToolChooseDado")
    end
    return true
end
-- =============== End of File =========================]]
```

- [ ] **Step 4: Finger math and validation, in the entry-point file**

```lua
function AutoFingerCount(width)
    -- Blum Drawer Maker's AutoFingerCount (BlumDrawerTools.xlua:1707), renamed onto Run/Milling: one finger
    -- per inch of width, never so many the finger bit cannot cut them, never fewer than 3.
    local target = Run.InMM and 25.4 or 1.0
    local count = math.floor(width / target + 0.5)
    local max_count = math.floor(width / (Milling.FingerTool.ToolDia / 0.70))
    if count > max_count then
        count = max_count
    end
    if count < 3 then
        count = 3
    end
    return count
end
-- =====================================================]]
function RecomputeDerived()
    if Run.FingerAuto then
        Run.FingerCount = AutoFingerCount(Run.StockW)
    else
        Run.FingerCount = math.max(3, Run.FingerCountManual)
    end
    Run.FingerWidth = Run.StockW / Run.FingerCount
end
-- =====================================================]]
function ValidateSettings()
    if Milling.ProfileTool == nil or Milling.FingerTool == nil or Milling.FingerClearTool == nil then
        return false, "Choose the profile bit, the finger bit, and the finger clear bit."
    end
    if Run.GrooveOn and Milling.DadoTool == nil then
        return false, "Choose the dado bit, or turn the bottom groove off."
    end
    if Milling.ProfileTool.InMM ~= Run.InMM then
        return false, "Profile bit units do not match the job units."
    end
    if Milling.FingerTool.InMM ~= Run.InMM then
        return false, "Finger bit units do not match the job units."
    end
    if Milling.FingerClearTool.InMM ~= Run.InMM then
        return false, "Finger clear bit units do not match the job units."
    end
    if Run.GrooveOn and Milling.DadoTool.InMM ~= Run.InMM then
        return false, "Dado bit units do not match the job units."
    end
    RecomputeDerived()
    if Run.FingerWidth < (Milling.FingerTool.ToolDia / 0.70) then
        return false, "Finger width " .. string.format("%.4f", Run.FingerWidth) ..
            " is too narrow for the finger bit. Reduce the finger count or increase the width."
    end
    if Milling.ProfileTool.ToolDia >= Milling.PartGap then
        return false, "Profile bit is too large for the part gap."
    end
    return true, nil
end
```

- [ ] **Step 5: The entry point**

```lua
-- VECTRIC LUA SCRIPT
--[[
-- Gadgets are an entirely optional add-in to Vectric's core software products.
-- They are provided 'as-is', without any express or implied warranty, and you make use of them entirely at your own risk.
-- In no event will the author(s) or Vectric Ltd. be held liable for any damages arising from their use.
-- Permission is granted to anyone to use this software for any purpose,
-- including commercial applications, and to alter it and redistribute it freely,
-- subject to the following restrictions:
-- 1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.
--    If you use this software in a product, an acknowledgement in the product documentation would be appreciated but is not required.
-- 2. Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software.
-- 3. This notice may not be removed or altered from any source distribution.
-- ====================================================================================================================================
-- Box Joint Runs borrows its finger-joint math and dialog/toolpath plumbing from this repository's own Blum
-- Drawer Maker, which is itself based on Easy Drawer Maker, originally written by JimAndi Gadgets, 2019.
]] -- =====================================================]]
require "strict"
Run = {}
Milling = {}
Run.RegName = "BoxJointRuns"
-- =====================================================]]
function GetMaterialSettings()
    local mtl_block = MaterialBlock()
    if mtl_block.InMM then
        Run.InMM = true
        Run.Cal = 25.4
        Run.UnitLabel = "(mm)"
    else
        Run.InMM = false
        Run.Cal = 1.0
        Run.UnitLabel = "(in)"
    end
end
-- =====================================================]]
function main(script_path)
    Milling.job = VectricJob()
    if not Milling.job.Exists then
        DisplayMessageBox("Error: Box Joint Runs cannot run without a job. Create a new file first, " ..
            "specifying the material dimensions.")
        return false
    end
    local Tools
    Tools = assert(loadfile(script_path .. "\\BoxJointRegistry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BoxJointDialog.xlua"))(Tools)
    GetMaterialSettings()
    SettingsRead()
    local looping = true
    while looping do
        if not ShowSettingsDialog() then
            return true -- Cancel
        end
        local ok, message = ValidateSettings()
        if ok then
            looping = false
        else
            PresentMessage("Unable to Proceed!", "Error", message)
        end
    end
    SettingsWrite()
    DisplayMessageBox("Settings saved. Mode: " .. Run.Mode .. ". Finger count: " .. tostring(Run.FingerCount) ..
        ". Finger width: " .. string.format("%.4f", Run.FingerWidth))
    return true
end
-- =============== End of File =========================]]
```

`PresentMessage` is Blum Drawer Maker's own alert wrapper (`BlumDrawerTools.xlua:1865`); copy it verbatim into this
file too (it has no dependency on `Drawer`/`Milling` fields beyond the three arguments it is called with).

- [ ] **Step 6: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| First run | Install the gadget, run it on an imperial job | Dialog opens titled "Box Joint Runs (in)"; Mode shows only "Test cut" |
| No tools chosen | Leave all four tool pickers unset, click OK | "Choose the profile bit, the finger bit, and the finger clear bit." — dialog reopens |
| Groove on, no dado bit | Pick profile/finger/finger clear bits, leave groove on with no dado bit, click OK | "Choose the dado bit, or turn the bottom groove off." |
| All tools chosen, groove off | Pick profile/finger/finger clear bits (any small end mills), turn groove off, click OK | Message box: "Settings saved. Mode: Test Cut. Finger count: N. Finger width: X.XXXX" |
| Second run | Run the gadget again | Every field shows the values just entered |

- [ ] **Step 7: Commit**

```bash
git add BoxJointRuns/Box_Joint_Runs.lua BoxJointRuns/BoxJointRegistry.xlua BoxJointRuns/BoxJointDialog.xlua BoxJointRuns/License.txt BoxJointRuns/README.md
git commit -m "Scaffold Box Joint Runs: dialog, settings, and validation."
```

---

### Task 2: Finger-end routine and Test cut geometry

Draws the two Test cut stubs (one Finger-at-bottom end, one Gap-at-bottom end) on the correct
thickness sheet, with groove and labels — no toolpaths yet.

**Files:**
- Create: `BoxJointRuns/BoxJointGeometry.xlua`
- Modify: `BoxJointRuns/Box_Joint_Runs.lua` (load the new module; call `RunTestCut()`)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `Run`, `Milling` from Task 1, including `Run.FingerCount`, `Run.FingerWidth` from `RecomputeDerived()`.
- Produces: `IdKey(raw_id) -> string`; `FormatThickness(t) -> string`; `ThicknessTag(t) -> string`; `GetDistance(a,b) -> number`; `PointAlong(pa,pb,fraction) -> Point2D`; `TabCountForEdge(length) -> integer`; `AddProfileTabs(cad_contour, pt1, pt2, pt3, pt4) -> boolean`; `DrawBox(p1,p2,p3,p4,layer_name) -> CadContour`; `DrawWriter(text, pt, size, layer_name, angle) -> boolean`; `OccupiedMaxX() -> number_or_nil`; `OpenSpaceStart() -> Point2D`; `ActivateThicknessSheet(thickness) -> nil`; `DrawFingerEnd(corner, dir_into, dir_across, phase, layer_name) -> boolean`; `DrawPieceOutline(origin, length, up_angle, layer_name) -> pt_bl, pt_tl, pt_tr, pt_br, cad_contour`; `DrawGroove(origin, length, up_angle, layer_name) -> boolean`; `LabelPiece(origin, index, length, width, thickness, layer_name) -> boolean`; `RunTestCut() -> boolean`. Layer/toolpath name constants on `Milling`: `LNProfile = "BJR Profile"`, `LNFingers = "BJR Fingers"`, `LNGroove = "BJR Groove"`, `LNLabels = "BJR Labels"` (each gets `ThicknessTag(Run.StockT)` appended once, by `ApplyThicknessLayerNames() -> nil`, added in this task).

- [ ] **Step 1: Copy the small geometry helpers verbatim, renamed**

Create `BoxJointRuns/BoxJointGeometry.xlua` starting with the same license header as
`Box_Joint_Runs.lua`. Then copy each function below from `BlumDrawerMaker/BlumDrawerTools.xlua`
verbatim at the given lines, with only this renaming throughout: `Drawer.Cal` → `Run.Cal`,
`Drawer.Unit` → `Run.InMM`, `Milling.job` stays `Milling.job` (already correct).

- `IdKey` (`BlumDrawerTools.xlua:104-107`) — no changes beyond the rename (none needed; it has no `Drawer`/`Milling` field reference).
- `GetDistance` (`:135-140`) — no changes.
- `FormatThickness` (`:74-78`) — no changes.
- `ThicknessTag` (`:79-82`) — no changes.
- `PointAlong` (`:1674-1678`) — no changes.
- `TabCountForEdge` (`:1679-1690`) — rename `Drawer.Unit` → `Run.InMM`.
- `AddProfileTabs` (`:1691-1706`) — rename `Milling.ProfileTabs` stays (already on `Milling`); no other changes.
- `DrawBox` (`:1418-1445`) — no changes.
- `OccupiedMaxX` (`:83-93`) — rename `Milling.job` stays; no other changes.
- `OpenSpaceStart` (`:95-103`) — rename `Drawer.Cal` → `Run.Cal`; drop the `Milling.PartGap` reference change (it already reads `Milling.PartGap`, unchanged).
- `ActivateThicknessSheet` (`:108-130`) — rename `Milling.MaterialBlockWidth`/`Milling.MaterialBlockHeight` to direct calls: replace the body's `Milling.MaterialBlockWidth, Milling.MaterialBlockHeight` argument to `sheet_manager:ResizeSheet` with `MaterialBlock().Width, MaterialBlock().Height` (Task 1 never stored those on `Milling`, so read them fresh here).
- `DrawWriter` (`BlumDrawerTools.xlua:141` through its matching `-- =====================================================]]` before line 1334) — copy verbatim; it only takes its five parameters and a layer name, with no `Drawer`/`Milling` field reads beyond what is passed in.
- `PresentMessage` (`:1865` to end of file) — only if not already copied into `Box_Joint_Runs.lua` in Task 1 Step 5; do not duplicate it in both files.

- [ ] **Step 2: Add the layer-naming pass**

```lua
function ApplyThicknessLayerNames()
    -- Must run after the dialog, exactly as Blum Drawer Maker's own ApplyThicknessLayerNames does
    -- (BlumDrawerJoinery.xlua:134), so the tagged names are never written to the registry.
    local tag = ThicknessTag(Run.StockT)
    Milling.LNProfile = "BJR Profile" .. tag
    Milling.LNFingers = "BJR Fingers" .. tag
    Milling.LNGroove = "BJR Groove" .. tag
    Milling.LNLabels = "BJR Labels" .. tag
end
```

- [ ] **Step 3: `DrawFingerEnd` — the one routine every mode calls**

```lua
function DrawFingerEnd(corner, dir_into, dir_across, phase, layer_name)
    -- Pockets every gap band at one finger end. corner is the point where this end's edge meets the piece's
    -- bottom (groove) edge. dir_into (degrees) points along the piece's length, into the piece body -- pockets
    -- recess this way by the finger depth, Run.StockT. dir_across (degrees) points from the bottom edge toward
    -- the top edge, along the piece's width -- band k runs from k * Run.FingerWidth to (k+1) * Run.FingerWidth
    -- along this direction, counted from the bottom edge (the spec's phase rule). phase is "Finger" when band 0
    -- is a finger, or "Gap" when band 0 is a gap; only gap bands are pocketed, since a finger band is the
    -- material a mating piece's gap will receive.
    --
    -- Generalizes Blum Drawer Maker's MySideFingers (BlumDrawerJoinery.xlua:769-941): where Blum hardcodes the
    -- panel axes as 0/180 (across) and 90/270 (into), this takes both directions as parameters so one routine
    -- serves every end of every mode. Only the Dog Bone and T-Bone branches carry over; Blum's Sniglet style has
    -- no equivalent here (the spec's three styles are Through, Dog Bone, T-Bone), and Through is new: a plain
    -- rectangular pocket with no corner relief, since this joint is hand-fitted, not flush-cornered.
    local layer = Milling.job.LayerManager:GetLayerWithName(layer_name)
    -- Clearance widens every gap outward, never narrows it. Blum Drawer Maker widens only the side's notches, by
    -- C/2 per edge, so its joint fits at C total (docs/clearance-reference.md, "Finger joints"). Here both mating
    -- ends are drawn by this one routine, so each edge moves C/4 to keep the same meaning: a finger clearance of
    -- C gives a total fit of C, the same number the user tuned in Blum Drawer Maker.
    local edge_clear = Run.FingerClearance * 0.25
    local overshoot = Milling.FingerTool.ToolDia * 1.5 -- past the end line, and past a long edge on band 0/n-1
    -- Arc winding for the Dog Bone and T-Bone reliefs depends on the handedness of the (dir_into, dir_across)
    -- pair. Blum Drawer Maker's two fixed cases fix the convention: into 90/across 0 uses -1.0, into 270/across 0
    -- uses +1.0 (BlumDrawerJoinery.xlua:629-639 and 668-681), which is sin(across - into) in both.
    local bulge = (math.sin(math.rad(dir_across - dir_into)) < 0.0) and -1.0 or 1.0
    local n = Run.FingerCount
    local gap_is_even = (phase == "Gap")
    for k = 0, n - 1 do
        local is_gap = ((k % 2 == 0) == gap_is_even)
        if is_gap then
            local band_start = Polar2D(corner, dir_across, k * Run.FingerWidth)
            local band_end = Polar2D(corner, dir_across, (k + 1) * Run.FingerWidth)
            local near = Polar2D(band_start, dir_across, -edge_clear)
            local far = Polar2D(band_end, dir_across, edge_clear)
            -- A gap on the bottom edge (k == 0) or the top edge (k == n - 1) overshoots past that long edge
            -- too, exactly as Blum Drawer Maker's pockets do, so no sliver of material is left along it.
            if k == 0 then
                near = Polar2D(band_start, dir_across, -overshoot)
            end
            if k == n - 1 then
                far = Polar2D(band_end, dir_across, overshoot)
            end
            local near_deep = Polar2D(near, dir_into, Run.StockT)
            local far_deep = Polar2D(far, dir_into, Run.StockT)
            local near_out = Polar2D(near, dir_into, -overshoot)
            local far_out = Polar2D(far, dir_into, -overshoot)
            local line = Contour(0.0)
            if Run.JointStyle == "Through" then
                line:AppendPoint(near_out)
                line:LineTo(near_deep)
                line:LineTo(far_deep)
                line:LineTo(far_out)
                line:LineTo(near_out)
            elseif Run.JointStyle == "Dog Bone" then
                -- A round relief bulging into each inside corner so a mating finger's square corner seats fully.
                -- Blum Drawer Maker's Dog Bone branch (BlumDrawerJoinery.xlua:598-639), generalized to dir_into/
                -- dir_across. Arc winding comes from bulge, above.
                local bit = math.sin(math.rad(45.0)) * Milling.FingerTool.ToolDia
                local near_relief_a = Polar2D(near_deep, dir_into, -bit)
                local near_relief_b = Polar2D(near_deep, dir_across, bit)
                local far_relief_a = Polar2D(far_deep, dir_across, -bit)
                local far_relief_b = Polar2D(far_deep, dir_into, -bit)
                line:AppendPoint(near_out)
                line:LineTo(near_relief_a)
                line:ArcTo(near_relief_b, bulge)
                line:LineTo(far_relief_a)
                line:ArcTo(far_relief_b, bulge)
                line:LineTo(far_out)
                line:LineTo(near_out)
            else -- "T-Bone"
                -- Blum Drawer Maker's T-Bone branch (BlumDrawerJoinery.xlua:640-664), generalized the same way.
                local relief = Milling.FingerTool.ToolDia
                local near_relief = Polar2D(near_deep, dir_into, -relief)
                local far_relief = Polar2D(far_deep, dir_into, -relief)
                line:AppendPoint(near_out)
                line:LineTo(near_relief)
                line:ArcTo(near_deep, bulge)
                line:LineTo(far_deep)
                line:ArcTo(far_relief, bulge)
                line:LineTo(far_out)
                line:LineTo(near_out)
            end
            layer:AddObject(CreateCadContour(line), true)
        end
    end
    return true
end
```

- [ ] **Step 4: The piece outline, groove, and label**

```lua
function DrawPieceOutline(origin, length, up_angle, layer_name)
    -- origin is the bottom-left corner (on the piece's bottom/groove edge, at its left end). up_angle is 90.0
    -- if the top edge is in the +Y direction from origin, or 270.0 if it is in -Y (Existing back's rotated
    -- frame). Ordering mirrors Blum Drawer Maker's Drawer_Side (BlumDrawerJoinery.xlua:267-273): pt1 origin,
    -- pt2 up, pt3 across, pt4 down -- so AddProfileTabs's (pt1,pt2)/(pt3,pt4) edge pairing still means "the two
    -- long edges" once passed in the piece's own order below.
    local pt_bl = origin
    local pt_tl = Polar2D(pt_bl, up_angle, Run.StockW)
    local pt_tr = Polar2D(pt_tl, 0.0, length)
    local pt_br = Polar2D(pt_tr, up_angle + 180.0, Run.StockW)
    local cad_contour = DrawBox(pt_bl, pt_tl, pt_tr, pt_br, layer_name)
    -- Tabs go on the two long edges (bottom and top), never the two ends, since the ends carry fingers.
    AddProfileTabs(cad_contour, pt_bl, pt_br, pt_tr, pt_tl)
    return pt_bl, pt_tl, pt_tr, pt_br, cad_contour
end
-- =====================================================]]
function DrawGroove(origin, length, up_angle, layer_name)
    -- A through dado on the top face, Run.GrooveInset from the bottom edge, running the full length plus the
    -- dado bit radius at each end, as on a Blum back (BlumDrawerTools.xlua:1643-1673, simplified: Box Joint Runs
    -- has no back rabbet to combine it with, so this is a plain rectangle, not Blum's T-shaped vector).
    if not Run.GrooveOn then
        return true
    end
    local radius = Milling.DadoTool.ToolDia * 0.5
    local near = Polar2D(origin, up_angle, Run.GrooveInset)
    local far = Polar2D(origin, up_angle, Run.GrooveInset + Run.GrooveWidth)
    local p1 = Polar2D(near, 180.0, radius)
    local p2 = Polar2D(far, 180.0, radius)
    local p3 = Polar2D(p2, 0.0, length + (radius * 2.0))
    local p4 = Polar2D(p1, 0.0, length + (radius * 2.0))
    DrawBox(p1, p2, p3, p4, layer_name)
    return true
end
-- =====================================================]]
function LabelPiece(origin, index, length, width, thickness, layer_name)
    -- "Run - Piece 2 (L x W x T)", positioned like Blum Drawer Maker's part notes (BlumDrawerJoinery.xlua:132-134).
    local pt = Polar2D(Polar2D(origin, 45.0, 1.5 * Run.Cal), 0.0, 0.75 * Run.Cal)
    local text = "Run - Piece " .. tostring(index) .. " (" .. string.format("%.4f", length) .. " x " ..
        string.format("%.4f", width) .. " x " .. string.format("%.4f", thickness) .. ")"
    DrawWriter(text, pt, 0.25 * Run.Cal, layer_name, 0.0)
    return true
end
```

- [ ] **Step 5: `RunTestCut`, the first mode driver**

```lua
function RunTestCut()
    -- Two short stubs at the real W, so the finger count and finger width match production: one Finger-at-
    -- bottom, one Gap-at-bottom, each about 3 units long, with the groove when it is on. Mirrors Blum Drawer
    -- Maker's Drawer.TestCut stub sizing (BlumDrawerTools.xlua:1745-1754) and ProcessTest (BlumDrawerJoinery.xlua:58-73).
    ApplyThicknessLayerNames()
    ActivateThicknessSheet(Run.StockT)
    local origin = OpenSpaceStart()
    local stub_length = 3.0 * Run.Cal
    -- Piece 1: Finger at bottom on its right end (the end under test); its left end is plain (no fingers).
    local pt_bl, pt_tl, pt_tr, pt_br = DrawPieceOutline(origin, stub_length, 90.0, Milling.LNProfile)
    DrawFingerEnd(pt_br, 180.0, 90.0, "Finger", Milling.LNFingers)
    DrawGroove(origin, stub_length, 90.0, Milling.LNGroove)
    LabelPiece(origin, 1, stub_length, Run.StockW, Run.StockT, Milling.LNLabels)
    -- Piece 2: Gap at bottom on its left end, placed to the right with the part gap plus room for the finger
    -- overshoot past the end line, so neither stub's pockets reach into the other's footprint.
    local gap2 = Milling.PartGap + (Milling.FingerTool.ToolDia * 1.5)
    local origin2 = Polar2D(origin, 0.0, stub_length + gap2)
    DrawPieceOutline(origin2, stub_length, 90.0, Milling.LNProfile)
    DrawFingerEnd(origin2, 0.0, 90.0, "Gap", Milling.LNFingers)
    DrawGroove(origin2, stub_length, 90.0, Milling.LNGroove)
    LabelPiece(origin2, 2, stub_length, Run.StockW, Run.StockT, Milling.LNLabels)
    Milling.job:Refresh2DView()
    return true
end
```

- [ ] **Step 6: Wire it into `main`**

In `Box_Joint_Runs.lua`, add the load line after the registry/dialog loads:

```lua
    Tools = assert(loadfile(script_path .. "\\BoxJointGeometry.xlua"))(Tools)
```

Replace the final `DisplayMessageBox` success line in `main` with:

```lua
    RecomputeDerived()
    if Run.Mode == "Test Cut" then
        RunTestCut()
    end
    DisplayMessageBox("Box Joint Runs complete. Mode: " .. Run.Mode .. ". Review the drawing before milling.")
```

- [ ] **Step 7: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| First run | Set stock T = 0.75", W = 6", groove on, Through style, run | A sheet named "0.75 Material" is created (or the default sheet renamed); two 3" x 6" rectangles appear side by side on layer "BJR Profile (0.75)", with pocket vectors on "BJR Fingers (0.75)" at one end of each piece, a groove rectangle on "BJR Groove (0.75)" on each, and two labels on "BJR Labels (0.75)" |
| Zoom the joint ends | Zoom into the facing ends of the two stubs | Piece 1's right end shows gap-band pockets at odd band positions (bands 1, 3, ...); Piece 2's left end shows pockets at even band positions (0, 2, ...) — the two patterns interlock when mentally overlaid |
| Dog Bone style | Switch Joint style to Dog Bone, re-run | Each gap pocket now shows a small round bulge into its two inside corners instead of a square corner |
| Second run | Run again without changing settings | A second pair of stubs is drawn to the right of the first (Chain/Test cut geometry is never replaced in place — only toolpaths recalculate, in Task 3) |

A Dog Bone relief must reach past each inside corner of the pocket, and a T-Bone relief must cut sideways
into the finger wall beside the pocket bottom, on **both** stubs. The two stubs have opposite handedness, so
this checks both signs of `bulge`. If both stubs are wrong, the convention is inverted: change `< 0.0` to
`> 0.0` in the `bulge` line of Step 3. If only one is wrong, stop and report it; the handedness rule is wrong,
not just its sign.

- [ ] **Step 8: Commit**

```bash
git add BoxJointRuns/BoxJointGeometry.xlua BoxJointRuns/Box_Joint_Runs.lua
git commit -m "Add the finger-end routine and Test cut geometry."
```

---

### Task 3: Toolpaths for the Test cut

Machines the Test cut stubs: finger clear, fingers, groove, profile with tabs, optional
finish. A second run recalculates instead of duplicating.

**Files:**
- Create: `BoxJointRuns/BoxJointToolpaths.xlua`
- Modify: `BoxJointRuns/Box_Joint_Runs.lua` (load the new module; call the toolpath functions after `RunTestCut()`)
- Test: none — verified by the user in VCarve, including a cut on scrap

**Interfaces:**
- Consumes: `Run`, `Milling` (including `Milling.LNProfile/LNFingers/LNGroove` from Task 2), the layers `RunTestCut()` populates.
- Produces: `SelectLayerVectors(layer_name, select_closed, select_open) -> boolean`; `AssociateToolpathWithLayer(toolpath_manager, toolpath_name, layer_name, select_closed, select_open) -> nil`; `SelectVectorsOnLayer(layer, selection, select_closed, select_open, select_groups) -> boolean`; `FindLatestToolpaths(toolpath_manager, toolpath_name) -> array`; `ReorderByTool(toolpath_manager, entries) -> boolean`; `SequenceToolpathsByTool() -> boolean`; `RecalculateExistingToolpath(name) -> boolean`; `CreateFingerClearToolpath() -> boolean`; `CreateFingerToolpath() -> boolean`; `CreateGrooveToolpath() -> boolean`; `CreateProfileToolpath(layer_name, InOrOut, use_tabs) -> boolean`. Toolpath name constants on `Milling`: `TPFingerClear = "BJR Finger Clear"`, `TPFingers = "BJR Fingers"`, `TPGroove = "BJR Groove"`, `TPProfile = "BJR Profile"`.

- [ ] **Step 1: Copy the selection and sequencing plumbing verbatim**

Create `BoxJointRuns/BoxJointToolpaths.xlua` with the same license header. Copy these functions
from `BlumDrawerMaker/BlumDrawerJoinery.xlua` verbatim — none of them reference `Drawer` or
`MillTool*`, so no renaming is needed:

- `SelectVectorsOnLayer` (`:1383-1432`)
- `SelectLayerVectors` (`:1339-1354`)
- `AssociateToolpathWithLayer` (`:1356-1381`)
- `FindLatestToolpaths` (`:150-165`)
- `ReorderByTool` (`:166-197`)
- `RecalculateExistingToolpath` (`:245-266`)

Copy `SequenceToolpathsByTool` (`:198-244`) verbatim except one rename: `Milling.job.SheetManager`
stays as written (it already reads `Milling.job`, which this gadget also uses).

- [ ] **Step 2: The finger clear toolpath (its own pass, not a two-tool pocket)**

```lua
function CreateFingerClearToolpath()
    -- The spec's toolpath table gives the finger clear bit its own full-depth pocket pass over the Fingers
    -- layer, ahead of the finger bit -- unlike Blum Drawer Maker, where the equivalent tool only ever runs
    -- paired with the finger bit inside one two-tool pocketing call (BlumDrawerJoinery.xlua:1138-1220). This is
    -- CreateLayerFingerToolpath's frame (BlumDrawerJoinery.xlua:1138-1220) with MillTool4 renamed to
    -- Milling.FingerClearTool, area_clear_tool always nil, and Allowance from Milling.FingerClearAllowance.
    if not SelectLayerVectors(Milling.LNFingers, true, false) then
        return false
    end
    if RecalculateExistingToolpath(Milling.TPFingerClear) then
        return true
    end
    local tool = Tool(Milling.FingerClearTool.Name, Tool.END_MILL)
    tool.InMM = Milling.FingerClearTool.InMM
    tool.ToolDia = Milling.FingerClearTool.ToolDia
    tool.Stepdown = Milling.FingerClearTool.Stepdown
    tool.Stepover = Milling.FingerClearTool.Stepover
    tool.RateUnits = Milling.FingerClearTool.RateUnits
    tool.FeedRate = Milling.FingerClearTool.FeedRate
    tool.PlungeRate = Milling.FingerClearTool.PlungeRate
    tool.SpindleSpeed = Milling.FingerClearTool.SpindleSpeed
    tool.ToolNumber = Milling.FingerClearTool.ToolNumber
    local mtl_block = MaterialBlock()
    local mtl_box_blc = mtl_block.MaterialBox.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_block.MaterialBox.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1
    local pocket_data = PocketParameterData()
    pocket_data.StartDepth = 0.0
    pocket_data.CutDepth = Run.StockT
    pocket_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
    pocket_data.Allowance = Milling.FingerClearAllowance
    pocket_data.DoRasterClearance = false
    pocket_data.RasterAngle = 0
    pocket_data.ProfilePassType = PocketParameterData.PROFILE_LAST
    pocket_data.DoRamping = false
    pocket_data.RampDistance = 1.0
    pocket_data.ProjectToolpath = false
    local geometry_selector = GeometrySelector()
    local toolpath_manager = ToolpathManager()
    local toolpath_id = toolpath_manager:CreatePocketingToolpath(Milling.TPFingerClear, tool, nil, pocket_data,
        pos_data, geometry_selector, true, false)
    if toolpath_id == nil then
        PresentMessage("Error", "Toolpath Processing", "Error creating Finger Clear toolpath")
        return false
    end
    AssociateToolpathWithLayer(toolpath_manager, Milling.TPFingerClear, Milling.LNFingers, true, false)
    return true
end
```

- [ ] **Step 3: The finger, groove, and profile toolpaths**

```lua
function CreateFingerToolpath()
    -- CreateLayerFingerToolpath's frame (BlumDrawerJoinery.xlua:1138-1220), renamed: MillTool4 ->
    -- Milling.FingerTool, Milling.FingerAllowance already correctly named, area_clear_tool always nil (finger
    -- clear now runs as its own toolpath, Step 2 above, not paired here).
    if not SelectLayerVectors(Milling.LNFingers, true, false) then
        return false
    end
    if RecalculateExistingToolpath(Milling.TPFingers) then
        return true
    end
    local tool = Tool(Milling.FingerTool.Name, Tool.END_MILL)
    tool.InMM = Milling.FingerTool.InMM
    tool.ToolDia = Milling.FingerTool.ToolDia
    tool.Stepdown = Milling.FingerTool.Stepdown
    tool.Stepover = Milling.FingerTool.Stepover
    tool.RateUnits = Milling.FingerTool.RateUnits
    tool.FeedRate = Milling.FingerTool.FeedRate
    tool.PlungeRate = Milling.FingerTool.PlungeRate
    tool.SpindleSpeed = Milling.FingerTool.SpindleSpeed
    tool.ToolNumber = Milling.FingerTool.ToolNumber
    local mtl_block = MaterialBlock()
    local mtl_box_blc = mtl_block.MaterialBox.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_block.MaterialBox.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1
    local pocket_data = PocketParameterData()
    pocket_data.StartDepth = 0.0
    pocket_data.CutDepth = Run.StockT
    pocket_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
    pocket_data.Allowance = Milling.FingerAllowance
    pocket_data.DoRasterClearance = false
    pocket_data.RasterAngle = 0
    pocket_data.ProfilePassType = PocketParameterData.PROFILE_LAST
    pocket_data.DoRamping = false
    pocket_data.RampDistance = 1.0
    pocket_data.ProjectToolpath = false
    local geometry_selector = GeometrySelector()
    local toolpath_manager = ToolpathManager()
    local toolpath_id = toolpath_manager:CreatePocketingToolpath(Milling.TPFingers, tool, nil, pocket_data,
        pos_data, geometry_selector, true, false)
    if toolpath_id == nil then
        PresentMessage("Error", "Toolpath Processing", "Error creating Fingers toolpath")
        return false
    end
    AssociateToolpathWithLayer(toolpath_manager, Milling.TPFingers, Milling.LNFingers, true, false)
    return true
end
-- =====================================================]]
function CreateGrooveToolpath()
    -- Same frame again, over the Groove layer with the dado bit. Chain and Test cut only -- Existing back and
    -- Existing end never populate Milling.LNGroove, so SelectLayerVectors finds no layer and this returns
    -- false harmlessly when called for those modes (it is not called for them; see Tasks 5-6).
    if not Run.GrooveOn then
        return true
    end
    if not SelectLayerVectors(Milling.LNGroove, true, false) then
        return false
    end
    if RecalculateExistingToolpath(Milling.TPGroove) then
        return true
    end
    local tool = Tool(Milling.DadoTool.Name, Tool.END_MILL)
    tool.InMM = Milling.DadoTool.InMM
    tool.ToolDia = Milling.DadoTool.ToolDia
    tool.Stepdown = Milling.DadoTool.Stepdown
    tool.Stepover = Milling.DadoTool.Stepover
    tool.RateUnits = Milling.DadoTool.RateUnits
    tool.FeedRate = Milling.DadoTool.FeedRate
    tool.PlungeRate = Milling.DadoTool.PlungeRate
    tool.SpindleSpeed = Milling.DadoTool.SpindleSpeed
    tool.ToolNumber = Milling.DadoTool.ToolNumber
    local mtl_block = MaterialBlock()
    local mtl_box_blc = mtl_block.MaterialBox.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_block.MaterialBox.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1
    local pocket_data = PocketParameterData()
    pocket_data.StartDepth = 0.0
    pocket_data.CutDepth = Run.GrooveDepth
    pocket_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
    pocket_data.Allowance = Milling.GrooveAllowance
    pocket_data.DoRasterClearance = false
    pocket_data.RasterAngle = 0
    pocket_data.ProfilePassType = PocketParameterData.PROFILE_LAST
    pocket_data.DoRamping = false
    pocket_data.RampDistance = 1.0
    pocket_data.ProjectToolpath = false
    local geometry_selector = GeometrySelector()
    local toolpath_manager = ToolpathManager()
    local toolpath_id = toolpath_manager:CreatePocketingToolpath(Milling.TPGroove, tool, nil, pocket_data,
        pos_data, geometry_selector, true, false)
    if toolpath_id == nil then
        PresentMessage("Error", "Toolpath Processing", "Error creating Groove toolpath")
        return false
    end
    AssociateToolpathWithLayer(toolpath_manager, Milling.TPGroove, Milling.LNGroove, true, false)
    return true
end
-- =====================================================]]
function CreateProfileToolpath(layer_name, InOrOut, use_tabs)
    -- CreateLayerProfileToolpath + CreateProfilePass, combined (BlumDrawerJoinery.xlua:1222-1338), renamed:
    -- MillTool1 -> Milling.ProfileTool, Milling.ProfileFinishAllowance already correctly named. name and
    -- toolpath_name are always Milling.TPProfile -- the caller picks layer_name, InOrOut ("OUT" for pieces,
    -- "IN" for Existing back's waste rectangle), and use_tabs (false for Existing back's waste, which the spec
    -- says gets no tabs).
    local allowance = 0.0
    if Milling.ProfileFinish and Milling.ProfileFinishAllowance > 0.0 then
        allowance = Milling.ProfileFinishAllowance
    end
    if not CreateProfilePass(Milling.TPProfile, layer_name, InOrOut, use_tabs, allowance, false) then
        return false
    end
    if allowance > 0.0 then
        return CreateProfilePass(Milling.TPProfile .. " Finish", layer_name, InOrOut, use_tabs, 0.0, true)
    end
    return true
end
-- =====================================================]]
function CreateProfilePass(name, layer_name, InOrOut, use_tabs, allowance, single_pass)
    if not SelectLayerVectors(layer_name, true, false) then
        return false
    end
    if RecalculateExistingToolpath(name) then
        return true
    end
    local tool = Tool(Milling.ProfileTool.Name, Tool.END_MILL)
    tool.InMM = Milling.ProfileTool.InMM
    tool.ToolDia = Milling.ProfileTool.ToolDia
    tool.Stepdown = Milling.ProfileTool.Stepdown
    if single_pass then
        tool.Stepdown = Run.StockT
    end
    tool.Stepover = Milling.ProfileTool.Stepover
    tool.RateUnits = Milling.ProfileTool.RateUnits
    tool.FeedRate = Milling.ProfileTool.FeedRate
    tool.PlungeRate = Milling.ProfileTool.PlungeRate
    tool.SpindleSpeed = Milling.ProfileTool.SpindleSpeed
    tool.ToolNumber = Milling.ProfileTool.ToolNumber
    local mtl_block = MaterialBlock()
    local mtl_box_blc = mtl_block.MaterialBox.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_block.MaterialBox.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1
    local profile_data = ProfileParameterData()
    profile_data.StartDepth = 0.0
    profile_data.CutDepth = Run.StockT
    profile_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
    if InOrOut == "IN" then
        profile_data.ProfileSide = ProfileParameterData.PROFILE_INSIDE
    else
        profile_data.ProfileSide = ProfileParameterData.PROFILE_OUTSIDE
    end
    profile_data.Allowance = allowance
    profile_data.KeepStartPoints = false
    profile_data.CreateSquareCorners = false
    profile_data.CornerSharpen = false
    profile_data.UseTabs = use_tabs and Milling.ProfileTabs
    profile_data.TabLength = 0.5 * Run.Cal
    profile_data.TabThickness = Run.StockT * 0.5
    profile_data.Use3dTabs = true
    profile_data.ProjectToolpath = false
    local ramping_data = RampingData()
    ramping_data.DoRamping = false
    ramping_data.RampType = RampingData.RAMP_ZIG_ZAG
    ramping_data.RampConstraint = RampingData.CONSTRAIN_ANGLE
    ramping_data.RampDistance = 100.0
    ramping_data.RampAngle = 25.0
    ramping_data.RampMaxAngleDist = 15
    ramping_data.RampOnLeadIn = false
    lead_in_out_data.DoLeadIn = false
    lead_in_out_data.DoLeadOut = false
    lead_in_out_data.LeadType = LeadInOutData.CIRCULAR_LEAD
    lead_in_out_data.LeadLength = 5.0
    lead_in_out_data.LinearLeadAngle = 45
    lead_in_out_data.CirularLeadRadius = 5.0
    lead_in_out_data.OvercutDistance = 0.0
    local geometry_selector = GeometrySelector()
    local toolpath_manager = ToolpathManager()
    local toolpath_id = toolpath_manager:CreateProfilingToolpath(name, tool, profile_data, ramping_data,
        lead_in_out_data, pos_data, geometry_selector, true, false)
    if toolpath_id == nil then
        PresentMessage("Error", "Toolpath Processing", "Error creating Profile toolpath '" .. name .. "'")
        return false
    end
    AssociateToolpathWithLayer(toolpath_manager, name, layer_name, true, false)
    return true
end
```

`lead_in_out_data` must exist as a global before this file loads; add `lead_in_out_data = LeadInOutData()`
next to `Run = {}` / `Milling = {}` at the top of `Box_Joint_Runs.lua` (Task 1's globals block), matching
`Blum_Drawer_Maker.lua:36`.

- [ ] **Step 4: Wire toolpath creation and sequencing into `main`**

In `Box_Joint_Runs.lua`, add the load line after `BoxJointGeometry.xlua`:

```lua
    Tools = assert(loadfile(script_path .. "\\BoxJointToolpaths.xlua"))(Tools)
```

Set the toolpath name constants next to `ApplyThicknessLayerNames`'s call site (in `RunTestCut`,
before it runs — or simplest, at the end of `ApplyThicknessLayerNames` itself in `BoxJointGeometry.xlua`):

```lua
    Milling.TPFingerClear = "BJR Finger Clear"
    Milling.TPFingers = "BJR Fingers"
    Milling.TPGroove = "BJR Groove"
    Milling.TPProfile = "BJR Profile"
```

Replace the `if Run.Mode == "Test Cut" then RunTestCut() end` block in `main` with:

```lua
    if Run.Mode == "Test Cut" then
        RunTestCut()
        CreateFingerClearToolpath()
        CreateFingerToolpath()
        CreateGrooveToolpath()
        CreateProfileToolpath(Milling.LNProfile, "OUT", true)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
    end
```

- [ ] **Step 5: Package and have the user verify the toolpaths**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| First run | Run with the Task 2 settings | Toolpath list shows "BJR Finger Clear", "BJR Fingers", "BJR Groove", "BJR Profile", in that order after Sequence; each previews without error |
| Re-run, no geometry change | Run again with identical settings | No new toolpaths are added to the list; the existing four recalculate (watch the status bar or toolpath count before/after) |
| Change a setting, re-run | Change Finger clearance, run again | The four toolpaths update in place (same names, same count), reflecting the new clearance |
| Simulate | Use VCarve's toolpath preview/simulate on all four | Finger clear and Fingers remove material at the gap bands to depth T; Groove cuts the dado to its depth; Profile cuts the two stub outlines free, leaving tabs |

- [ ] **Step 6: Cut the test pair on scrap and check the fit**

Mill both stubs from scrap at the actual stock thickness and width. Break the tabs, slide the two
stubs together by hand.

| Check | Expected |
| --- | --- |
| Fit | Fingers seat fully with hand pressure, no gaps at the shoulders, no need to force it |
| Squareness | The two stubs meet at a clean 90° corner with the bottom (groove) edges flush |
| Groove | If groove was on, both grooves align across the joint |

If the fit is too tight or too loose, adjust `Run.FingerClearance` and re-run from Step 4's dialog —
do not change the geometry code to compensate for a clearance problem.

- [ ] **Step 7: Commit**

```bash
git add BoxJointRuns/BoxJointToolpaths.xlua BoxJointRuns/Box_Joint_Runs.lua BoxJointRuns/BoxJointGeometry.xlua
git commit -m "Add Test cut toolpaths: finger clear, fingers, groove, profile."
```

---

### Task 4: Chain mode

Adds the 4-piece chain: enable checkboxes, lengths, start/end dropdowns, close loop, and layout.

**Files:**
- Modify: `BoxJointRuns/BoxJointRegistry.xlua` (chain-row defaults, read, write)
- Modify: `BoxJointRuns/BoxJointDialog.xlua` (chain rows UI, "Chain" mode option)
- Modify: `BoxJointRuns/BoxJointGeometry.xlua` (`RunChain`)
- Modify: `BoxJointRuns/Box_Joint_Runs.lua` (dispatch to `RunChain`, extend `ValidateSettings`)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `DrawFingerEnd`, `DrawPieceOutline`, `DrawGroove`, `LabelPiece`, `ApplyThicknessLayerNames`, `ActivateThicknessSheet`, `OpenSpaceStart`, `Polar2D` from Tasks 1-3.
- Produces: `Run.Piece[1..4]` = `{Enabled = boolean, Length = number}`; `Run.StartEnd`, `Run.EndEnd` ∈ `{"None", "Finger", "Gap"}`; `Run.CloseLoop = boolean`; `RunChain() -> boolean`; extends `ValidateSettings()` with the chain length rule.

- [ ] **Step 1: Registry — chain-row defaults, read, write**

In `BoxJointRuns/BoxJointRegistry.xlua`, add to both `IMPERIAL_DEFAULTS` and `METRIC_DEFAULTS`:

```lua
    Piece1Length = 12.0000, -- imperial; 300.0000 in the metric table
    Piece2Length = 12.0000, -- 300.0000 metric
    Piece3Length = 12.0000, -- 300.0000 metric
    Piece4Length = 12.0000, -- 300.0000 metric
    Piece2Enabled = false,
    Piece3Enabled = false,
    Piece4Enabled = false,
    StartEnd = "None",
    EndEnd = "None",
    CloseLoop = false,
```

Add to `SettingsRead()`:

```lua
    Run.Piece = Run.Piece or {}
    Run.Piece[1] = {Enabled = true, Length = registry:GetDouble(SettingsKey("Piece1Length"), defaults.Piece1Length)}
    Run.Piece[2] = {
        Enabled = registry:GetBool(SettingsKey("Piece2Enabled"), defaults.Piece2Enabled),
        Length = registry:GetDouble(SettingsKey("Piece2Length"), defaults.Piece2Length)
    }
    Run.Piece[3] = {
        Enabled = registry:GetBool(SettingsKey("Piece3Enabled"), defaults.Piece3Enabled),
        Length = registry:GetDouble(SettingsKey("Piece3Length"), defaults.Piece3Length)
    }
    Run.Piece[4] = {
        Enabled = registry:GetBool(SettingsKey("Piece4Enabled"), defaults.Piece4Enabled),
        Length = registry:GetDouble(SettingsKey("Piece4Length"), defaults.Piece4Length)
    }
    Run.StartEnd = registry:GetString(SettingsKey("StartEnd"), defaults.StartEnd)
    Run.EndEnd = registry:GetString(SettingsKey("EndEnd"), defaults.EndEnd)
    Run.CloseLoop = registry:GetBool(SettingsKey("CloseLoop"), defaults.CloseLoop)
```

Add to `SettingsWrite()`:

```lua
    registry:SetDouble(SettingsKey("Piece1Length"), Run.Piece[1].Length)
    registry:SetDouble(SettingsKey("Piece2Length"), Run.Piece[2].Length)
    registry:SetDouble(SettingsKey("Piece3Length"), Run.Piece[3].Length)
    registry:SetDouble(SettingsKey("Piece4Length"), Run.Piece[4].Length)
    registry:SetBool(SettingsKey("Piece2Enabled"), Run.Piece[2].Enabled)
    registry:SetBool(SettingsKey("Piece3Enabled"), Run.Piece[3].Enabled)
    registry:SetBool(SettingsKey("Piece4Enabled"), Run.Piece[4].Enabled)
    registry:SetString(SettingsKey("StartEnd"), Run.StartEnd)
    registry:SetString(SettingsKey("EndEnd"), Run.EndEnd)
    registry:SetBool(SettingsKey("CloseLoop"), Run.CloseLoop)
```

- [ ] **Step 2: Dialog — chain rows and the "Chain" mode option**

In `BoxJointRuns/BoxJointDialog.xlua`, add `<option value="Chain">Chain</option>` to the `Run.Mode`
`<select>`, and insert this block before the `<h2>Mode</h2>` row:

```html
<tr><td colspan="4"><h2>Chain</h2></td></tr>
<tr>
  <td><label>Piece 1</label></td>
  <td><input type="text" id="Run.Piece1Length" size="10"/></td>
  <td><label title="Piece 1 is always part of the chain.">Enabled</label></td>
  <td>(always)</td>
</tr>
<tr>
  <td><label>Piece 2</label></td>
  <td><input type="text" id="Run.Piece2Length" size="10"/></td>
  <td><label>Enabled</label></td>
  <td><input type="checkbox" id="Run.Piece2Enabled"/></td>
</tr>
<tr>
  <td><label>Piece 3</label></td>
  <td><input type="text" id="Run.Piece3Length" size="10"/></td>
  <td><label title="Can only be enabled while Piece 2 is.">Enabled</label></td>
  <td><input type="checkbox" id="Run.Piece3Enabled"/></td>
</tr>
<tr>
  <td><label>Piece 4</label></td>
  <td><input type="text" id="Run.Piece4Length" size="10"/></td>
  <td><label title="Can only be enabled while Piece 3 is.">Enabled</label></td>
  <td><input type="checkbox" id="Run.Piece4Enabled"/></td>
</tr>
<tr>
  <td><label title="The end at the start of Piece 1.">Start of Piece 1</label></td>
  <td>
    <select id="Run.StartEnd" size="1">
      <option value="None">None (plain square end)</option>
      <option value="Finger">Finger at bottom</option>
      <option value="Gap">Gap at bottom</option>
    </select>
  </td>
  <td><label title="The end at the end of the last enabled piece.">End of last piece</label></td>
  <td>
    <select id="Run.EndEnd" size="1">
      <option value="None">None (plain square end)</option>
      <option value="Finger">Finger at bottom</option>
      <option value="Gap">Gap at bottom</option>
    </select>
  </td>
</tr>
<tr>
  <td><label title="Offered only with 4 pieces enabled. Joins the end of Piece 4 to the start of Piece 1, and replaces both end dropdowns above.">Close loop</label></td>
  <td><input type="checkbox" id="Run.CloseLoop"/></td>
  <td colspan="2"></td>
</tr>
```

In `BuildDialog()`, add:

```lua
    Run.dialog:AddDoubleField("Run.Piece1Length", Run.Piece[1].Length)
    Run.dialog:AddDoubleField("Run.Piece2Length", Run.Piece[2].Length)
    Run.dialog:AddDoubleField("Run.Piece3Length", Run.Piece[3].Length)
    Run.dialog:AddDoubleField("Run.Piece4Length", Run.Piece[4].Length)
    Run.dialog:AddCheckBox("Run.Piece2Enabled", Run.Piece[2].Enabled)
    Run.dialog:AddCheckBox("Run.Piece3Enabled", Run.Piece[3].Enabled)
    Run.dialog:AddCheckBox("Run.Piece4Enabled", Run.Piece[4].Enabled)
    Run.dialog:AddDropDownList("Run.StartEnd", Run.StartEnd)
    Run.dialog:AddDropDownList("Run.EndEnd", Run.EndEnd)
    Run.dialog:AddCheckBox("Run.CloseLoop", Run.CloseLoop)
```

In `ShowSettingsDialog()`, add, before the `return true`:

```lua
    Run.Piece[1].Length = math.abs(Run.dialog:GetDoubleField("Run.Piece1Length"))
    Run.Piece[2].Length = math.abs(Run.dialog:GetDoubleField("Run.Piece2Length"))
    Run.Piece[3].Length = math.abs(Run.dialog:GetDoubleField("Run.Piece3Length"))
    Run.Piece[4].Length = math.abs(Run.dialog:GetDoubleField("Run.Piece4Length"))
    Run.Piece[2].Enabled = Run.dialog:GetCheckBox("Run.Piece2Enabled")
    Run.Piece[3].Enabled = Run.dialog:GetCheckBox("Run.Piece3Enabled") and Run.Piece[2].Enabled
    Run.Piece[4].Enabled = Run.dialog:GetCheckBox("Run.Piece4Enabled") and Run.Piece[3].Enabled
    Run.StartEnd = Run.dialog:GetDropDownListValue("Run.StartEnd")
    Run.EndEnd = Run.dialog:GetDropDownListValue("Run.EndEnd")
    Run.CloseLoop = Run.dialog:GetCheckBox("Run.CloseLoop") and Run.Piece[4].Enabled
```

The `and Run.Piece[2].Enabled` / `and Run.Piece[3].Enabled` chaining is the dialog-side enforcement
of "Piece N can be enabled only while Piece N−1 is"; a later piece silently drops back to disabled
rather than raising an error, since the spec calls this a structural constraint, not a validation.

- [ ] **Step 3: Validation — piece length and the close-loop warning**

In `Box_Joint_Runs.lua`, extend `ValidateSettings()` — add before its final `return true, nil`:

```lua
    if Run.Mode == "Chain" then
        for i = 1, 4 do
            if Run.Piece[i].Enabled and Run.Piece[i].Length <= (2.0 * Run.StockT) then
                return false, "Piece " .. tostring(i) .. " length must be greater than 2 x thickness."
            end
        end
        if Run.CloseLoop then
            if Run.Piece[1].Length ~= Run.Piece[3].Length or Run.Piece[2].Length ~= Run.Piece[4].Length then
                PresentMessage("Alert", "Box Joint Runs",
                    "Close loop: Piece 1/Piece 3 or Piece 2/Piece 4 lengths do not match. Continuing anyway.")
            end
        end
    end
```

This warns without blocking, exactly as the spec requires, by using `PresentMessage("Alert", ...)`
(an acknowledgment dialog) rather than returning `false` from `ValidateSettings`.

- [ ] **Step 4: `RunChain`, in `BoxJointGeometry.xlua`**

```lua
function RunChain()
    -- Lays out 1 to 4 pieces end to end along X, each a plain L x W rectangle with fingers cut per the phase
    -- rule. At every internal joint the earlier piece's end is Finger at bottom and the later piece's end is
    -- Gap at bottom (the spec's internal-joint rule) -- this is fixed, never a dialog choice. Close loop applies
    -- that same rule between Piece 4's end and Piece 1's start, replacing the two end dropdowns.
    ApplyThicknessLayerNames()
    ActivateThicknessSheet(Run.StockT)
    local origin = OpenSpaceStart()
    local gap = Milling.PartGap + (Milling.FingerTool.ToolDia * 1.5)
    local count = 1
    for i = 2, 4 do
        if Run.Piece[i].Enabled then
            count = i
        end
    end
    local x = origin
    for i = 1, count do
        local piece = Run.Piece[i]
        local _, _, _, pt_br = DrawPieceOutline(x, piece.Length, 90.0, Milling.LNProfile)
        DrawGroove(x, piece.Length, 90.0, Milling.LNGroove)
        LabelPiece(x, i, piece.Length, Run.StockW, Run.StockT, Milling.LNLabels)
        -- Start-of-piece end
        local start_phase = nil
        if i == 1 then
            if Run.CloseLoop then
                start_phase = "Gap" -- opposite the internal rule's "Finger" at the end of Piece 4
            elseif Run.StartEnd ~= "None" then
                start_phase = Run.StartEnd
            end
        else
            start_phase = "Gap" -- internal joint: always opposite the previous piece's Finger end
        end
        if start_phase ~= nil then
            DrawFingerEnd(x, 0.0, 90.0, start_phase, Milling.LNFingers)
        end
        -- End-of-piece end
        local end_phase = nil
        if i == count then
            if Run.CloseLoop and count == 4 then
                end_phase = "Finger" -- internal rule, joining to Piece 1's start
            elseif not Run.CloseLoop and Run.EndEnd ~= "None" then
                end_phase = Run.EndEnd
            end
        else
            end_phase = "Finger" -- internal joint: this piece's end is Finger at bottom
        end
        if end_phase ~= nil then
            DrawFingerEnd(pt_br, 180.0, 90.0, end_phase, Milling.LNFingers)
        end
        x = Polar2D(x, 0.0, piece.Length + gap)
    end
    Milling.job:Refresh2DView()
    return true
end
```

- [ ] **Step 5: Wire Chain mode into `main`**

In `Box_Joint_Runs.lua`, replace the `if Run.Mode == "Test Cut" then ... end` block with:

```lua
    if Run.Mode == "Test Cut" then
        RunTestCut()
    elseif Run.Mode == "Chain" then
        RunChain()
    end
    if Run.Mode == "Test Cut" or Run.Mode == "Chain" then
        CreateFingerClearToolpath()
        CreateFingerToolpath()
        CreateGrooveToolpath()
        CreateProfileToolpath(Milling.LNProfile, "OUT", true)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
    end
```

- [ ] **Step 6: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| Two-piece open chain | Mode = Chain, enable Piece 2 only, lengths 10" and 8", Start = None, End = None | Two pieces drawn in a row; only the internal joint (Piece 1 end / Piece 2 start) carries fingers; Piece 1's start and Piece 2's end are plain rectangles |
| Start/End dropdowns | Set Start of Piece 1 = Gap at bottom, End of last piece = Finger at bottom | Piece 1's left end and Piece 2's right end now show finger pockets matching the chosen phase |
| Three-piece chain (the U-notch case) | Enable Pieces 1-3, set lengths matching a real notch opening | Three pieces, two internal joints, each showing opposite phases at the mating ends |
| Close loop | Enable all 4 pieces, check Close loop | The Start/End dropdowns disappear behind the fixed rule; Piece 4's end and Piece 1's start both show fingers per the internal rule |
| Close loop mismatch warning | With Close loop checked, set Piece 1 and Piece 3 to different lengths | An alert names the mismatch but the run proceeds |
| Length validation | Set Piece 1 length to less than 2 x thickness | "Piece 1 length must be greater than 2 x thickness." — dialog reopens |
| Toolpaths | Run any chain above to completion | Finger clear, Fingers, Groove (if on), and Profile toolpaths cover every piece; re-running with a length change recalculates rather than duplicating |

- [ ] **Step 7: Commit**

```bash
git add BoxJointRuns/BoxJointRegistry.xlua BoxJointRuns/BoxJointDialog.xlua BoxJointRuns/BoxJointGeometry.xlua BoxJointRuns/Box_Joint_Runs.lua
git commit -m "Add Chain mode: 1-4 pieces, end dropdowns, close loop."
```

---

### Task 5: Existing end mode

Adds finger pockets to a single existing square end, mirrored for the right-hand stub.

**Files:**
- Modify: `BoxJointRuns/BoxJointRegistry.xlua` (Existing end defaults, read, write)
- Modify: `BoxJointRuns/BoxJointDialog.xlua` (Existing end inputs, "Existing end" mode option)
- Modify: `BoxJointRuns/BoxJointGeometry.xlua` (`RunExistingEnd`)
- Modify: `BoxJointRuns/Box_Joint_Runs.lua` (dispatch to `RunExistingEnd`)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `DrawFingerEnd` from Task 2; `Milling.job.LayerManager:FindLayerWithName` / `:RemoveLayer` for the "re-run replaces" rule.
- Produces: `Run.EEToward = boolean` (true = bottom edge toward the operator, on Y = 0); `Run.EEPhase ∈ {"Finger", "Gap"}`; `Milling.LNExistingFingers = "BJR Existing Fingers"`; `Milling.TPExistingFingers = "BJR Existing Fingers"`; `ClearModeLayer(layer_name) -> nil`; `RunExistingEnd() -> boolean`.

- [ ] **Step 1: Registry**

Add to both default tables in `BoxJointRuns/BoxJointRegistry.xlua`:

```lua
    EEToward = true,
    EEPhase = "Finger",
```

Add to `SettingsRead()`:

```lua
    Run.EEToward = registry:GetBool(SettingsKey("EEToward"), defaults.EEToward)
    Run.EEPhase = registry:GetString(SettingsKey("EEPhase"), defaults.EEPhase)
```

Add to `SettingsWrite()`:

```lua
    registry:SetBool(SettingsKey("EEToward"), Run.EEToward)
    registry:SetString(SettingsKey("EEPhase"), Run.EEPhase)
```

- [ ] **Step 2: Dialog**

Add `<option value="Existing End">Existing end</option>` to the `Run.Mode` `<select>`, and this
block before `<h2>Mode</h2>`:

```html
<tr><td colspan="4"><h2>Existing end</h2></td></tr>
<tr>
  <td><label title="The end being cut is always at X = 0. Turn a right-hand stub end for end so nothing is drawn at negative X.">Bottom edge</label></td>
  <td>
    <select id="Run.EEToward" size="1">
      <option value="true">Toward the operator (Y = 0)</option>
      <option value="false">Away from the operator (Y = W)</option>
    </select>
  </td>
  <td><label>Phase</label></td>
  <td>
    <select id="Run.EEPhase" size="1">
      <option value="Finger">Finger at bottom</option>
      <option value="Gap">Gap at bottom</option>
    </select>
  </td>
</tr>
```

`Run.EEToward` is a dropdown of the strings `"true"`/`"false"` rather than a checkbox, since it
needs a boolean-with-a-label; `ShowSettingsDialog()` converts it:

In `BuildDialog()`, add:

```lua
    Run.dialog:AddDropDownList("Run.EEToward", tostring(Run.EEToward))
    Run.dialog:AddDropDownList("Run.EEPhase", Run.EEPhase)
```

In `ShowSettingsDialog()`, add:

```lua
    Run.EEToward = (Run.dialog:GetDropDownListValue("Run.EEToward") == "true")
    Run.EEPhase = Run.dialog:GetDropDownListValue("Run.EEPhase")
```

- [ ] **Step 3: `RunExistingEnd`, in `BoxJointGeometry.xlua`**

```lua
function ClearModeLayer(layer_name)
    -- A re-run of Existing back or Existing end replaces that mode's geometry on the active sheet rather than
    -- stacking on top of it; Chain and Test cut geometry is never touched by this. Mirrors Blum Drawer Maker's
    -- MyLayerClear (BlumDrawerTools.xlua:1496-1502), but removes non-empty contents too, since here the layer
    -- is meant to hold exactly one mode's output at a time.
    local layer = Milling.job.LayerManager:FindLayerWithName(layer_name)
    if layer ~= nil then
        Milling.job.LayerManager:RemoveLayer(layer)
    end
end
-- =====================================================]]
function RunExistingEnd()
    -- Only the finger pockets are cut -- no profile, no groove. The end being cut is always at X = 0, zeroed
    -- at that end's corner; a right-hand stub is handled by turning it end for end, so nothing here is drawn
    -- at negative X. Bottom edge is at Y = 0 (Run.EEToward true) or Y = W (false).
    Milling.LNExistingFingers = "BJR Existing Fingers" .. ThicknessTag(Run.StockT)
    Milling.TPExistingFingers = "BJR Existing Fingers"
    ClearModeLayer(Milling.LNExistingFingers)
    local sheet_manager = Milling.job.SheetManager
    Milling.job:Refresh2DView()
    local corner = Point2D(0.0, 0.0)
    local up_angle = 90.0
    if not Run.EEToward then
        corner = Point2D(0.0, Run.StockW)
        up_angle = 270.0
    end
    DrawFingerEnd(corner, 0.0, up_angle, Run.EEPhase, Milling.LNExistingFingers)
    Milling.job:Refresh2DView()
    return true
end
```

- [ ] **Step 4: Toolpath and dispatch**

In `BoxJointRuns/BoxJointToolpaths.xlua`, add:

```lua
function CreateExistingFingerToolpath(layer_name, toolpath_name)
    -- Same frame as CreateFingerToolpath (Task 3 Step 3), parameterized on layer and toolpath name so Existing
    -- end and Existing back (Task 6) can each use their own names, as the spec requires.
    if not SelectLayerVectors(layer_name, true, false) then
        return false
    end
    if RecalculateExistingToolpath(toolpath_name) then
        return true
    end
    local tool = Tool(Milling.FingerTool.Name, Tool.END_MILL)
    tool.InMM = Milling.FingerTool.InMM
    tool.ToolDia = Milling.FingerTool.ToolDia
    tool.Stepdown = Milling.FingerTool.Stepdown
    tool.Stepover = Milling.FingerTool.Stepover
    tool.RateUnits = Milling.FingerTool.RateUnits
    tool.FeedRate = Milling.FingerTool.FeedRate
    tool.PlungeRate = Milling.FingerTool.PlungeRate
    tool.SpindleSpeed = Milling.FingerTool.SpindleSpeed
    tool.ToolNumber = Milling.FingerTool.ToolNumber
    local mtl_block = MaterialBlock()
    local mtl_box_blc = mtl_block.MaterialBox.BLC
    local pos_data = ToolpathPosData()
    pos_data:SetHomePosition(mtl_box_blc.x, mtl_box_blc.y, mtl_block.MaterialBox.TRC.z + (mtl_block.Thickness * 0.2))
    pos_data.SafeZGap = mtl_block.Thickness * 0.1
    local pocket_data = PocketParameterData()
    pocket_data.StartDepth = 0.0
    pocket_data.CutDepth = Run.StockT
    pocket_data.CutDirection = ProfileParameterData.CLIMB_DIRECTION
    pocket_data.Allowance = Milling.FingerAllowance
    pocket_data.DoRasterClearance = false
    pocket_data.RasterAngle = 0
    pocket_data.ProfilePassType = PocketParameterData.PROFILE_LAST
    pocket_data.DoRamping = false
    pocket_data.RampDistance = 1.0
    pocket_data.ProjectToolpath = false
    local geometry_selector = GeometrySelector()
    local toolpath_manager = ToolpathManager()
    local toolpath_id = toolpath_manager:CreatePocketingToolpath(toolpath_name, tool, nil, pocket_data,
        pos_data, geometry_selector, true, false)
    if toolpath_id == nil then
        PresentMessage("Error", "Toolpath Processing", "Error creating " .. toolpath_name .. " toolpath")
        return false
    end
    AssociateToolpathWithLayer(toolpath_manager, toolpath_name, layer_name, true, false)
    return true
end
```

In `Box_Joint_Runs.lua`, extend the mode dispatch:

```lua
    elseif Run.Mode == "Existing End" then
        RunExistingEnd()
        CreateExistingFingerToolpath(Milling.LNExistingFingers, Milling.TPExistingFingers)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
```

- [ ] **Step 5: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| Toward the operator | Mode = Existing end, Bottom edge = Toward, Phase = Finger at bottom | Finger pockets appear at X = 0, running from Y = 0 upward, matching a Finger-at-bottom pattern |
| Away from the operator | Bottom edge = Away | The same pattern, mirrored so band 0 sits at Y = W instead |
| No profile, no groove | Either case | No profile or groove vectors are drawn — only pockets on "BJR Existing Fingers (T)" |
| Re-run replaces | Change Phase to Gap at bottom, run again on the same sheet | The previous pockets are gone; only the new phase's pockets remain — no stacking |
| Toolpath name | Inspect the toolpath list | A toolpath named "BJR Existing Fingers" exists and recalculates rather than duplicating on a further re-run |

- [ ] **Step 6: Commit**

```bash
git add BoxJointRuns/BoxJointRegistry.xlua BoxJointRuns/BoxJointDialog.xlua BoxJointRuns/BoxJointGeometry.xlua BoxJointRuns/BoxJointToolpaths.xlua BoxJointRuns/Box_Joint_Runs.lua
git commit -m "Add Existing end mode."
```

---

### Task 6: Existing back mode

Profiles the waste out of an existing Blum back and pockets the new ends behind it.

**Files:**
- Modify: `BoxJointRuns/BoxJointRegistry.xlua` (Existing back defaults, read, write)
- Modify: `BoxJointRuns/BoxJointDialog.xlua` (Existing back inputs, "Existing back" mode option)
- Modify: `BoxJointRuns/BoxJointGeometry.xlua` (`RunExistingBack`)
- Modify: `BoxJointRuns/Box_Joint_Runs.lua` (dispatch to `RunExistingBack`, extend `ValidateSettings`)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `ClearModeLayer`, `DrawFingerEnd`, `CreateExistingFingerToolpath` from Task 5; `CreateProfilePass` from Task 3.
- Produces: `Run.EBBackLength`, `Run.EBFirstStub`, `Run.EBOpening ∈ number`; `Run.EBPhase ∈ {"Finger", "Gap"}`; `Milling.LNExistingProfile = "BJR Existing Profile"`, `Milling.LNExistingBackFingers = "BJR Existing Fingers"` (shares the name with Existing end per the spec's "own toolpath names" being about *this mode's* set, not a cross-mode collision — see Step 3 note); `Milling.TPExistingProfile = "BJR Existing Profile"`; `RunExistingBack() -> boolean`.

- [ ] **Step 1: Registry**

Add to both default tables:

```lua
    EBBackLength = 24.0000, -- imperial; 600.0000 metric
    EBFirstStub = 9.0000, -- imperial; 225.0000 metric
    EBOpening = 6.0000, -- imperial; 150.0000 metric
    EBPhase = "Finger",
```

Add to `SettingsRead()`:

```lua
    Run.EBBackLength = registry:GetDouble(SettingsKey("EBBackLength"), defaults.EBBackLength)
    Run.EBFirstStub = registry:GetDouble(SettingsKey("EBFirstStub"), defaults.EBFirstStub)
    Run.EBOpening = registry:GetDouble(SettingsKey("EBOpening"), defaults.EBOpening)
    Run.EBPhase = registry:GetString(SettingsKey("EBPhase"), defaults.EBPhase)
```

Add to `SettingsWrite()`:

```lua
    registry:SetDouble(SettingsKey("EBBackLength"), Run.EBBackLength)
    registry:SetDouble(SettingsKey("EBFirstStub"), Run.EBFirstStub)
    registry:SetDouble(SettingsKey("EBOpening"), Run.EBOpening)
    registry:SetString(SettingsKey("EBPhase"), Run.EBPhase)
```

- [ ] **Step 2: Dialog**

Add `<option value="Existing Back">Existing back</option>` to `Run.Mode`, and this block before
`<h2>Mode</h2>`:

```html
<tr><td colspan="4"><h2>Existing back</h2></td></tr>
<tr>
  <td><label>Back length</label></td>
  <td><input type="text" id="Run.EBBackLength" size="10"/></td>
  <td><label title="From zero (the back's top-right corner) to the first cut end.">First stub length</label></td>
  <td><input type="text" id="Run.EBFirstStub" size="10"/></td>
</tr>
<tr>
  <td><label title="Between the two cut ends. Equals the notch front piece's overall length.">Notch opening</label></td>
  <td><input type="text" id="Run.EBOpening" size="10"/></td>
  <td><label>Phase of the stub ends</label></td>
  <td>
    <select id="Run.EBPhase" size="1">
      <option value="Finger">Finger at bottom</option>
      <option value="Gap">Gap at bottom</option>
    </select>
  </td>
</tr>
```

In `BuildDialog()`, add:

```lua
    Run.dialog:AddDoubleField("Run.EBBackLength", Run.EBBackLength)
    Run.dialog:AddDoubleField("Run.EBFirstStub", Run.EBFirstStub)
    Run.dialog:AddDoubleField("Run.EBOpening", Run.EBOpening)
    Run.dialog:AddDropDownList("Run.EBPhase", Run.EBPhase)
```

In `ShowSettingsDialog()`, add:

```lua
    Run.EBBackLength = math.abs(Run.dialog:GetDoubleField("Run.EBBackLength"))
    Run.EBFirstStub = math.abs(Run.dialog:GetDoubleField("Run.EBFirstStub"))
    Run.EBOpening = math.abs(Run.dialog:GetDoubleField("Run.EBOpening"))
    Run.EBPhase = Run.dialog:GetDropDownListValue("Run.EBPhase")
```

- [ ] **Step 3: Validation**

In `Box_Joint_Runs.lua`, extend `ValidateSettings()`:

```lua
    if Run.Mode == "Existing Back" then
        if Run.EBFirstStub <= Run.StockT then
            return false, "First stub length must be greater than the stock thickness."
        end
        if Run.EBOpening <= 0.0 then
            return false, "Notch opening must be greater than zero."
        end
        if (Run.EBFirstStub + Run.EBOpening + Run.StockT) >= Run.EBBackLength then
            return false, "First stub length + opening + thickness must be less than the back length."
        end
    end
```

- [ ] **Step 4: `RunExistingBack`, in `BoxJointGeometry.xlua`**

```lua
function RunExistingBack()
    -- Setup fixed by the Blum back's shape: it lies with its bottom edge away from the operator (top edge
    -- along Y = 0), zero is the back's top-right corner (the operator's lower-left), X runs along the top edge.
    -- The middle -- from Run.EBFirstStub to Run.EBFirstStub + Run.EBOpening -- is profiled out as a rectangle,
    -- inside, full depth, with no tabs; it comes loose and the operator screws it down. The gap bands are
    -- pocketed behind each new end. No groove: the back already has one.
    Milling.LNExistingProfile = "BJR Existing Profile" .. ThicknessTag(Run.StockT)
    Milling.LNExistingBackFingers = "BJR Existing Fingers" .. ThicknessTag(Run.StockT)
    Milling.TPExistingProfile = "BJR Existing Profile"
    Milling.TPExistingBackFingers = "BJR Existing Fingers"
    ClearModeLayer(Milling.LNExistingProfile)
    ClearModeLayer(Milling.LNExistingBackFingers)
    -- The back lies in +Y: its top edge on Y = 0, its bottom (groove) edge on Y = Run.StockW. Finger ends are
    -- anchored on the bottom edge and count bands toward the top edge, so dir_across is 270.0.
    local bottom_y = Run.StockW
    local across = 270.0
    local near_x = Run.EBFirstStub -- the first stub's new end; that stub's body is at X < near_x
    local far_x = Run.EBFirstStub + Run.EBOpening -- the second stub's new end; its body is at X > far_x
    -- The waste rectangle, Y = 0 to Y = W: full depth, inside, no tabs.
    DrawBox(Point2D(near_x, 0.0), Point2D(near_x, bottom_y), Point2D(far_x, bottom_y), Point2D(far_x, 0.0),
        Milling.LNExistingProfile)
    -- Both stub ends take the one chosen phase; phase is measured from the bottom edge, so each stub meets its
    -- notch side the same way. The chain's start and end dropdowns are set to the opposite phase.
    DrawFingerEnd(Point2D(near_x, bottom_y), 180.0, across, Run.EBPhase, Milling.LNExistingBackFingers)
    DrawFingerEnd(Point2D(far_x, bottom_y), 0.0, across, Run.EBPhase, Milling.LNExistingBackFingers)
    Milling.job:Refresh2DView()
    return true
end
```

`DrawFingerEnd`'s `dir_into` always points into the stub that keeps the end: `180.0` at the first stub's
end (its body lies at lower X) and `0.0` at the second stub's. The gap pockets recess into each stub, never
into the waste.

- [ ] **Step 5: Toolpaths and dispatch**

In `Box_Joint_Runs.lua`, extend the mode dispatch:

```lua
    elseif Run.Mode == "Existing Back" then
        RunExistingBack()
        CreateProfilePass(Milling.TPExistingProfile, Milling.LNExistingProfile, "IN", false, 0.0, false)
        CreateExistingFingerToolpath(Milling.LNExistingBackFingers, Milling.TPExistingBackFingers)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
```

- [ ] **Step 6: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| Basic setup | Mode = Existing back, back length 24", first stub 9", opening 6", phase Finger at bottom | A rectangle from X=9 to X=15, Y=0 to Y=W is drawn on "BJR Existing Profile (T)"; gap pockets appear at X=8.25 to 9 and X=15 to 15.75 (for T = 0.75") on "BJR Existing Fingers (T)". Both ends have a finger, not a pocket, in the band touching Y=W (the bottom edge) |
| Validation: stub too short | Set first stub length to less than the stock thickness | "First stub length must be greater than the stock thickness." |
| Validation: opening zero | Set opening to 0 | "Notch opening must be greater than zero." |
| Validation: exceeds back length | Set first stub + opening + thickness ≥ back length | "First stub length + opening + thickness must be less than the back length." |
| No groove drawn | Any valid setup | No vectors appear on any Groove layer for this mode |
| Re-run replaces | Change the phase, run again | Previous profile/finger vectors for this mode are gone; only the new ones remain |
| Toolpaths | Run to completion | "BJR Existing Profile" cuts the middle rectangle free (inside, no tabs); "BJR Existing Fingers" pockets the two new ends; re-running recalculates both |
| Mill on scrap | Mill a scrap board standing in for the back, bottom edge away from you, zero at its top-right corner; screw the middle down first. Then cut a 3-piece Chain with start and end set to Gap at bottom | The middle comes free; each notch side's fingers seat into a stub end with both groove edges on the same side |

- [ ] **Step 7: Commit**

```bash
git add BoxJointRuns/BoxJointRegistry.xlua BoxJointRuns/BoxJointDialog.xlua BoxJointRuns/BoxJointGeometry.xlua BoxJointRuns/Box_Joint_Runs.lua
git commit -m "Add Existing back mode."
```

---

### Task 7: Help page and repository README

**Files:**
- Create: `BoxJointRuns/Help/HelpMain.xlua`
- Modify: `BoxJointRuns/BoxJointDialog.xlua` (Help button wiring)
- Modify: `README.md` (repository root — table row and section)
- Test: none — verified by the user in VCarve

**Interfaces:**
- Consumes: `Project.AppPath`-equivalent path passed as `script_path` to `main`; store it on `Run.AppPath` in Task 1's `main` (add `Run.AppPath = string.gsub(script_path, "\\", "/")` right after `Milling.job = VectricJob()`) so the Help loader can find `Help/HelpMain.xlua` the same way `Blum_Drawer_Maker.lua:67,1310` does.
- Produces: `HTMLHelpMain() -> nil` (sets `Run.HelpHtml`); `OnLuaButton_InquiryHelpMain() -> boolean`.

- [ ] **Step 1: Store the app path**

In `Box_Joint_Runs.lua`'s `main`, immediately after `Milling.job = VectricJob()`, add:

```lua
    Run.AppPath = string.gsub(script_path, "\\", "/")
```

- [ ] **Step 2: The Help page**

```lua
-- VECTRIC LUA SCRIPT
-- =====================================================]]
function HTMLHelpMain()
    Run.HelpHtml = [[<!DOCTYPE html><html><head><title>Box Joint Runs Help</title>
<style>
body { font-family: Arial, sans-serif; font-size: 12px; }
h2 { font-size: 13px; margin: 10px 0 2px 0; }
</style></head><body>
<h2>Reading the phase labels on a board in hand</h2>
<p>Lay the board with the groove (or the edge that will carry the groove) toward you. Look at one end.
If the first strip of material at that groove edge is solid wood, the end is <b>Finger at bottom</b>.
If the first strip is a notch (empty), the end is <b>Gap at bottom</b>. Two ends that mate always show
opposite labels: one Finger at bottom, one Gap at bottom.</p>
<h2>Existing back setup</h2>
<p>Turn the back so its bottom edge (the one with the Blum runner cutouts) faces away from you, and its
top edge runs left to right along the front of the machine. Zero the job at the operator's lower-left
corner -- that is the back's top-right corner. X then runs along the back's top edge toward the left.
Enter the first stub length (zero to the first cut end), the notch opening (between the two cut ends),
and the phase of the stub ends. After cutting, the middle of the back comes loose -- screw it back down
once the new notch pieces are in place.</p>
<h2>Turning a right-hand stub end for end (Existing end mode)</h2>
<p>Existing end mode always draws at X = 0 with zero at the corner being cut, and never draws anything at
negative X. For a right-hand stub, turn the board end for end on the machine so the end you are cutting
is still at the zero corner; the gadget mirrors the pattern using the "toward/away" input rather than
drawing a second copy at negative X.</p>
<h2>The bottom panel</h2>
<p>This gadget does not cut the bottom panel. Cut it separately, with its own U-shaped notch removed to
match the run drawn here.</p>
</body></html>]]
end
-- =============== End of File =========================]]
```

- [ ] **Step 3: Wire the Help button**

In `BoxJointRuns/BoxJointDialog.xlua`, add:

```lua
function OnLuaButton_InquiryHelpMain()
    local Helper
    Helper = assert(loadfile(Run.AppPath .. "/Help/HelpMain.xlua"))(Helper)
    HTMLHelpMain()
    local dialog = HTML_Dialog(true, Run.HelpHtml, 560, 520, "Box Joint Runs Help")
    dialog:ShowDialog()
    return true
end
```

This matches the `id="InquiryHelpMain"` button already present in `BuildDialog()`'s HTML from Task 1
Step 3 — the `LuaButton` class binds that element's click to this function by naming convention,
exactly as `BlumDrawerDialog.xlua:1308-1319` does for `InquiryHelpMain`.

- [ ] **Step 4: Repository README**

Read the repository root `README.md`, find the table listing each gadget (matching the row for
`BlumDrawerMaker`/Hold Down Helper), and add a row for Box Joint Runs pointing at
`BoxJointRuns/README.md`, plus a section below the existing gadget sections summarizing what it does
(a chain of through-finger-jointed 90° corners, plus adding finger ends to an existing Blum back or a
single existing end, plus a test-cut mode) — following the exact structure the existing rows/sections
use (read one full existing row and section first to match its column order and heading level).

- [ ] **Step 5: Package and have the user verify**

```powershell
pwsh ./deploy.ps1 -SourceFolder BoxJointRuns
```

| Case | Action | Expected |
| --- | --- | --- |
| Help button | Open the gadget, click Help | A page opens covering phase labels, Existing back setup, turning a stub end for end, and the bottom panel note |
| Help from any mode | Switch Mode to each of Chain / Existing back / Existing end / Test cut, click Help each time | The same Help page opens regardless of the selected mode |

- [ ] **Step 6: Commit**

```bash
git add BoxJointRuns/Help/HelpMain.xlua BoxJointRuns/BoxJointDialog.xlua BoxJointRuns/Box_Joint_Runs.lua README.md
git commit -m "Add the Help page and list Box Joint Runs in the repository README."
```
