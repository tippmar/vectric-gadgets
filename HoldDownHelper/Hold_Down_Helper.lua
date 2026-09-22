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
