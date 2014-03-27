-------------------------------------------------------------------------------
-- myCalApp
-- 
-- Application template
--    
-- Copy this file to your project directory and insert the specific code of 
-- your application
-------------------------------------------------------------------------------
-- Include the src directory
package.path = "/home/src/?.lua;" .. package.path 
-------------------------------------------------------------------------------
local rinApp = require "rinApp"     --  load in the application framework

--=============================================================================
-- Connect to the instruments you want to control
-- Define any Application variables you wish to use 
--=============================================================================
local dwi = rinApp.addK400("K401")     --  make a connection to the instrument
dwi.loadRIS("myCalApp.RIS")               -- load default instrument settings

local mode = 'idle'

--=============================================================================
-- Register All Event Handlers and establish local application variables
--=============================================================================

-------------------------------------------------------------------------------
-- Callback to handle F1 key event 
local function F1Pressed(key, state)
    mode = 'menu'
    return true    -- key handled here so don't send back to instrument for handling
end
dwi.setKeyCallback(dwi.KEY_F1, F1Pressed)
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Callback to handle F2 key event 
dwi.enableOutput(3)
local function F2Pressed(key, state)
    dwi.turnOnTimed(3,5.0)
    return true    -- key handled here so don't send back to instrument for handling
end
dwi.setKeyCallback(dwi.KEY_F2, F2Pressed)
-------------------------------------------------------------------------------



-------------------------------------------------------------------------------
-- Callback to handle PWR+ABORT key and end application
local function pwrCancelPressed(key, state)
    if state == 'long' then
      rinApp.running = false
      return true
    end 
    return false
end
dwi.setKeyCallback(dwi.KEY_PWR_CANCEL, pwrCancelPressed)
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Callback to handle changes in instrument settings
local function settingsChanged(status, active)
end
dwi.setEStatusCallback(dwi.ESTAT_INIT, settingsChanged)
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Callback for local timer
local tickerStart = 0.100    -- time in millisec until timer events start triggering
local tickerRepeat = 0.200  -- time in millisec that the timer repeats
local function ticker()
-- insert code here that you want to run on each timer event
    dwi.rotWAIT(1)
end
rinApp.system.timers.addTimer(tickerRepeat,tickerStart,ticker)
-------------------------------------------------------------------------------



--=============================================================================
-- Initialisation 
--=============================================================================
--  This is a good place to put your initialisation code 
-- (eg, setup outputs or put a message on the LCD etc)
-------------------------------------------------------------------------------
dwi.setIdleCallback(dwi.abortDialog,30)
--=============================================================================
-- Main Application Loop
--=============================================================================
-- Define your application loop
-- mainLoop() gets called by the framework after any event has been processed
-- Main Application logic goes here
local function prompt(msg)
       dwi.writeBotLeft(msg)
       dwi.delay(1.5) 
end

local sel = 'ZERO' 
local function mainLoop()
  
   if mode == 'idle' then
      dwi.writeTopLeft('CAL.APP')
      dwi.writeBotLeft('F1-MENU',1.5)
      dwi.writeBotRight('')
   elseif mode == 'menu' then
      dwi.writeTopLeft()
      dwi.writeBotLeft('')
      sel = dwi.selectOption('MENU',{'ZERO','SPAN','MVV ZERO','MVV SPAN','SET LIN', 'CLR LIN','PASSCODE','EXIT'},sel,true)
      if not sel or sel == 'EXIT' then
         mode = 'idle'
         dwi.lockPasscode('full')
      elseif sel == 'PASSCODE' then
          local pc = dwi.selectOption('ENTER PASSCODE',{'full','safe','oper'},'full',true)
          if pc then
               dwi.changePasscode(pc)
          end          
      elseif dwi.checkPasscode('full',_,5) then
          if sel == 'ZERO' then
              ret, msg = dwi.calibrateZero()
              if ret == 0 then
                  rinApp.dbg.info('Zero MVV: ',dwi.readZeroMVV())
              end    
              prompt(msg)  
              
          elseif sel == 'SPAN' then
              ret, msg = dwi.calibrateSpan(dwi.editReg(dwi.REG_CALIBWGT)) 
              if ret == 0 then
                  rinApp.dbg.info('Span Calibration Weight: ',dwi.readSpanWeight())
                  rinApp.dbg.info('Span MVV: ',dwi.readSpanMVV())
              end
              prompt(msg)
          
          elseif sel == 'MVV SPAN' then
              MVV = dwi.edit('MVV SPAN','2.0','number')
              ret, msg = dwi.calibrateSpanMVV(MVV)   
              prompt(msg)
          
          elseif sel == 'MVV ZERO' then
              MVV = dwi.edit('MVV ZERO','0','number')
              ret, msg = dwi.calibrateZeroMVV(MVV) 
              prompt(msg)
          
          elseif sel == 'SET LIN' then
              pt = dwi.selectOption('LIN PT',{'1','2','3','4','5','6','7','8','9','10'},'1',true)
              if (pt) then
                  ret, msg = dwi.calibrateLin(pt,dwi.editReg(dwi.REG_CALIBWGT))   
                  if ret == 0 then  
                      rinApp.dbg.info('Linearisation Calibration: ',dwi.readLinCal())
                  end
                  prompt(msg)
              end    
          elseif sel == 'CLR LIN' then
              pt = dwi.selectOption('LIN PT',{'1','2','3','4','5','6','7','8','9','10'},'1',true)
              if (pt) then
                 ret, msg = dwi.clearLin(pt)   
                 if ret == 0 then  
                      rinApp.dbg.info('Linearisation Calibration: ',dwi.readLinCal())
                 end
                 prompt(msg)
              end   
          end          
        end
    end 
end

--=============================================================================
-- Clean Up 
--=============================================================================
-- Define anything for the Application to do when it exits
-- cleanup() gets called by framework when the application finishes
local function cleanup()
     
end

--=============================================================================
-- run the application 
rinApp.setMainLoop(mainLoop)
rinApp.setCleanup(cleanup)
rinApp.run()                       
--=============================================================================
