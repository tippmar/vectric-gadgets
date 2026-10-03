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
lead_in_out_data = LeadInOutData()
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
    if Run.Mode == "Chain" then
        for i = 1, 4 do
            if Run.Piece[i].Enabled and Run.Piece[i].Length <= (2.0 * Run.StockT) then
                return false, "Piece " .. tostring(i) .. " length must be greater than 2 x thickness."
            end
        end
        if Run.CloseLoop then
            if Run.Piece[1].Length ~= Run.Piece[3].Length or Run.Piece[2].Length ~= Run.Piece[4].Length then
                PresentMessage("Box Joint Runs", "Alert",
                    "Close loop: Piece 1/Piece 3 or Piece 2/Piece 4 lengths do not match. Continuing anyway.")
            end
        end
    end
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
    return true, nil
end
-- =====================================================]]
function PresentMessage(Header, Type, Line, Height)
    -- Blum Drawer Maker's own alert wrapper (BlumDrawerTools.xlua:1865), copied verbatim except that the
    -- style block is inlined here rather than read from a shared DialogWindow global: this gadget keeps
    -- global state in exactly Run and Milling, with no third global table.
    --[[
     Provides user information on an Error
     Caller = local ItWorked = OnLuaButton_InquiryError("No number found")
     Dialog Header = "Something Error"
     User Message = "No Number etc..."
     Returns = True
    ]]
    local style = [[<style>
.Error { font-weight: bold; color: #900000; white-space: nowrap; }
.ErrorMessage { font-size: 12px; }
.FormButton { font-weight: bold; width: 75px; font-size: 12px; white-space: nowrap; background-color: #630; color: #FFFFFF; }
</style>]]
    local myHtml = [[<html><head><title>Error</title>]] .. style .. [[</head><body>
  <table><tr><th valign="top" id="MessageType" class="Error">-</th><td id="MessageLine"><label class="ErrorMessage">-</label><td></tr>
<tr><td></td><td align="right"><input id = "ButtonOK" class = "FormButton" name = "ButtonOK" type = "button" value = "OK"></td></tr>
</table></body></html>]]
    local dialog = HTML_Dialog(true, myHtml, 500, 150, Header)
    if Height then
        dialog = HTML_Dialog(true, myHtml, 500, Height, Header)
    end
    dialog:AddLabelField("MessageType", Type .. ": ")
    dialog:AddLabelField("MessageLine", Line)
    dialog:ShowDialog()
    return true
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
    Tools = assert(loadfile(script_path .. "\\BoxJointGeometry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BoxJointToolpaths.xlua"))(Tools)
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
    RecomputeDerived()
    if Run.Mode == "Test Cut" then
        RunTestCut()
    elseif Run.Mode == "Chain" then
        RunChain()
    elseif Run.Mode == "Existing End" then
        RunExistingEnd()
    elseif Run.Mode == "Existing Back" then
        RunExistingBack()
    end
    if Run.Mode == "Test Cut" or Run.Mode == "Chain" then
        if Milling.job.LayerManager:FindLayerWithName(Milling.LNFingers) ~= nil then
            CreateFingerToolpath(Milling.LNFingers, Milling.TPFingers) -- a chain with no joints and None ends draws no pockets
        end
        CreateGrooveToolpath()
        CreateProfileToolpath(Milling.LNProfile, "OUT", true)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
    elseif Run.Mode == "Existing End" then
        if Milling.job.LayerManager:FindLayerWithName(Milling.LNExistingFingers) ~= nil then
            CreateFingerToolpath(Milling.LNExistingFingers, Milling.TPExistingFingers)
        end
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
    elseif Run.Mode == "Existing Back" then
        if Milling.job.LayerManager:FindLayerWithName(Milling.LNExistingFingers) ~= nil then
            CreateFingerToolpath(Milling.LNExistingFingers, Milling.TPExistingFingers)
        end
        CreateProfilePass(Milling.TPExistingProfile, Milling.LNExistingProfile, "IN", false, 0.0, false)
        SequenceToolpathsByTool()
        Milling.job:Refresh2DView()
    end
    DisplayMessageBox("Box Joint Runs complete. Mode: " .. Run.Mode .. ". Review the drawing before milling.")
    return true
end
-- =============== End of File =========================]]
