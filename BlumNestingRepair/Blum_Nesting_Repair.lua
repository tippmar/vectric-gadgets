-- VECTRIC LUA SCRIPT
--[[
-- Gadgets are an entirely optional add-in to Vectric's core software products.
-- They are provided 'as-is', without any express or implied warranty, and you make use of them entirely at your own risk.
-- In no event will the author(s) or Vectric Ltd. be held liable for any damages arising from their use.
-- ====================================================================================================================================
-- Blum Nesting Repair: run after nesting has moved parts onto other sheets.
-- A toolpath belongs to exactly one sheet, so parts nested onto a new sheet have no toolpaths, and toolpaths whose
-- parts all moved away are left empty. For every toolpath associated with layers ("Associate with toolpath"):
--   * each sheet with vectors on those layers but no such toolpath gets a copy, loaded from a template of the existing
--     toolpath so the user's tools and settings carry over;
--   * each copy on a sheet with no vectors left on those layers is deleted.
-- Then toolpaths are re-sequenced by tool, as Blum Drawer Maker does.
]] -- =====================================================]]
require "strict"
-- =====================================================]]
function IdKey(raw_id) -- String form of a UUID, usable as a table key
    return luaUUID(raw_id):AsString()
end
-- =====================================================]]
function IsClearingPass(name)
    return string.find(name, "[Clear]", 1, true) ~= nil
end
-- =====================================================]]
function BaseToolpathName(name) -- "Back Dado (0.48) [Clear]" -> "Back Dado (0.48)"
    local base = string.gsub(name, "%s*%[Clear%]", "")
    return base
end
-- =====================================================]]
function FindToolpathByKey(toolpath_manager, key)
    local pos = toolpath_manager:GetHeadPosition()
    while pos ~= nil do
        local toolpath
        toolpath, pos = toolpath_manager:GetNext(pos)
        if IdKey(toolpath.Id) == key then
            return toolpath
        end
    end
    return nil
end
-- =====================================================]]
function ToolpathKeys(toolpath_manager) -- Set of all toolpath id keys currently in the job
    local keys = {}
    local pos = toolpath_manager:GetHeadPosition()
    while pos ~= nil do
        local toolpath
        toolpath, pos = toolpath_manager:GetNext(pos)
        keys[IdKey(toolpath.Id)] = true
    end
    return keys
end
-- =====================================================]]
function DeleteToolpathByKey(toolpath_manager, key)
    local toolpath = FindToolpathByKey(toolpath_manager, key)
    if toolpath == nil then
        return false
    end
    toolpath_manager:DeleteToolpath(toolpath)
    return true
end
-- =====================================================]]
function LayerSheets(job) -- layer name -> set of sheet keys holding vectors on that layer
    local layer_sheets = {}
    local layer_manager = job.LayerManager
    local pos = layer_manager:GetHeadPosition()
    while pos ~= nil do
        local layer
        layer, pos = layer_manager:GetNext(pos)
        if not layer.IsSystemLayer then
            local sheets = layer_sheets[layer.Name] or {}
            layer_sheets[layer.Name] = sheets
            local object_pos = layer:GetHeadPosition()
            while object_pos ~= nil do
                local object
                object, object_pos = layer:GetNext(object_pos)
                sheets[IdKey(object.SheetId)] = true
            end
        end
    end
    return layer_sheets
end
-- =====================================================]]
function AssociatedLayerNames(toolpath) -- Layers the toolpath auto-selects from, or an empty list
    local names = {}
    local ok, err = pcall(function()
        local selector = GeometrySelector()
        if not selector:HasSelectorData(toolpath) then
            return
        end
        selector:LoadSelectorData(toolpath)
        if not (selector.GeometryFilterUsed and selector.OnlyOnLayers and selector.HaveLayerNames) then
            return
        end
        local pos = selector:GetLayerNameHeadPosition()
        while pos ~= nil do
            local name
            name, pos = selector:GetNextLayerName(pos)
            table.insert(names, name)
        end
    end)
    if not ok then
        return {}, tostring(err)
    end
    return names, nil
