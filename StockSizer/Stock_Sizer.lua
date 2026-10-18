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
-- Stock Sizer is an original gadget from the vectric-gadgets repository, https://github.com/tippmar/vectric-gadgets
-- ====================================================================================================================================
-- Stock Sizer: finds the bounding box of every visible vector on the active sheet, adds a margin for the cutter,
-- and reports the size of stock the job needs. It can then resize the sheet to that size, so a job can be drawn on
-- a full sheet and the stock size read off afterward.
]] -- =====================================================]]
require "strict"
-- Layer visibility is layer.Visible, a contour's bounds are contour.BoundingBox2D (.MinX .MinY .MaxX .MaxY), and a
-- group has no contour (ClassName "vcCadObjectGroup"); all confirmed against V12.5 by the Hold Down Helper probe.
-- job.SheetManager:ResizeSheet is undocumented. Probed against V12.5 on 2026-10-18:
--   ResizeSheet(sheet id, width, height, thickness, false) -> resizes; the width/height-only forms are refused for a
--   flat sheet with VCarve's own dialog "Incorrect parameters for resizing flat sheet", and still return normally
--   The sheet keeps its lower-left corner (it stays at the origin) and the vectors do not move

StockSizer = {}
StockSizer.ProgramVersion = "1.0"
StockSizer.RegName = "StockSizer" .. StockSizer.ProgramVersion
StockSizer.job = nil
StockSizer.InMM = false
StockSizer.UnitLabel = "inches"
-- =====================================================]]
function IdKey(raw_id) -- String form of a UUID, usable as a table key
    return luaUUID(raw_id):AsString()
end
-- =====================================================]]
function ReadUnits()
    if MaterialBlock().InMM then
        StockSizer.InMM = true
        StockSizer.UnitLabel = "mm"
    else
        StockSizer.InMM = false
        StockSizer.UnitLabel = "inches"
    end
end
-- =====================================================]]
local IMPERIAL_DEFAULTS = {ToolDiameter = 0.25, Allowance = 0.125, RoundUp = "None", ReportOnly = true,
    DialogSize = "380 x 260"}
local METRIC_DEFAULTS = {ToolDiameter = 6.0, Allowance = 3.0, RoundUp = "None", ReportOnly = true,
    DialogSize = "380 x 260"}
-- The round-up choices in list order, each a label and its size in job units. The label is what is saved.
local IMPERIAL_ROUND_UP = {
    {label = "None", size = 0.0}, {label = "1/8 inch", size = 0.125}, {label = "1/4 inch", size = 0.25},
    {label = "1/2 inch", size = 0.5}, {label = "1 inch", size = 1.0}
}
local METRIC_ROUND_UP = {
    {label = "None", size = 0.0}, {label = "1 mm", size = 1.0}, {label = "5 mm", size = 5.0},
    {label = "10 mm", size = 10.0}, {label = "25 mm", size = 25.0}, {label = "50 mm", size = 50.0}
}
-- =====================================================]]
function RoundUpChoices()
    if StockSizer.InMM then
        return METRIC_ROUND_UP
    end
    return IMPERIAL_ROUND_UP
end
-- =====================================================]]
function RoundUpSize()
    -- A saved label that is not in the list (a hand-edited or older value) means no rounding
    for _, choice in ipairs(RoundUpChoices()) do
        if choice.label == StockSizer.RoundUp then
            return choice.size
        end
    end
    return 0.0
end
-- =====================================================]]
function DialogSize(text)
    -- "W x H" back to numbers, as Blum Drawer Maker does; a damaged value gives the default size
    local width, height = string.match(tostring(text), "^(%d+) x (%d+)$")
    if width == nil or tonumber(width) < 380 or tonumber(height) < 260 then
        return 380, 260
    end
    return tonumber(width), tonumber(height)
end
-- =====================================================]]
function SettingsKey(name)
    if StockSizer.InMM then
        return "Metric." .. name
    end
    return "Imperial." .. name
