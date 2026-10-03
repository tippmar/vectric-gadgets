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
-- Shaker Maker borrows its dialog look, layer/toolpath plumbing and sheet handling from this repository's own Blum
-- Drawer Maker (by way of Box Joint Runs), which is itself based on Easy Drawer Maker, originally written by JimAndi
-- Gadgets, 2019.
]] -- =====================================================]]
-- Shaker Maker carves a shaker look into a solid slab (MDF): the center panel is recessed, leaving the rails and
-- stiles standing as a raised frame. The panel wall is either straight (end mill) or beveled (V-bit).
require "strict"
Shaker = {}
Milling = {}
Shaker.RegName = "ShakerMaker"
Shaker.AppPath = "" -- the installed gadget folder, set from main's script_path; the Help page lives under it
lead_in_out_data = LeadInOutData()
-- =====================================================]]
function GetMaterialSettings()
    local mtl_block = MaterialBlock()
    if mtl_block.InMM then
        Shaker.InMM = true
        Shaker.Cal = 25.4
        Shaker.UnitLabel = "(mm)"
    else
        Shaker.InMM = false
        Shaker.Cal = 1.0
        Shaker.UnitLabel = "(in)"
    end
end
-- =====================================================]]
function ClearingTools()
    -- The clearing bits in the order they cut: the bulk bit, then each enabled corner bit. A corner bit is used only
    -- while every bit before it is, so the list never has holes.
    local tools = {Milling.BulkTool}
    if Shaker.Corner1On then
        table.insert(tools, Milling.Corner1Tool)
        if Shaker.Corner2On then
            table.insert(tools, Milling.Corner2Tool)
        end
    end
    return tools
