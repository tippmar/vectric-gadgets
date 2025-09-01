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
-- Blum Drawer Maker is based on Easy Drawer Maker, originally written by JimAndi Gadgets of Houston Texas 2019
]] -- =====================================================]]
-- require("mobdebug").start()
require "strict"
-- Global Table Names
Milling = {}
Project = {}
Drawer = {}
Sheet = {}
DialogWindow = {}
Project = {}
Sheets = {}
-- Global Variables
Drawer.WriteSetting = true
Tool_ID1 = ToolDBId()
Tool_ID2 = ToolDBId()
Tool_ID3 = ToolDBId()
Tool_ID4 = ToolDBId()
Tool_ID5 = ToolDBId()
Tool_ID6 = ToolDBId()
lead_in_out_data = LeadInOutData() -- Create object used to control lead in/out
Project.ProgramVersion = 0.1 -- Version Number
Milling.myRecord = 1.0
Drawer.RSide = 1
Drawer.LSide = 1
Drawer.Front = 1
Drawer.Back = 1
Drawer.Bottom = 1
Drawer.Cal = 1.0
DialogWindow.ProgramName = "Blum Drawer Maker"

Drawer.WP = Point2D(1.0 * Drawer.Cal, 1.0 * Drawer.Cal)
SheetThick = 0.0
MillTool1 = {}
MillTool2 = {}
MillTool3 = {}
MillTool4 = {}
MillTool5 = {}
MillTool6 = {}
Project.RegName = "BlumDrawerMaker" .. string.format(Project.ProgramVersion)
-- ====================================================]]
function main(script_path) -- Gadget Start Point, Error and Alert Messages
    local Tools
    Milling.job = VectricJob()
    Project.AppPath = string.gsub(script_path, "\\", "/")
    Milling.Sheet = 1
    if not Milling.job.Exists then
        DisplayMessageBox("Error: The Gadget cannot run without a job being setup.\n" ..
                              "Select: 'Create a new file' under 'Startup Tasks' and \n" ..
                              "specify the material dimensions")
        return false
    end
    Tools = assert(loadfile(script_path .. "\\BlumDrawerImages.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BlumDrawerRegistry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BlumDrawerTools.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BlumDrawerJointry.xlua"))(Tools)
    Tools = assert(loadfile(script_path .. "\\BlumDrawerDialog.xlua"))(Tools)
    Images()
    HTML()
    GetMaterialSettings()
    RegistryRead()
    Drawer_Math()
    local mtl_block = MaterialBlock()
    local mtl_thick = mtl_block.Thickness
    local R1, R2, R3
    local DialogLoop = 1 -- Nope, loop it again
    while DialogLoop == 1 do
        if InquiryDrawer("Blum Drawer Maker " .. Drawer.Units) then
            Drawer_Math()
            RegistryWriter()
            if Project.ProjectPath == "Default" then
                PresentMessage("Unable to Proceed!", "Error",
                    "Cannot find project setup data. \n Rerun program and setup Project.")
                OnLuaButton_InquiryProjectInfo()
                DialogLoop = 1 -- Nope do it again
            elseif Milling.FingerToolDia == 0 then
                PresentMessage("Unable to Proceed!", "Error", "Finger Tool Diameter cannot equal zero.")
                OnLuaButton_InquiryMilling()
                DialogLoop = 1 -- Nope do it again
            elseif Milling.DrawerStyleName == [[Captive Bottom (Dado)]] and Drawer.BottomDadoInset == 0.0 then
                PresentMessage("Unable to Proceed!", "Captive Bottom cannot have Bottom Dado Inset value of zero.")
                OnLuaButton_InquiryMilling()
                DialogLoop = 1 -- Nope do it again
            elseif Milling.ProfileToolDia == 0 then
                PresentMessage("Unable to Proceed!", "Error", "Profile Tool Diameter is too small")
                OnLuaButton_InquiryMilling()
                DialogLoop = 1 -- Nope do it again
            elseif Project.CabinetName == "" then
                PresentMessage("Unable to Proceed!", "Error", "Drawer Name cannot be blank.")
                DialogLoop = 1 -- Nope do it again
            elseif Drawer.OpeningDepth < (10 * Drawer.SideThickness) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Drawer Opening Depth is too small of value. \nEnter a larger Drawer Depth value or enter a smaller Side Thickness")
                DialogLoop = 1 -- Nope do it again
            elseif Drawer.SideFingerCount <= 1 then
                PresentMessage("Unable to Proceed!", "Error", "Finger count cannot be lass then 2 fingers")
                DialogLoop = 1 -- Nope do it again
            elseif not StringChecks() then
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool1.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Profile Milling bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool2.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Dado Milling bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool3.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Dado Clear bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool4.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Finger Milling bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool5.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Finger Clear bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool6.InMM ~= Drawer.Unit) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Blume Operation bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (Drawer.SideWidth / Drawer.SideFingerCount) < (Milling.FingerToolDia / 0.70) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Number of fingers is to high to allow proper milling. \nReduce the Finger Count to ~" ..
                        tostring(math.ceil(Drawer.SideWidth / (Milling.FingerToolDia / 0.70))) .. " fingers.")
                DialogLoop = 1 -- Nope do it again
            elseif (MillTool1 and (MillTool1.Name ~= "Tool Not Selected")) or
                (MillTool2 and (MillTool2.Name ~= "Tool Not Selected")) or
                (MillTool3 and (MillTool3.Name ~= "Tool Not Selected")) or
                (MillTool4 and (MillTool4.Name ~= "Tool Not Selected")) or
                (MillTool5 and (MillTool5.Name ~= "Tool Not Selected")) or
                (MillTool6 and (MillTool6.Name ~= "Tool Not Selected")) then
                DialogLoop = 2 -- Good to Go
                if (MillTool1.ToolDia >= Milling.PartGap) then
                    PresentMessage("Unable to Proceed!", "Error",
                        "Profile Milling Bit is too large for the part gap Width of " .. string.format(Milling.PartGap))
                    DialogLoop = 1 -- Nope do it again
                end -- if end
                if (MillTool2.ToolDia > Drawer.BottomThickness) and
                    (Milling.DrawerStyleName == [[Captive Bottom (Dado)]]) then
                    PresentMessage("Unable to Proceed!", "Error", "Dado Milling Bit is too large for Dado Width of " ..
                        string.format(Drawer.BottomThickness))
                    DialogLoop = 1 -- Nope do it again
                end -- if end
                if (MillTool4.ToolDia > Drawer.SideFingerWidth) then
                    PresentMessage("Unable to Proceed!", "Error", "Finger Bit is too large for finger Width of " ..
                        string.format(Drawer.SideFingerWidth))
                    DialogLoop = 1 -- Nope do it again
                end
                if (MillTool6.ToolDia > Drawer.BlumeDia) then
                    PresentMessage("Unable to Proceed!", "Error",
                        "Bit for Blume Operation is too large Max Dia = " .. string.format(Drawer.BlumeDia))
                    DialogLoop = 1 -- Nope do it again
                end -- if end
            else
                DialogLoop = 2 -- Good to Go
            end
        else
            DialogLoop = 0 -- Pressed Cancel Button
        end -- if end Dialog
    end -- While end
    if DialogLoop == 2 then
        Sheet.ProgressBar = ProgressBar("Drawing Parts", ProgressBar.LINEAR) -- Setup Type of progress bar
        Sheet.ProgressBar:SetPercentProgress(0) -- Sets progress bar to zero
        Project.ProjectPath = string.gsub(Project.ProjectPath, "\\", "/")
        R1, R2, R3 = os.rename(Project.ProjectPath, Project.ProjectPath)
        -- How many sheets do we need
        Sheets = {Drawer.BackThickness, Drawer.BottomThickness, Drawer.SideThickness, Drawer.FrontThickness}
        Sheets = RemoveDuplicates(Sheets)
        if MillTool4.Name ~= "Tool Not Selected" then
            Milling.FingerToolDia = MillTool4.ToolDia
        end -- if end
        Milling.FingerToolRad = Milling.FingerToolDia * 0.5
        if not (R1) then
            if R3 == 13 then
                PresentMessage("Alert", "Toolpath Processing", R2 .. "\nYou may have a file open in the Directory")
            else
                PresentMessage("Error", "Toolpath Processing", R2)
                return false
            end
        end -- if not R1
        ToolCheck() -- checks if tooling was selected
        Drawer.Record = (61.0 * Drawer.Count) -- How much to push the progress bar per Push() step
        Push()
        CutBySheets()
        Push()
        Drawer_Math()
        Push()
        MakeLayers()
        Push()
        if GetAppVersion() < 10.999 then
            StampIt(mtl_thick) -- Job Setup thickness
        end -- if end
        CutListfileWriterHeader()
        Drawer.WP = Point2D(1.0 * Drawer.Cal, 1.0 * Drawer.Cal)
        -- Draw parts by thickness
        for i = 1, #Sheets do
            SheetThick = Sheets[i]
            DrawWriter("Material Thickness " .. tostring(SheetThick) .. " Thk.",
                Polar2D(Point2D(0, 0), 270.0, 3.5 * Drawer.Cal), 1.5 * Drawer.Cal, Milling.LNDrawNotes, 0.0)
            -- Reordered so back (and its Blume pockets) are processed before sides or front
            if SheetThick == Drawer.BackThickness then
                ProcessBack()
            end
            if SheetThick == Drawer.SideThickness then
                ProcessSide()
            end
            if SheetThick == Drawer.FrontThickness then
                ProcessFront()
            end
            if SheetThick == Drawer.BottomThickness then
                ProcessBottom()
            end
            if Sheets[i + 1] then
                NextSheet()
                Drawer.WP = Point2D(1.0 * Drawer.Cal, 1.0 * Drawer.Cal)
            end
        end
        CutListfileWriterFooter()
        Sheet.ProgressBar:SetText("Complete") -- Sets the label to Complete
        Sheet.ProgressBar:Finished() -- Close Progress Bar
        LayerClear()
        Milling.job:Refresh2DView()
        if Drawer.BottomThickness == Drawer.BackThickness and Drawer.SideThickness == Drawer.FrontThickness and
            Drawer.BackThickness == Drawer.FrontThickness then
            PresentMessage("Success", "Congratulations",
                [[Blum Drawer Maker Gadget has completed. It is recommended you validate the drawing and milling toolpaths before milling parts.]])
        else
            PresentMessage("Sheet Configuration", "Alert",
                [[Blum Drawer Maker Gadget has completed. At this time, the gadget cannot create sheets with differing material (Z) thickness. All sheets have been replicated from the initial sheet having the same thickness (Z) value. The user will need to manually adjust each sheet (Z) thickness in the 'Sheet Tab Menu', to match the part thickness before milling parts.]],
                220)
        end -- if end
    end -- if end
    return true
end -- Function End
-- =============== End of File =========================]]