end
-- =====================================================]]
function CollectDefinitions(toolpath_manager, problems)
    -- A definition is every copy of one layer-associated toolpath, keyed by base name. Each copy (one per sheet)
    -- holds the main toolpath and its "[Clear]" partner, which is a separate toolpath with the same base name.
    local definitions = {}
    local order = {}
    local pos = toolpath_manager:GetHeadPosition()
    while pos ~= nil do
        local toolpath
        toolpath, pos = toolpath_manager:GetNext(pos)
        local base = BaseToolpathName(toolpath.Name)
        local definition = definitions[base]
        if definition == nil then
            definition = {name = base, layers = {}, copies = {}}
            definitions[base] = definition
            table.insert(order, definition)
        end
        local sheet = IdKey(toolpath.SheetId)
        local copy = definition.copies[sheet]
        if copy == nil then
            copy = {sheet = sheet, member_keys = {}}
            definition.copies[sheet] = copy
        end
        local key = IdKey(toolpath.Id)
        table.insert(copy.member_keys, key)
        if copy.main_key == nil and not IsClearingPass(toolpath.Name) then
            copy.main_key = key
        end
        local layer_names, err = AssociatedLayerNames(toolpath)
        if err ~= nil then
            table.insert(problems, "Could not read layer association of '" .. toolpath.Name .. "': " .. err)
        end
        for _, layer_name in ipairs(layer_names) do
            definition.layers[layer_name] = true
        end
    end
    return order
end
-- =====================================================]]
function ReorderByTool(toolpath_manager, entries)
    -- Same ordering as Blum Drawer Maker: clearance passes, then other cuts, then profiles, with toolpaths sharing a
    -- tool kept together in the order each tool first appears.
    local tiers = {{order = {}, ids = {}}, {order = {}, ids = {}}, {order = {}, ids = {}}}
    for _, entry in ipairs(entries) do
        local tier = tiers[2]
        if IsClearingPass(entry.name) then
            tier = tiers[1]
        elseif string.find(entry.name, "-Profile", 1, true) then
            tier = tiers[3]
        end
        if tier.ids[entry.tool] == nil then
            tier.ids[entry.tool] = {}
            table.insert(tier.order, entry.tool)
        end
        table.insert(tier.ids[entry.tool], entry.id)
    end
    local ids = UUID_List()
    for _, tier in ipairs(tiers) do
        for _, key in ipairs(tier.order) do
            for _, id in ipairs(tier.ids[key]) do
                ids:AddTail(id)
            end
        end
    end
    local ok, reordered = pcall(function()
        return toolpath_manager:ReorderToolpathList(ids)
    end)
    return ok and reordered
end
-- =====================================================]]
function SequenceToolpathsByTool(problems, sheet_manager, sheet_ids, sheet_names)
    local toolpath_manager = ToolpathManager()
    local entries = {}
    local pos = toolpath_manager:GetHeadPosition()
    while pos ~= nil do
        local toolpath
        toolpath, pos = toolpath_manager:GetNext(pos)
        local tool = toolpath.Tool
        table.insert(entries, {
            id = toolpath.Id,
            name = toolpath.Name,
            sheet = IdKey(toolpath.SheetId),
            tool = tostring(tool.Name) .. "|" .. tostring(tool.ToolNumber) .. "|" .. tostring(tool.ToolDia)
        })
    end
    if ReorderByTool(toolpath_manager, entries) then
        return
    end
    -- A job-wide list spanning several sheets may be rejected; order each sheet's own list instead
    local original_sheet = sheet_manager.ActiveSheetId
    local failed = {}
    for key, id in pairs(sheet_ids) do
        local on_sheet = {}
        for _, entry in ipairs(entries) do
            if entry.sheet == key then
                table.insert(on_sheet, entry)
            end
        end
        if #on_sheet > 0 then
            sheet_manager.ActiveSheetId = id
            if not ReorderByTool(toolpath_manager, on_sheet) then
                table.insert(failed, sheet_names[key] .. " (" .. #on_sheet .. " toolpaths)")
            end
        end
    end
    sheet_manager.ActiveSheetId = original_sheet
    if #failed > 0 then
        table.insert(problems, "Could not reorder toolpaths by tool for the whole job (" .. #entries ..
            " toolpaths) or on: " .. table.concat(failed, ", "))
    end
end
-- =====================================================]]
function HtmlEscape(text)
    local escaped = string.gsub(text, "[&<>\"]", {["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ["\""] = "&quot;"})
    return escaped
