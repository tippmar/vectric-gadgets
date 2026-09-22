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
HoldDownToolId = ToolDBId()
HoldDown.Tool = {Name = "Tool Not Selected"}
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
function ToolRead()
    -- The last V-bit chosen, restored as a plain table carrying the fields CreateDimpleToolpath copies
    local registry = Registry(HoldDown.RegName)
    local name = registry:GetString(SettingsKey("Tool.Name"), "Tool Not Selected")
    if name == "Tool Not Selected" then
        HoldDown.Tool = {Name = name}
        return
    end
    HoldDown.Tool = {
        Name = name,
        InMM = registry:GetBool(SettingsKey("Tool.InMM"), HoldDown.InMM),
        ToolDia = registry:GetDouble(SettingsKey("Tool.ToolDia"), 0.0),
        VBit_Angle = registry:GetDouble(SettingsKey("Tool.VBitAngle"), 90.0),
        Stepdown = registry:GetDouble(SettingsKey("Tool.Stepdown"), 0.0),
        Stepover = registry:GetDouble(SettingsKey("Tool.Stepover"), 0.0),
        RateUnits = registry:GetInt(SettingsKey("Tool.RateUnits"), 4),
        FeedRate = registry:GetDouble(SettingsKey("Tool.FeedRate"), 0.0),
        PlungeRate = registry:GetDouble(SettingsKey("Tool.PlungeRate"), 0.0),
        SpindleSpeed = registry:GetInt(SettingsKey("Tool.SpindleSpeed"), 18000),
        ToolNumber = registry:GetInt(SettingsKey("Tool.ToolNumber"), 1)
    }
end
-- =====================================================]]
function ToolWrite()
    local registry = Registry(HoldDown.RegName)
    local tool = HoldDown.Tool
    registry:SetString(SettingsKey("Tool.Name"), tool.Name)
    if tool.Name == "Tool Not Selected" then
        return
    end
    registry:SetBool(SettingsKey("Tool.InMM"), tool.InMM)
    registry:SetDouble(SettingsKey("Tool.ToolDia"), tool.ToolDia)
    registry:SetDouble(SettingsKey("Tool.VBitAngle"), tool.VBit_Angle) -- the Tool property is VBit_Angle, per the SDK
    registry:SetDouble(SettingsKey("Tool.Stepdown"), tool.Stepdown)
    registry:SetDouble(SettingsKey("Tool.Stepover"), tool.Stepover)
    registry:SetInt(SettingsKey("Tool.RateUnits"), tool.RateUnits)
    registry:SetDouble(SettingsKey("Tool.FeedRate"), tool.FeedRate)
    registry:SetDouble(SettingsKey("Tool.PlungeRate"), tool.PlungeRate)
    registry:SetInt(SettingsKey("Tool.SpindleSpeed"), tool.SpindleSpeed)
    registry:SetInt(SettingsKey("Tool.ToolNumber"), tool.ToolNumber)
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
    ToolRead()
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
    ToolWrite()
end
-- =====================================================]]
function ClearanceRadius()
    -- R = half the cutter + half the screw head + margin. At the imperial defaults this is 0.375".
    return (HoldDown.ToolDiameter * 0.5) + (HoldDown.HeadDiameter * 0.5) + HoldDown.Margin
end
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
-- =====================================================]]
function SheetBounds()
    local mtl_box = MaterialBlock().MaterialBox
    return mtl_box.BLC.x, mtl_box.BLC.y, mtl_box.TRC.x, mtl_box.TRC.y
end
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
-- =====================================================]]
function DrawMarker(layer, x, y)
    -- Polar2D is a Blum Drawer Maker helper, not part of the Vectric API, so the two points are built directly
    local radius = HoldDown.MarkerDiameter * 0.5
    local left = Point2D(x - radius, y)
    local right = Point2D(x + radius, y)
    local circle = Contour(0.0)
    circle:AppendPoint(left)
    circle:ArcTo(right, 1)
    circle:ArcTo(left, 1)
    layer:AddObject(CreateCadContour(circle), true)
end
-- =====================================================]]
function ClearHoldDownLayer()
    -- Re-running must rebuild rather than accumulate. Only this sheet's markers are removed: the layer
    -- spans every sheet, and markers on other sheets belong to runs this one is not responsible for.
    -- Objects are collected first because removing them mid-walk would invalidate the position.
    local layer = HoldDown.job.LayerManager:FindLayerWithName(HoldDown.LayerName)
    if layer == nil then
        return
    end
    local sheet_key = IdKey(HoldDown.job.SheetManager.ActiveSheetId)
    local doomed = {}
    local pos = layer:GetHeadPosition()
    while pos ~= nil do
        local object
        object, pos = layer:GetNext(pos)
        if IdKey(object.SheetId) == sheet_key then
            table.insert(doomed, object)
        end
    end
    for _, object in ipairs(doomed) do
        layer:RemoveObject(object)
    end
end
-- =====================================================]]
function HoldDownLayer()
    local layer = HoldDown.job.LayerManager:GetLayerWithName(HoldDown.LayerName)
    layer:SetColor(255, 0, 255) -- magenta: not a color the Blum gadgets use, so markers stand out
    return layer
