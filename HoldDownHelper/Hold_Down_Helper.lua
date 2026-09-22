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
-- Resolved against VCarve Pro V12.5 by the Task 2 probe on 2026-09-22. The SDK PDF does not document
-- all of these; these are the signatures the running application actually accepts.
--   GetDefaultContourTolerance()          -> number (4e-05 in an imperial job)
--   Contour:CreatePolygonizedCopy(tolerance, max_line_len) -> Contour; both arguments required
--   Contour:IsPointInside(Point2D, tolerance) -> bool; undefined for open contours
--   Contour bounding box                  -> contour.BoundingBox2D (.MinX .MinY .MaxX .MaxY)
--   Contour point iteration               -> contour:GetHeadPosition() / contour:GetNext(pos) -> span, pos;
--                                            span.StartPoint2D / span.EndPoint2D (span.StartPoint is nil)
--   Contour open/closed                   -> contour.IsOpen, contour.IsClosed
--   Layer visibility                      -> layer.Visible (layer.IsVisible is nil)
--   Clearing a layer                      -> no layer:Clear(); layer:RemoveObject(CadObject) removes one object
--   Grouped objects                       -> GetContour() is nil; ClassName "vcCadObjectGroup",
--                                            CastCadObjectToCadObjectGroup(obj), then GetHeadPosition/GetNext
--   DrillParameterData()                  -> object; toolpath_manager.CreateDrillingToolpath is a function

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
    -- layer.Visible, per the Task 2 probe. Failing to read it means "visible", so an unknown
    -- layer still blocks fasteners instead of being ignored.
    local ok, visible = pcall(function()
        return layer.Visible
    end)
    if ok and visible ~= nil then
        return visible
    end
    return true
end
-- =====================================================]]
function CollectObject(object, layer_name, vectors, skipped)
    -- A group has no contour of its own, so its members are collected instead. Anything else without
    -- a contour (text, bitmaps) is recorded as skipped by class, never silently dropped.
    local contour = object:GetContour()
    if contour ~= nil then
        table.insert(vectors, {contour = contour, layer = layer_name})
    elseif object.ClassName == "vcCadObjectGroup" then
        local group = CastCadObjectToCadObjectGroup(object)
        local pos = group:GetHeadPosition()
        while pos ~= nil do
            local member
            member, pos = group:GetNext(pos)
            CollectObject(member, layer_name, vectors, skipped)
        end
    else
        table.insert(skipped, object.ClassName .. " on layer '" .. layer_name .. "'")
    end
end
-- =====================================================]]
function SkippedWarning(skipped)
    -- One line per distinct kind of skipped object, or "" when nothing was skipped
    if #skipped == 0 then
        return ""
    end
    local counts = {}
    local order = {}
    for _, entry in ipairs(skipped) do
        if counts[entry] == nil then
            counts[entry] = 0
            table.insert(order, entry)
        end
        counts[entry] = counts[entry] + 1
    end
    local text = "\n\nWARNING: " .. #skipped .. " object(s) have no outline to keep clear of and were ignored:"
    for _, entry in ipairs(order) do
        text = text .. "\n  " .. counts[entry] .. " x " .. entry
    end
    return text .. "\nHide those layers if that is intended, or convert the objects to vectors."
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
                    CollectObject(object, layer.Name, vectors, skipped)
                end
            end
        end
    end
    return vectors, skipped
end
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
-- =====================================================]]
function ClearanceRadius()
    -- R = half the cutter + half the screw head + margin. At the imperial defaults this is 0.375".
    return (HoldDown.ToolDiameter * 0.5) + (HoldDown.HeadDiameter * 0.5) + HoldDown.Margin
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
    SettingsRead()

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
    message = message .. "\nClearance radius R: " .. string.format("%.4f", ClearanceRadius())
    message = message .. SkippedWarning(skipped)
    SettingsWrite()
    MessageBox(message)
    return true
end
-- =============== End of File =========================]]
