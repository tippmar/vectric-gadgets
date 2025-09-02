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
-- optional remote debug
do
    local ok_env = os.getenv("DRAWER_DEBUG") == "1"
    if ok_env then
        local ok, md = pcall(require, "mobdebug")
        if ok then
            md.start()
        end
    end
end
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
Project.ProgramVersion = 0.2 -- Version Number
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
    Tools = assert(loadfile(script_path .. "\\BlumDrawerJoinery.xlua"))(Tools)
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
            elseif Drawer.SlideLength < (10 * Drawer.PanelThickness) then
                PresentMessage("Unable to Proceed!", "Error",
                    "Drawer Slide Length is too small of value. \nEnter a larger Slide Length value or enter a smaller Panel Thickness")
                DialogLoop = 1 -- Nope do it again
            elseif (Drawer.SideFingerCount <= 1) then
                PresentMessage("Unable to Proceed!", "Error", "Finger count cannot be lass then 2 fingers")
                DialogLoop = 1 -- Nope do it again
            elseif not StringChecks() then
                DialogLoop = 1 -- Nope do it again
            elseif Drawer.SideWidth <= 0 then
                local needed = 0
                if Drawer.Unit then
                    needed = 21.0
                else
                    needed = 13.0 / 16.0
                end
                PresentMessage("Unable to Proceed!", "Error",
                    "Opening Height minus required clearance (" .. string.format("%.4f", needed) ..
                        ") is not positive.\nIncrease the Opening Height.")
                DialogLoop = 1
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
                    "Blum Operation bit units do not match the drawing units. Select a bit in the drawing units")
                DialogLoop = 1 -- Nope do it again
            elseif (Drawer.SideWidth / Drawer.SideFingerCount) < (Milling.FingerToolDia / 0.70) then
                local effectiveWidth = math.max(0, Drawer.SideWidth)
                local minFinger = math.ceil(effectiveWidth / (Milling.FingerToolDia / 0.70))
                if minFinger < 2 then
                    minFinger = 2
                end
                PresentMessage("Unable to Proceed!", "Error",
                    "Number of fingers is too high to allow proper milling.\nReduce the Finger Count to " ..
                        tostring(minFinger) .. " or less, or increase the drawer opening height.")
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
                if (MillTool6.ToolDia > Drawer.BlumDia) then
                    PresentMessage("Unable to Proceed!", "Error",
                        "Bit for Blum Operation is too large Max Dia = " .. string.format(Drawer.BlumDia))
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
        R1, R2, R3 = os.rename(Project.ProjectPath, Project.ProjectPath)
        -- How many sheets do we need
        Sheets = {Drawer.PanelThickness, Drawer.BottomThickness}
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
            if SheetThick == Drawer.PanelThickness then
                ProcessBack();
                ProcessSide();
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
        PresentMessage("Success", "Congratulations",
            [[Blum Drawer Maker Gadget has completed. It is recommended you validate the drawing and milling toolpaths before milling parts.]])
    end -- if end
    return true
end -- Function End
-- =============== End of File =========================]]