end
-- =====================================================]]
function RecomputeDerived()
    -- Panel geometry, relative to the door's bottom-left corner.
    --   Top:   the panel's outline on the face of the door, where the frame ends.
    --   Floor: the outline of the flat recess floor.
    -- A straight wall makes the two the same. A V-bit wall slopes in by Bevel = depth x tan(half the bit angle),
    -- so the floor is smaller than the top. Rail and stile widths are measured either to the bottom of the bevel
    -- (the frame, bevel included, is exactly the entered width, as a five-piece door's frame would be) or to the
    -- top of it (the flat face of the frame is the entered width, and the bevel eats into the panel).
    Shaker.Bevel = 0.0
    if Shaker.Edge == "V-Bit" then
        Shaker.Bevel = Shaker.Depth * math.tan(math.rad(Milling.VBitTool.VBit_Angle * 0.5))
    end
    local floor_stile, floor_rail = Shaker.StileW, Shaker.RailW
    if Shaker.Edge == "V-Bit" and Shaker.MeasureTo == "Top of Bevel" then
        floor_stile = Shaker.StileW + Shaker.Bevel
        floor_rail = Shaker.RailW + Shaker.Bevel
    end
    Shaker.FloorStile = floor_stile
    Shaker.FloorRail = floor_rail
    Shaker.TopStile = floor_stile - Shaker.Bevel
    Shaker.TopRail = floor_rail - Shaker.Bevel
    Shaker.FloorW = Shaker.Width - (2.0 * floor_stile)
    -- A middle stile splits the panel into two of equal height, one above the other. It is a stile's width wide,
    -- measured the same way, but it has a bevel on both sides: its floor gap is that width when measured to the
    -- bottom of the bevel, and that width plus both bevels when measured to the top.
    Shaker.FloorMid = 0.0
    Shaker.TopMid = 0.0
    local panels = 1
    if Shaker.MiddleStile then
        panels = 2
        Shaker.FloorMid = Shaker.StileW
        if Shaker.Edge == "V-Bit" and Shaker.MeasureTo == "Top of Bevel" then
            Shaker.FloorMid = Shaker.StileW + (2.0 * Shaker.Bevel)
        end
        Shaker.TopMid = Shaker.FloorMid - (2.0 * Shaker.Bevel)
    end
    Shaker.FloorH = (Shaker.Height - (2.0 * floor_rail) - Shaker.FloorMid) / panels
    -- Bottom edge of each panel's floor, measured from the door's bottom edge.
    Shaker.PanelFloorY = {floor_rail}
    if Shaker.MiddleStile then
        table.insert(Shaker.PanelFloorY, floor_rail + Shaker.FloorH + Shaker.FloorMid)
    end
    -- Each corner bit pockets a square in every floor corner, big enough to take out the round the bit before it
    -- left (a quarter circle of that bit's radius inside a radius-sized square) plus its own radius of overlap.
    Shaker.CornerSize = {}
    local tools = ClearingTools()
    for i = 2, #tools do
        local size = (tools[i - 1].ToolDia * 0.5) + (tools[i].ToolDia * 0.5)
        Shaker.CornerSize[i] = math.min(size, Shaker.FloorW * 0.5, Shaker.FloorH * 0.5)
    end
    Shaker.CornerRadius = tools[#tools].ToolDia * 0.5
end
-- =====================================================]]
function Fmt(value)
    return string.format("%.4f", value)
end
-- =====================================================]]
function ValidateSettings()
    local tools = {
        {Milling.BulkTool, "bulk clearing bit", true},
        {Milling.Corner1Tool, "first corner bit", Shaker.Corner1On},
        {Milling.Corner2Tool, "second corner bit", Shaker.Corner1On and Shaker.Corner2On},
        {Milling.VBitTool, "V-bit", Shaker.Edge == "V-Bit"},
        {Milling.ProfileTool, "profile bit", Shaker.CutOut}
    }
    for _, entry in ipairs(tools) do
        if entry[3] then
            if entry[1] == nil then
                return false, "Choose the " .. entry[2] .. "."
            end
            if entry[1].InMM ~= Shaker.InMM then
                return false, "The " .. entry[2] .. "'s units do not match the job units. Choose a bit in the job units."
            end
        end
    end
    if Shaker.Width <= 0.0 or Shaker.Height <= 0.0 or Shaker.Thickness <= 0.0 then
        return false, "Width, height and thickness must all be greater than zero."
    end
    if Shaker.Quantity < 1 then
        return false, "Quantity must be at least 1."
    end
    if Shaker.Depth <= 0.0 or Shaker.Depth >= Shaker.Thickness then
        return false, "Recess depth must be greater than zero and less than the thickness."
    end
    if Shaker.Edge == "V-Bit" and (Milling.VBitTool.VBit_Angle <= 0.0 or Milling.VBitTool.VBit_Angle >= 180.0) then
        return false, "The V-bit's angle must be between 0 and 180 degrees."
    end
    RecomputeDerived()
    if Shaker.MiddleStile and Shaker.TopMid <= 0.0 then
        return false, "The middle stile must be wider than both its bevels (" .. Fmt(2.0 * Shaker.Bevel) ..
            "), or measure the widths to the top of the bevel."
    end
    if Shaker.TopStile <= 0.0 or Shaker.TopRail <= 0.0 then
        return false, "Rail and stile widths must be greater than the bevel width (" .. Fmt(Shaker.Bevel) ..
            "), or measure them to the top of the bevel."
    end
    if Shaker.FloorW <= 0.0 or Shaker.FloorH <= 0.0 then
        return false, "The rails and stiles leave no panel. Each panel floor would be " .. Fmt(Shaker.FloorW) ..
            " x " .. Fmt(Shaker.FloorH) .. "."
    end
    local floor_min = math.min(Shaker.FloorW, Shaker.FloorH)
    if Milling.BulkTool.ToolDia >= floor_min then
        return false, "The bulk clearing bit (" .. Fmt(Milling.BulkTool.ToolDia) .. ") does not fit the panel floor (" ..
            Fmt(Shaker.FloorW) .. " x " .. Fmt(Shaker.FloorH) .. "). Choose a smaller bulk bit."
    end
    local clearing = ClearingTools()
    for i = 2, #clearing do
        if clearing[i].ToolDia >= clearing[i - 1].ToolDia then
            return false, "Each corner bit must be smaller than the bit before it."
        end
    end
    if Shaker.Edge == "V-Bit" and Milling.VBitTool.ToolDia < (2.0 * Shaker.Bevel) then
        return false, "The V-bit (" .. Fmt(Milling.VBitTool.ToolDia) .. ") is too small to reach the recess depth. " ..
            "It needs a diameter of at least " .. Fmt(2.0 * Shaker.Bevel) .. "."
    end
    if Shaker.CutOut and Milling.ProfileTool.ToolDia >= Milling.PartGap then
        return false, "The profile bit is too large for the part gap."
    end
    return true, nil