end
-- =====================================================]]
function SettingsRead()
    local registry = Registry(StockSizer.RegName)
    local defaults = IMPERIAL_DEFAULTS
    if StockSizer.InMM then
        defaults = METRIC_DEFAULTS
    end
    StockSizer.ToolDiameter = registry:GetDouble(SettingsKey("ToolDiameter"), defaults.ToolDiameter)
    StockSizer.Allowance = registry:GetDouble(SettingsKey("Allowance"), defaults.Allowance)
    StockSizer.RoundUp = registry:GetString(SettingsKey("RoundUpChoice"), defaults.RoundUp)
    StockSizer.DialogSize = registry:GetString("DialogSize", defaults.DialogSize)
    StockSizer.ReportOnly = registry:GetBool(SettingsKey("ReportOnly"), defaults.ReportOnly)
end
-- =====================================================]]
function SettingsWrite()
    local registry = Registry(StockSizer.RegName)
    registry:SetDouble(SettingsKey("ToolDiameter"), StockSizer.ToolDiameter)
    registry:SetDouble(SettingsKey("Allowance"), StockSizer.Allowance)
    registry:SetString(SettingsKey("RoundUpChoice"), StockSizer.RoundUp)
    registry:SetString("DialogSize", StockSizer.DialogSize)
    registry:SetBool(SettingsKey("ReportOnly"), StockSizer.ReportOnly)
end
-- =====================================================]]
function Margin()
    -- An outside profile puts the cutter center half a diameter outside the vector, so the cutter's far edge
    -- is a FULL diameter out. The allowance goes on top of that.
    return StockSizer.ToolDiameter + StockSizer.Allowance
end
-- =====================================================]]
function RoundUpOptions()
    local options = ""
    for _, choice in ipairs(RoundUpChoices()) do
        options = options .. "<option>" .. choice.label .. "</option>"
    end
    return options
end
-- =====================================================]]
function SettingsHtml()
    local unit = StockSizer.UnitLabel
    return [[<html><head><style>
html { overflow: hidden; }
body { font-family: Arial, sans-serif; font-size: 12px; background-color: #F0F0F0; overflow: hidden; }
table { border-collapse: collapse; }
td { padding: 2px 6px; }
td.label { text-align: right; }
td.unit { color: #666666; }
.buttons { text-align: right; margin-top: 8px; }
</style></head><body>
<table>
<tr><td class="label"><label title="Largest cutter that cuts outside a vector">Largest tool diameter:</label></td>
    <td><input type="text" id="ToolDiameter" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Extra stock beyond the cutter, on every side">Extra allowance:</label></td>
    <td><input type="text" id="Allowance" size="10" maxlength="10" /></td><td class="unit">]] .. unit .. [[</td></tr>
<tr><td class="label"><label title="Round width and length up to a multiple of this. None leaves them as measured">Round up to:</label></td>
    <td><select id="RoundUp">]] .. RoundUpOptions() .. [[</select></td><td>&nbsp;</td></tr>
<tr><td class="label"><label title="Show the size only; do not change the sheet">Report only:</label></td>
    <td><input type="checkbox" id="ReportOnly" /></td><td>&nbsp;</td></tr>
</table>
<p class="buttons"><input id="InquiryHelp" class="LuaButton" type="button" value="Help">
<input id="InquiryAbout" class="LuaButton" type="button" value="About">
<input id="ButtonOK" class="FormButton" type="button" value="Size Stock">
<input id="ButtonCancel" class="FormButton" type="button" value="Cancel"></p>
</body></html>]]
end
-- =====================================================]]
function ShowSettingsDialog()
    local width, height = DialogSize(StockSizer.DialogSize)
    local dialog = HTML_Dialog(true, SettingsHtml(), width, height, "Stock Sizer (" .. StockSizer.UnitLabel .. ")")
    dialog:AddDoubleField("ToolDiameter", StockSizer.ToolDiameter)
    dialog:AddDoubleField("Allowance", StockSizer.Allowance)
    dialog:AddDropDownList("RoundUp", StockSizer.RoundUp)
    dialog:AddCheckBox("ReportOnly", StockSizer.ReportOnly)
    if not dialog:ShowDialog() then
        return false
    end
    -- Every distance is a magnitude; a negative one is always a typo.
    StockSizer.ToolDiameter = math.abs(dialog:GetDoubleField("ToolDiameter"))
    StockSizer.Allowance = math.abs(dialog:GetDoubleField("Allowance"))
    StockSizer.RoundUp = dialog:GetDropDownListValue("RoundUp")
    StockSizer.DialogSize = tostring(dialog.WindowWidth) .. " x " .. tostring(dialog.WindowHeight)
    StockSizer.ReportOnly = dialog:GetCheckBox("ReportOnly")
    return true