end
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
-- =====================================================]]
function ContourPoints(contour)
    -- Flat array of x,y pairs along a polygonized contour: every span's start, then the last span's end,
    -- so an open contour keeps its final segment. Span points are StartPoint2D/EndPoint2D per the Task 2 probe.
    local points = {}
    local last_end = nil
    local pos = contour:GetHeadPosition()
    while pos ~= nil do
        local span
        span, pos = contour:GetNext(pos)
        local start_point = span.StartPoint2D
        table.insert(points, start_point.x)
        table.insert(points, start_point.y)
        last_end = span.EndPoint2D
    end
    if last_end ~= nil then
        table.insert(points, last_end.x)
        table.insert(points, last_end.y)
    end
    return points
end
-- =====================================================]]
function PrepareObstacles(vectors, radius)
    local tolerance = GetDefaultContourTolerance()
    local obstacles = {}
    local failed = {}
    for _, entry in ipairs(vectors) do
        local ok, polygonized = pcall(function()
            return entry.contour:CreatePolygonizedCopy(tolerance, radius)
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
                    layer = entry.layer,
                    min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y
                })
            else
                table.insert(failed, entry.layer)
            end
        else
            table.insert(failed, entry.layer)
        end
    end
    return obstacles, failed
end
-- =====================================================]]
function IsPointSafe(obstacles, x, y, radius)
    -- Returns true, or false plus the obstacle that blocked the point and why, so a rejection can be explained
    for _, obstacle in ipairs(obstacles) do
        -- Skip anything whose bounding box is further than R away without polygon math
        if not (x < obstacle.min_x - radius or x > obstacle.max_x + radius or
                y < obstacle.min_y - radius or y > obstacle.max_y + radius) then
            if obstacle.closed then
                local ok, inside = pcall(function()
                    return obstacle.contour:IsPointInside(Point2D(x, y), GetDefaultContourTolerance())
                end)
                if not ok then
                    return false, obstacle, "inside test failed for" -- a failed inside test is unsafe: never through the middle of a part
                end
                if inside then
                    return false, obstacle, "inside" -- never through a part
                end
            end
            local points = obstacle.points
            for i = 1, #points - 3, 2 do
                if PointSegmentDistance(x, y, points[i], points[i + 1], points[i + 2], points[i + 3]) < radius then
                    return false, obstacle, "too close to" -- inside the band the cutter sweeps, or in too narrow a gap
                end
            end
            if obstacle.closed and #points >= 4 then
                -- Close the loop: the last point back to the first
                local last = #points - 1
                if PointSegmentDistance(x, y, points[last], points[last + 1], points[1], points[2]) < radius then
                    return false, obstacle, "too close to"
                end
            end
        end
    end
    return true
end
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
-- =====================================================]]
function PlaceTargets(obstacles, targets, radius)
    local placed = {}
    local rejected = {}
    for _, target in ipairs(targets) do
        local safe, blocker, reason = IsPointSafe(obstacles, target.x, target.y, radius)
        if safe then
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
                -- Name what blocked the original position, so the user knows which layer to look at
                local why = reason .. " a vector on layer '" .. blocker.layer .. "' spanning " ..
                    string.format("%.2f", blocker.min_x) .. "," .. string.format("%.2f", blocker.min_y) .. " to " ..
                    string.format("%.2f", blocker.max_x) .. "," .. string.format("%.2f", blocker.max_y)
                table.insert(rejected, {x = target.x, y = target.y, kind = target.kind, why = why})
            end
        end
    end
    return placed, rejected
end
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
    tool.VBit_Angle = picked.VBit_Angle -- the Tool property is VBit_Angle, per the SDK
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

    local min_x, min_y, max_x, max_y = SheetBounds()
    local targets = PerimeterTargets(min_x, min_y, max_x, max_y)
    for _, target in ipairs(FieldTargets(min_x, min_y, max_x, max_y)) do
        table.insert(targets, target)
    end

    local radius = ClearanceRadius()
    local obstacles, failed = PrepareObstacles(vectors, radius)
    for _, name in ipairs(failed) do
        table.insert(skipped, "unreadable vector on layer '" .. name .. "'")
    end
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
    DeleteDimpleToolpath()
    local toolpath_made = CreateDimpleToolpath()
    -- The toolpath needed the markers selected; left selected, VCarve draws a direction arrow larger than each marker
    HoldDown.job.Selection:Clear()
    HoldDown.job:Refresh2DView()

    local message = "Hold Down Helper\n\nMarked " .. #placed .. " position(s) on layer '" .. HoldDown.LayerName .. "'," ..
        " each at least " .. string.format("%.4f", radius) .. " " .. HoldDown.UnitLabel .. " (R) from every vector."
    if toolpath_made then
        message = message .. "\nCreated the '" .. HoldDown.ToolpathName .. "' toolpath."
    end
    if #rejected > 0 then
        message = message .. "\n\nCould not place " .. #rejected .. " position(s):"
        for _, position in ipairs(rejected) do
            message = message .. "\n  " .. position.kind .. " at " ..
                string.format("%.3f", position.x) .. ", " .. string.format("%.3f", position.y) ..
                "\n      " .. position.why
        end
    end
    message = message .. SkippedWarning(skipped)
    message = message .. "\n\nLook at the marked positions before you drill. This gadget keeps every fastener " ..
        "clear of every vector, but it cannot tell whether the material under one comes free during the job. " ..
        "A screw in a piece that is cut loose is worse than no screw at all." ..
        "\n\nDO NOT RE-ZERO between running this toolpath and running the job. Zero X and Y, run only " ..
        "'" .. HoldDown.ToolpathName .. "', drive the screws at the dimples, then run the job toolpaths " ..
        "WITHOUT re-zeroing. The dimples are in job coordinates; re-zeroing invalidates every one of them."
    MessageBox(message)
    return true
end
-- =============== End of File =========================]]