end
-- =====================================================]]
function PresentMessage(Header, Type, Line, Height)
    -- Blum Drawer Maker's own alert wrapper (BlumDrawerTools.xlua:1865), with the style block inlined as Box Joint
    -- Runs does: this gadget keeps global state in exactly Shaker and Milling.
    local style = [[<style>
.Error { font-weight: bold; color: #900000; white-space: nowrap; }
.ErrorMessage { font-size: 12px; }
.FormButton { font-weight: bold; width: 75px; font-size: 12px; white-space: nowrap; background-color: #630; color: #FFFFFF; }
</style>]]
    local myHtml = [[<html><head><title>Error</title>]] .. style .. [[</head><body>
  <table><tr><th valign="top" id="MessageType" class="Error">-</th><td id="MessageLine"><label class="ErrorMessage">-</label><td></tr>
<tr><td></td><td align="right"><input id = "ButtonOK" class = "FormButton" name = "ButtonOK" type = "button" value = "OK"></td></tr>
</table></body></html>]]
    local dialog = HTML_Dialog(true, myHtml, 500, Height or 150, Header)
    dialog:AddLabelField("MessageType", Type .. ": ")
    dialog:AddLabelField("MessageLine", Line)
    dialog:ShowDialog()
    return true
end
-- =====================================================]]
function main(script_path)
    Milling.job = VectricJob()
    if not Milling.job.Exists then
        DisplayMessageBox("Error: Shaker Maker cannot run without a job. Create a new file first, " ..
            "specifying the material dimensions.")
        return false
    end
    Shaker.AppPath = string.gsub(script_path, "\\", "/")
    local Tools
    Tools = assert(loadfile(script_path .. "\\ShakerRegistry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\ShakerDialog.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\ShakerGeometry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\ShakerToolpaths.xlua"))(Tools)
    GetMaterialSettings()
    SettingsRead()
    local looping = true
    while looping do
        if not ShowSettingsDialog() then
            return true -- Cancel
        end
        -- Saved before validation, so what was typed survives a rejected setting or a script error.
        SettingsWrite()
        local ok, message = ValidateSettings()
        if ok then
            looping = false
        else
            PresentMessage("Unable to Proceed!", "Error", message)
        end
    end
    RecomputeDerived()
    ApplyLayerNames()
    ActivateThicknessSheet(Shaker.Thickness)
    DrawDoors()
    CreateShakerToolpaths()
    SequenceToolpathsByTool()
    Milling.job:Refresh2DView()
    local summary = "Shaker Maker drew " .. tostring(Shaker.Quantity) .. " part(s), " .. Fmt(Shaker.Width) .. " x " ..
        Fmt(Shaker.Height) .. ", with " .. tostring(#Shaker.PanelFloorY) .. " panel(s), each with a floor of " .. Fmt(Shaker.FloorW) .. " x " .. Fmt(Shaker.FloorH) .. "."
    if Shaker.Edge == "V-Bit" then
        summary = summary .. "\nThe V-bit bevel is " .. Fmt(Shaker.Bevel) .. " wide."
    else
        summary = summary .. "\nPanel corners are left at a radius of " .. Fmt(Shaker.CornerRadius) ..
            ", the radius of the smallest clearing bit."
    end
    DisplayMessageBox(summary .. "\n\nReview the drawing and toolpaths before milling.")
    return true
end
-- =====================================================]]
function OnLuaButton_InquiryHelpMain(dialog)
    -- Called by HTML_Dialog when the Help button is pressed. The page is loaded on demand, as Hold Down Helper
    -- loads its own (Hold_Down_Helper.lua:955), so the help text costs nothing on a normal run.
    local ok, loader = pcall(loadfile, Shaker.AppPath .. "/Help/HelpMain.xlua")
    if not ok or loader == nil then
        DisplayMessageBox("The Shaker Maker help page is missing from:\n" .. Shaker.AppPath .. "/Help\n\n" ..
            "Reinstall the gadget.")
        return true
    end
    loader()
    local help = HTML_Dialog(true, ShakerHelpHtml(), 760, 640, "Shaker Maker Help")
    help:ShowDialog()
    return true
end
-- =============== End of File =========================]]