end
-- =====================================================]]
function IsLayerVisible(layer)
    -- Failing to read it means "visible", so an unknown layer still counts toward the size
    local ok, visible = pcall(function()
        return layer.Visible
    end)
    if ok and visible ~= nil then
        return visible
    end
    return true
end
-- =====================================================]]
function GrowBounds(bounds, min_x, min_y, max_x, max_y)
    if bounds.min_x == nil then
        bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y = min_x, min_y, max_x, max_y
        return
    end
    bounds.min_x = math.min(bounds.min_x, min_x)
    bounds.min_y = math.min(bounds.min_y, min_y)
    bounds.max_x = math.max(bounds.max_x, max_x)
    bounds.max_y = math.max(bounds.max_y, max_y)
end
-- =====================================================]]
function AddObjectBounds(object, bounds, counts)
    -- Vectors use their contour's box; groups are walked; text and bitmaps fall back to the object's box
    local contour = object:GetContour()
    if contour ~= nil then
        local box = contour.BoundingBox2D
        GrowBounds(bounds, box.MinX, box.MinY, box.MaxX, box.MaxY)
        counts.vectors = counts.vectors + 1
    elseif object.ClassName == "vcCadObjectGroup" then
        local group = CastCadObjectToCadObjectGroup(object)
        local pos = group:GetHeadPosition()
        while pos ~= nil do
            local member
            member, pos = group:GetNext(pos)
            AddObjectBounds(member, bounds, counts)
        end
    else
        local ok, box = pcall(function()
            return object:GetBoundingBox()
        end)
        if ok and box ~= nil then
            GrowBounds(bounds, box.MinX, box.MinY, box.MaxX, box.MaxY)
            counts.boxed = counts.boxed + 1
        else
            counts.unread = counts.unread + 1
        end
    end
end
-- =====================================================]]
function SheetBounds(job)
    -- Bounds of every object on the active sheet, on any visible layer
    local sheet_key = IdKey(job.SheetManager.ActiveSheetId)
    local layer_manager = job.LayerManager
    local bounds = {}
    local counts = {vectors = 0, boxed = 0, unread = 0}
    local pos = layer_manager:GetHeadPosition()
    while pos ~= nil do
        local layer
        layer, pos = layer_manager:GetNext(pos)
        if (not layer.IsSystemLayer) and IsLayerVisible(layer) then
            local object_pos = layer:GetHeadPosition()
            while object_pos ~= nil do
                local object
                object, object_pos = layer:GetNext(object_pos)
                if IdKey(object.SheetId) == sheet_key then
                    AddObjectBounds(object, bounds, counts)
                end
            end
        end
    end
    return bounds, counts
end
-- =====================================================]]
function RoundedUp(length)
    local step = RoundUpSize()
    if step <= 0.0 then
        return length
    end
    -- The small subtraction stops 12.0000000001 from rounding up to the next step
    return math.ceil((length / step) - 1e-9) * step
end
-- =====================================================]]
function Fmt(value)
    return string.format("%.3f", value) .. " " .. StockSizer.UnitLabel
end
-- =====================================================]]
function SizeText(value)
    -- Three decimals, with the inch mark or mm, for the final message
    if StockSizer.InMM then
        return string.format("%.3f", value) .. " mm"
    end
    return string.format("%.3f", value) .. '"'