end
-- =====================================================]]
function ConfirmPlan(lines, prompt_count) -- Lists the planned changes; true if the user chooses Repair
    local items = {}
    for _, line in ipairs(lines) do
        table.insert(items, "<li>" .. HtmlEscape(line) .. "</li>")
    end
    -- Each toolpath is added by loading a template, and LoadToolpathTemplate always asks whether to apply the
    -- template to every sheet. The API has no form that suppresses it, so the user has to answer each one.
    local warning = ""
    if prompt_count > 0 then
        local times = prompt_count .. " times"
        if prompt_count == 1 then
            times = "once"
        end
        warning = [[<div class="warn"><b>Answer &quot;No&quot; to every prompt.</b> Adding a toolpath asks
<i>&quot;Do you want to apply the template to all sheets?&quot;</i> &mdash; ]] .. times .. [[ in this run.
Answering Yes copies toolpaths onto sheets that should not have them, and can leave the target sheet
without the toolpath it needs.</div>]]
    end
    local html = [[<html><head><style>
body { font-family: Arial, sans-serif; font-size: 12px; background-color: #F0F0F0; }
.plan { height: 230px; overflow: auto; background-color: #FFFFFF; border: 1px solid #999999; padding: 4px; }
.warn { background-color: #FFF4CE; border: 1px solid #D9A400; padding: 6px; margin-top: 8px; }
.buttons { text-align: right; }
</style></head><body>
<p>Nesting moved parts between sheets. Apply these toolpath changes?</p>
<div class="plan"><ul>]] .. table.concat(items) .. [[</ul></div>]] .. warning .. [[
<p class="buttons"><input id="ButtonOK" class="FormButton" type="button" value="Repair">
<input id="ButtonCancel" class="FormButton" type="button" value="Cancel"></p>
</body></html>]]
    local dialog = HTML_Dialog(true, html, 560, 470, "Blum Nesting Repair")
    return dialog:ShowDialog()
end
-- =====================================================]]
function main(script_path)
    local job = VectricJob()
    if not job.Exists then
        DisplayMessageBox("No job loaded")
        return false
    end
    local sheet_manager = job.SheetManager
    local toolpath_manager = ToolpathManager()
    local problems = {}
    local actions = {}

    -- Sheets by key, remembering the active one so it can be restored
    local sheet_ids = {}
    local sheet_names = {}
    for id in sheet_manager:GetSheetIds() do
        local key = IdKey(id)
        sheet_ids[key] = id
        sheet_names[key] = sheet_manager:GetSheetName(id)
    end
    setmetatable(sheet_names, {__index = function(_, key)
        return "sheet " .. tostring(key)
    end})
    local original_sheet = IdKey(sheet_manager.ActiveSheetId)

    local layer_sheets = LayerSheets(job)
    local definitions = CollectDefinitions(toolpath_manager, problems)

    -- Plan: sheets that need a copy, and copies left with nothing to cut
    local creates = {}
    local deletes = {}
    for _, definition in ipairs(definitions) do
        local vector_sheets = {}
        local has_layers = false
        for layer_name in pairs(definition.layers) do
            has_layers = true
            for sheet in pairs(layer_sheets[layer_name] or {}) do
                if sheet_ids[sheet] ~= nil then
                    vector_sheets[sheet] = true
                end
            end
        end
        -- Leave toolpaths alone if they aren't layer-associated, or their layers are empty everywhere
        if has_layers and next(vector_sheets) ~= nil then
            local source = nil
            for sheet, copy in pairs(definition.copies) do
                if copy.main_key ~= nil and (source == nil or vector_sheets[sheet]) then
                    source = copy
                end
            end
            for sheet in pairs(vector_sheets) do
                if definition.copies[sheet] == nil and sheet_ids[sheet] ~= nil and source ~= nil then
                    table.insert(creates, {definition = definition, source = source, sheet = sheet,
                                           source_has_parts = vector_sheets[source.sheet] == true})
                end
            end
            for sheet, copy in pairs(definition.copies) do
                -- Only judge copies on known sheets, so an id mismatch can never delete toolpaths wholesale
                if sheet_ids[sheet] ~= nil and not vector_sheets[sheet] then
                    table.insert(deletes, {definition = definition, copy = copy})
                end
            end
        end
    end

    if #creates == 0 and #deletes == 0 then
        local message = "Every sheet already has toolpaths for its parts. Nothing to repair."
        if #problems > 0 then
            message = message .. "\n\n" .. table.concat(problems, "\n")
        end
        MessageBox(message)
        return true
    end

    local plan = {}
    for _, create in ipairs(creates) do
        table.insert(plan, "Add '" .. create.definition.name .. "' to " .. sheet_names[create.sheet])
    end
    for _, delete in ipairs(deletes) do
        table.insert(plan, "Remove empty '" .. delete.definition.name .. "' from " .. sheet_names[delete.copy.sheet])
    end
    for _, problem in ipairs(problems) do
        table.insert(plan, "Warning: " .. problem)
    end
    if not ConfirmPlan(plan, #creates) then
        return false
    end

    -- Save one template per definition before anything is deleted
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
    local templates = {}
    local template_count = 0
    for _, create in ipairs(creates) do
        local definition = create.definition
        if templates[definition] == nil then
            template_count = template_count + 1
            local path = temp_dir .. "\\BlumNestingRepair_" .. template_count .. ".ToolpathTemplate"
            local toolpath = FindToolpathByKey(toolpath_manager, create.source.main_key)
            local ok, saved = pcall(function()
                return toolpath_manager:SaveToolpathAsTemplate(toolpath, path)
            end)
            if ok and saved then
                templates[definition] = path
            else
                templates[definition] = false
                table.insert(problems, "Could not save a template of '" .. definition.name .. "': " .. tostring(saved))
            end
        end
    end

    -- Remove copies whose sheet no longer has vectors on their layers (they fail to recalculate)
    for _, delete in ipairs(deletes) do
        for _, key in ipairs(delete.copy.member_keys) do
            local ok, deleted = pcall(DeleteToolpathByKey, toolpath_manager, key)
            if not (ok and deleted) then
                table.insert(problems, "Could not delete empty toolpath '" .. delete.definition.name .. "' on " ..
                    sheet_names[delete.copy.sheet] .. ": " .. tostring(deleted))
            end
        end
        table.insert(actions, "Removed empty '" .. delete.definition.name .. "' from " .. sheet_names[delete.copy.sheet])
    end

    -- Load each template onto the sheet that needs it
    for _, create in ipairs(creates) do
        local definition = create.definition
        local path = templates[definition]
        if path then
            sheet_manager.ActiveSheetId = sheet_ids[create.sheet]
            job:Refresh2DView()
            local before = ToolpathKeys(toolpath_manager)
            local ok, loaded = pcall(function()
                return toolpath_manager:LoadToolpathTemplate(path)
            end)
            if not (ok and loaded) then
                table.insert(problems, "Could not load template of '" .. definition.name .. "' onto " ..
                    sheet_names[create.sheet] .. ": " .. tostring(loaded))
            else
                -- Keep only what landed on the target sheet; a template applied to all sheets would duplicate
                -- toolpaths elsewhere
                local recalculate = {}
                local stray = {}
                local stray_names = {}
                local created = 0
                local pos = toolpath_manager:GetHeadPosition()
                while pos ~= nil do
                    local toolpath
                    toolpath, pos = toolpath_manager:GetNext(pos)
                    local key = IdKey(toolpath.Id)
                    if not before[key] then
                        if IdKey(toolpath.SheetId) == create.sheet then
                            created = created + 1
                            if not IsClearingPass(toolpath.Name) then
                                table.insert(recalculate, key)
                            end
                        else
                            table.insert(stray, key)
                            table.insert(stray_names, "'" .. toolpath.Name .. "' on " ..
                                sheet_names[IdKey(toolpath.SheetId)])
                        end
                    end
                end
                for _, key in ipairs(stray) do
                    pcall(DeleteToolpathByKey, toolpath_manager, key)
                end
                -- The "[Clear]" partner can't be recalculated on its own (VCarve error 1035); it follows its main toolpath
                for _, key in ipairs(recalculate) do
                    local toolpath = FindToolpathByKey(toolpath_manager, key)
                    local name = toolpath and toolpath.Name or definition.name
                    local recalc_ok, recalculated = pcall(function()
                        return toolpath_manager:RecalculateToolpath(toolpath)
                    end)
                    if not (recalc_ok and recalculated) then
                        table.insert(problems, "Could not recalculate '" .. name .. "' on " ..
                            sheet_names[create.sheet] .. ": " .. tostring(recalculated))
                    end
                end
                if created == 0 then
                    local source_state = create.source_has_parts and "which still had parts" or "which had no parts left"
                    local found = #stray_names > 0 and table.concat(stray_names, ", ") or "none"
                    table.insert(problems, "Template of '" .. definition.name .. "' created no toolpaths on " ..
                        sheet_names[create.sheet] .. ". It was saved from the copy on " ..
                        sheet_names[create.source.sheet] .. " (" .. #create.source.member_keys .. " toolpath(s), " ..
                        source_state .. "). Toolpaths the load created elsewhere: " .. found)
                else
                    local line = "Added '" .. definition.name .. "' to " .. sheet_names[create.sheet]
                    if #stray > 0 then
                        line = line .. " (removed " .. #stray .. " duplicate(s) from other sheets)"
                    end
                    table.insert(actions, line)
                end
            end
        end
    end

    for _, path in pairs(templates) do
        if path then
            os.remove(path)
        end
    end

    if sheet_ids[original_sheet] ~= nil then
        sheet_manager.ActiveSheetId = sheet_ids[original_sheet]
    end
    SequenceToolpathsByTool(problems, sheet_manager, sheet_ids, sheet_names)
    job:Refresh2DView()

    local message = "Nesting repair complete.\n\n" .. table.concat(actions, "\n")
    if #problems > 0 then
        message = message .. "\n\nProblems:\n" .. table.concat(problems, "\n")
    end
    MessageBox(message)
    return true
end