end
-- =====================================================]]
function NotesHtml(notes)
    if notes == nil or notes == "" then
        return ""
    end
    return '<div class="note">' .. string.gsub(notes, "\n", "<br>") .. "</div>"
end
-- =====================================================]]
function ConfirmResize(current_width, current_height, width, height, margin, notes)
    -- VCarve has no undo for a sheet size change, so nothing is resized until this returns true
    local html = [[<html><head><style>
html { overflow: hidden; }
body { font-family: Arial, sans-serif; font-size: 12px; background-color: #F0F0F0; overflow: hidden; }
td { padding: 2px 6px; }
td.label { text-align: right; }
.note { background-color: #FFF4CE; border: 1px solid #D9A400; padding: 6px; margin-top: 8px; }
.buttons { text-align: right; margin-top: 8px; }
</style></head><body>
<table>
<tr><td class="label">Current size:</td><td><b>]] .. SizeText(current_width) .. " x " .. SizeText(current_height) .. [[</b></td></tr>
<tr><td class="label">Proposed size:</td><td><b>]] .. SizeText(width) .. " x " .. SizeText(height) .. [[</b></td></tr>
<tr><td class="label">Margin:</td><td>]] .. SizeText(margin) .. [[</td></tr>
</table>
<div class="note"><b>VCarve cannot undo a sheet size change.</b> Resize the sheet?</div>]] .. NotesHtml(notes) .. [[
<p class="buttons"><input id="ButtonOK" class="FormButton" type="button" value="Resize Sheet">
<input id="ButtonCancel" class="FormButton" type="button" value="Cancel"></p>
</body></html>]]
    local dialog = HTML_Dialog(true, html, 520, 360, "Resize Sheet?")
    return dialog:ShowDialog()
end
-- =====================================================]]
function ResizeActiveSheet(job, width, height)
    -- V12.5 accepts ResizeSheet(sheet id, width, height, thickness, bool); the width/height-only forms are
    -- refused for a flat sheet. The sheet keeps its lower-left corner and the vectors do not move. VCarve can
    -- refuse with its own dialog and still return normally, so the result is judged by the sheet's size.
    local sheet_id = job.SheetManager.ActiveSheetId
    local thickness = MaterialBlock().Thickness
    local ok, result = pcall(function()
        return job.SheetManager:ResizeSheet(sheet_id, width, height, thickness, false)
    end)
    local block = MaterialBlock()
    local tolerance = 1e-4
    if ok and math.abs(block.Width - width) < tolerance and math.abs(block.Height - height) < tolerance then
        return true
    end
    return false, tostring(result)
end
-- =====================================================]]
function OnLuaButton_InquiryHelp(dialog)
    -- The page is loaded on demand, the way Hold Down Helper loads its Help page
    local ok, loader = pcall(loadfile, StockSizer.AppPath .. "/Help/HelpMain.xlua")
    if not ok or loader == nil then
        DisplayMessageBox("The Stock Sizer help page is missing from:\n" .. StockSizer.AppPath .. "/Help\n\n" ..
            "Reinstall the gadget to restore it.")
        return true
    end
    loader()
    local help = HTML_Dialog(true, StockSizerHelpHtml(), 760, 640, "Stock Sizer Help")
    help:ShowDialog()
    return true
end
-- =====================================================]]
function OnLuaButton_InquiryAbout(dialog)
    local html = [[<html><head><style>
html { overflow: hidden; }
body { font-family: Arial, sans-serif; font-size: 12px; background-color: #F0F0F0; overflow: hidden; }
h2 { margin: 4px 0; }
.buttons { text-align: right; margin-top: 12px; }
</style></head><body>
<h2>Stock Sizer</h2>
<p>Version ]] .. StockSizer.ProgramVersion .. [[<br>
Finds the size of stock that a job needs and resizes the sheet to it.</p>
<p>An original gadget from the vectric-gadgets repository:<br>
https://github.com/tippmar/vectric-gadgets</p>
<p>Gadgets are an entirely optional add-in to Vectric's core software products. They are provided 'as-is',
without any express or implied warranty, and you make use of them entirely at your own risk. See the Help page
for the full terms.</p>
<p class="buttons"><input id="ButtonOK" class="FormButton" type="button" value="Close"></p>
</body></html>]]
    local about = HTML_Dialog(true, html, 460, 320, "About Stock Sizer")
    about:ShowDialog()
    return true
end
-- =====================================================]]
function main(script_path)
    StockSizer.AppPath = (string.gsub(script_path, "\\", "/"))
    local job = VectricJob()
    if not job.Exists then
        DisplayMessageBox("Stock Sizer needs a job.\n\nOpen or create one, then run the gadget again.")
        return false
    end
    StockSizer.job = job
    ReadUnits()
    SettingsRead()

    local bounds, counts = SheetBounds(job)
    if bounds.min_x == nil then
        DisplayMessageBox("There are no visible vectors on the active sheet, so there is nothing to size.\n\n" ..
            "Stock Sizer made no changes.")
        return false
    end
    if not ShowSettingsDialog() then
        return false
    end
    SettingsWrite()

    local margin = Margin()
    local mtl_block = MaterialBlock()
    local sheet_blc = mtl_block.MaterialBox.BLC
    local span_x = bounds.max_x - bounds.min_x
    local span_y = bounds.max_y - bounds.min_y
    -- The resize keeps the sheet's lower-left corner and does not move the vectors, so the size runs from that
    -- corner out past the vectors' far edges
    local width = RoundedUp((bounds.max_x - sheet_blc.x) + margin)
    local height = RoundedUp((bounds.max_y - sheet_blc.y) + margin)
    local tight_left = bounds.min_x - sheet_blc.x
    local tight_bottom = bounds.min_y - sheet_blc.y
    -- Stock needed if the vectors sat the margin in from the lower-left corner
    local packed_width = RoundedUp(span_x + (2.0 * margin))
    local packed_height = RoundedUp(span_y + (2.0 * margin))

    local message = "Stock Sizer\n\nThe vectors measure " .. Fmt(span_x) .. " x " .. Fmt(span_y) ..
        ".\nMargin: " .. Fmt(margin) .. ".\n\nThe sheet was: " .. Fmt(mtl_block.Width) .. " x " .. Fmt(mtl_block.Height) ..
        "\nStock needed with the vectors where they are: " .. Fmt(width) .. " x " .. Fmt(height)
    if packed_width < width or packed_height < height then
        message = message .. "\nStock needed if the vectors were moved to the lower-left corner: " ..
            Fmt(packed_width) .. " x " .. Fmt(packed_height)
    end
    local notes = ""
    if tight_left < margin or tight_bottom < margin then
        notes = notes .. "WARNING: The vectors are " .. Fmt(tight_left) .. " from the left edge and " ..
            Fmt(tight_bottom) .. " from the bottom edge, less than the margin on at least one side. Move them " ..
            "away from the lower-left corner first.\n"
    end
    if counts.boxed > 0 then
        notes = notes .. "NOTE: " .. counts.boxed .. " object(s) have no vector outline. Their bounding boxes were used.\n"
    end
    if counts.unread > 0 then
        notes = notes .. "NOTE: " .. counts.unread .. " object(s) could not be read and were NOT counted.\n"
    end
    if width >= mtl_block.Width and height >= mtl_block.Height then
        message = message .. "\n\nThe vectors already fill the sheet."
    end
    if notes ~= "" then
        message = message .. "\n\n" .. notes
    end
    if StockSizer.ReportOnly then
        MessageBox(message .. "\n\nReport only: the sheet was not changed.")
        return true
    end
    if not ConfirmResize(mtl_block.Width, mtl_block.Height, width, height, margin, notes) then
        MessageBox("The sheet was not resized.")
        return true
    end
    local resized, problem = ResizeActiveSheet(job, width, height)
    if resized then
        MessageBox("The sheet was resized to " .. SizeText(width) .. " x " .. SizeText(height) .. ".")
    else
        MessageBox("The sheet was NOT resized. " .. tostring(problem))
    end
    return true
end
-- =============== End of File =========================]]
