-------------------------------------------------------------------------------
--- USB Functions.
-- Functions to detect and mount USB devices.
-- @module rinLibrary.rinUSB
-- @author Pauli
-- @copyright 2014 Rinstrum Pty Ltd
-------------------------------------------------------------------------------

local _M = {}

local socks = require "rinSystem.rinSockets"
local dbg = require "rinLibrary.rinDebug"
local rs232 = require "luars232"
local utils = require 'rinSystem.utilities'
local timers = require 'rinSystem.rinTimers'
local posix = require 'posix'
local unistd = require "posix.unistd"
local deepcopy = utils.deepcopy
local naming = require 'rinLibrary.namings'
local canonical = naming.canonicalisation
local dirent = require "posix.dirent"
local re = require "re"

local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local tostring = tostring
local table = table
local next = next
local os = os

local usb, ev_lib, decodeKey, usbKeyboardMap, partition
if pcall(function() usb = require "devicemounter" end) then
    ev_lib = require "ev_lib"
    decodeKey = require "kb_lib"
    usbKeyboardMap = require 'kb_mapping'
    local status, module = pcall(require, "dm.partition")
    partition = status and module or nil
elseif not _TEST then
    dbg.warn('rinUSB:', 'USB not supported')
end

local userUSBRegisterCallback = nil
local userUSBEventCallback = nil
local userUSBKBDCallback = nil
local lineUSBKBDCallback = nil
local libUSBKBDCallback = nil
local libUSBSerialCallback = nil
local userUSBPrinterAddedCallback, userUSBPrinterRemovedCallback = nil, nil
local eventDevices = {}

local userStorageRemovedCallback, userStorageAddedCallback = nil, nil
local storageEvent = nil

local legalKeys = nil

local function doRS232(n)
    local r, l = {}, n:len()
    for k, v in pairs(rs232) do
        if k:sub(1, l) == n then
            r[canonical(k:sub(l+1))] = v
        end
    end
    return r
end

local baudRates = doRS232 'RS232_BAUD_'         -- 300 ... 460800 with gaps
local dataBits = doRS232 'RS232_DATA_'          -- '5', '6', '7', '8'
local parityOptions = doRS232 'RS232_PARITY_'   -- none, odd, even
local stopBitsOptions = doRS232 'RS232_STOP_'   -- '1', '2'
local flowControl = doRS232 'RS232_FLOW_'       -- off, hw, xon_xoff

-- RS232 error table in human readable form
local rs232ErrorTable = setmetatable({
    [rs232.RS232_ERR_UNKNOWN]       = 'unknown error',
    [rs232.RS232_ERR_OPEN]          = 'open failed',
    [rs232.RS232_ERR_CLOSE]         = 'close failed',
    [rs232.RS232_ERR_FLUSH]         = 'flush failed',
    [rs232.RS232_ERR_CONFIG]        = 'configuration error',
    [rs232.RS232_ERR_READ]          = 'read failed',
    [rs232.RS232_ERR_WRITE]         = 'write failed',
    [rs232.RS232_ERR_SELECT]        = 'select failed',
    [rs232.RS232_ERR_TIMEOUT]       = 'timeout',
    [rs232.RS232_ERR_IOCTL]         = 'ioctl failed',
    [rs232.RS232_ERR_PORT_CLOSED]   = 'port closed'
}, {
    __index = function(t, f)
        if f == rs232.RS232_ERR_NOERROR then return nil end
        return 'error "'..tostring(f)..'"'
    end
})

-------------------------------------------------------------------------------
-- Called to register a callback to run whenever a USB device change is detected
-- @func callback Callback function takes event table as a parameter
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- function registerCB(t)
--     for _, v in pairs(t) do
--         print('register:', v[1])
--         print('    what:', v[2])   -- 'added' or 'removed'
--         print('    whom:', v[3])
--     end
-- end
-- usb.setUSBRegisterCallback(registerCB)
function _M.setUSBRegisterCallback(callback)
    utils.checkCallback(callback)
    local r = userUSBRegisterCallback
    userUSBRegisterCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever a USB device change is detected
-- @treturn func current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getUSBRegisterCallback() == nil then
--     print('No USB register callback installed')
-- end
function _M.getUSBRegisterCallback()
    return userUSBRegisterCallback
end

-------------------------------------------------------------------------------
-- Called to register a callback to run whenever a USB device event is detected
-- @func callback Callback function takes event table as a parameter
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
-- local input = linux_input or require("linux.input")
--
-- function eventCB(ev)
--     if ev.type == input.EV_SYN and ev.code == input.SYN_CONFIG then
--         print "Event: -------------- Config Sync ------------ "
--     elseif ev.type == input.EV_SYN and ev.code == input.SYN_REPORT then
--         print "Event: -------------- Report Sync ------------ "
--     elseif ev.type == input.EV_MSC and (ev.code == input.MSC_RAW or ev.code == input.MSC_SCAN) then
--         print(string.format("Event: type %d (%s), code %d (%s), value %02x",
--                 ev.type, ev_lib.events[ev.type],
--                 ev.code, ev_lib.names[ev.type][ev.code],
--                 ev.value))
--     else
--         print(string.format("Event: type %d (%s), code %d (%s), value %d",
--                 ev.type, ev_lib.events[ev.type],
--                 ev.code, ev_lib.names[ev.type][ev.code],
--                 ev.value))
--     end
-- end
-- usb.setUSBEventCallback(eventCB)
function _M.setUSBEventCallback(callback)
    utils.checkCallback(callback)
    local r = userUSBEventCallback
    userUSBEventCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever a USB device event is detected
-- @treturn func Current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getUSBEventCallback() == nil then
--     print('No USB user event callback installed')
-- end
function _M.getUSBEventCallback()
    return userUSBEventCallback
end

-------------------------------------------------------------------------------
-- Called to register a callback to run whenever a USB Keyboard event is
-- processed
-- @func callback Callback function takes key string as a parameter
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setUSBKBDCallback(function(key) print(key, 'pressed') end)
function _M.setUSBKBDCallback(callback)
    utils.checkCallback(callback)
    local r = userUSBKBDCallback
    userUSBKBDCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a USB Keyboard
-- event is processed
-- @treturn func current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getUSBKBDCallback() == nil then
--     print('No USB keyboard call back installed')
-- end
function _M.getUSBKBDCallback()
    return userUSBKBDCallback
end

-------------------------------------------------------------------------------
-- Called to register a callback to run whenever a USB Keyboard has input a full
-- line of text
-- @func callback Callback function takes line string as a parameter
-- @string endchar Ending character for a line (default \n)
-- @treturn func The previous callback
-- @treturn string The previous end of line character
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setUSBKBDLineCallback(function(line) print('data: ' .. line) end)
function _M.setUSBKBDLineCallback(callback, endchar)
    utils.checkCallback(callback)

    local cb, ec = deepcopy(callback), endchar or '\n'
    local r1, r2 = _M.getUSBKBDLineCallback()
    _M.getUSBKBDLineCallback = function() return cb, ec end

    if cb == nil then
        lineUSBKBDCallback = nil
    else
        local line = {}
        lineUSBKBDCallback = function(k)
            if k == ec then
                utils.call(cb, table.concat(line))
                line = {}
            else
                table.insert(line, k)
            end
        end
    end
    return r1, r2
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a USB Keyboard
-- has finished inputting a line.
-- @treturn func The current callback
-- @treturn string The current end of line character
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getUSBKBDLineCallback() == nil then
--     print('No USB keyboard line call back installed')
-- end
function _M.getUSBKBDLineCallback()
    return nil, '\n'
end

-------------------------------------------------------------------------------
-- Register a callback to run whenever a USB storage device is inserted
-- @func callback Callback function takes the mount point as a string
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setStorageAddedCallback(function(mnt) print('new USB storage '..mnt) end)
function _M.setStorageAddedCallback(callback)
    utils.checkCallback(callback)
    local r = userStorageAddedCallback
    userStorageAddedCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a new USB storage
-- device is detected
-- @treturn func Current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getStorageAddedCallback() == nil then
--     print('No storage added callback installed')
-- end
function _M.getStorageAddedCallback()
    return userStorageAddedCallback
end

-------------------------------------------------------------------------------
-- Register a callback to run whenever a USB storage device is removed
-- @func callback Callback function takes the mount point as a string
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setStorageRemovedCallback(function() print('USB storage has gone') end)
function _M.setStorageRemovedCallback(callback)
    utils.checkCallback(callback)
    local r = userStorageRemovedCallback
    userStorageRemovedCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a new USB storage
-- device is removed
-- @treturn func current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getStorageRemovedCallback() == nil then
--     print('No storage removed callback installed')
-- end
function _M.getStorageRemovedCallback()
    return userStorageRemovedCallback
end

-------------------------------------------------------------------------------
-- Add the raw key stroke call back.
-- @treturn func callback The library call back
-- @local
function _M.setLibKBDCallback(callback)
    utils.checkCallback(callback)
    if decodeKey then
        libUSBKBDCallback = callback
    end
end

-------------------------------------------------------------------------------
-- Return an iterator that gives canonical names for all USB defined keyboard
-- keys.
-- @return Iterator
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- for k in usb.usbKeyboardKeyIterator() do
--     print('key: ', k)
-- end
function _M.usbKeyboardKeyIterator()
    if usbKeyboardMap == nil then return utils.null end

    local k = nil
    return function()
        local v
        k, v = next(usbKeyboardMap, k)
        return v ~= nil and canonical(v[1]) or nil
    end
end

-------------------------------------------------------------------------------
-- Return a table of legal keys
-- @treturn tab Table of all known USB keys
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- dbg.info('legal USB keys:', usb.usbKeyboardGetKeys())
function _M.getKeyboardKeys()
    if legalKeys == nil then
        legalKeys = {}
        for k in _M.usbKeyboardKeyIterator() do
            legalKeys[k] = k
        end
    end
    return legalKeys
end

-------------------------------------------------------------------------------
-- Callback to detect events happening for USB devices and to further dispatch
-- them as required.
-- @param sock File descriptor the USB device is communicating with.
-- @local
local function eventCallback(sock)
    local ev = ev_lib and ev_lib.getEvent(sock)
    if ev then
        utils.call(userUSBEventCallback, ev)

        if decodeKey then
            local key = decodeKey(ev)
            if key then
                utils.call(libUSBKBDCallback, key)

                if key.type == 'down' and not key.modifier then
                    local k = key.key
                    if key.alt then
                        k = 'ALT-' .. k
                    end
                    utils.call(userUSBKBDCallback, k)

                    if lineUSBKBDCallback and not key.alt then
                        lineUSBKBDCallback(key.key)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Register a callback to run whenever a USB printer device is inserted
-- @func callback Callback function takes the printer as a file
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setPrinterAddedCallback(function(printer) 
--      print('new USB printer '..printer) 
--      printer:write("test!\r\n")
--    end)
function _M.setPrinterAddedCallback(callback)
    utils.checkCallback(callback)
    local r = userUSBPrinterAddedCallback
    userUSBPrinterAddedCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a new USB printer
-- device is detected
-- @treturn func Current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getPrinterAddedCallback() == nil then
--     print('No printer added callback installed')
-- end
function _M.getPrinterAddedCallback()
    return userUSBPrinterAddedCallback
end

-------------------------------------------------------------------------------
-- Register a callback to run whenever a USB printer device is removed
-- @treturn func The previous callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- usb.setPrinterRemovedCallback(function() print('USB printer has gone') end)
function _M.setPrinterRemovedCallback(callback)
    utils.checkCallback(callback)
    local r = userUSBPrinterRemovedCallback
    userUSBPrinterRemovedCallback = callback
    return r
end

-------------------------------------------------------------------------------
-- Called to get current callback that runs whenever whenever a new USB printer
-- device is removed
-- @treturn func Current callback
-- @usage
-- local usb = require 'rinLibrary.rinUSB'
--
-- if usb.getPrinterRemovedCallback() == nil then
--     print('No printer removed callback installed')
-- end
function _M.getPrinterRemovedCallback()
    return userUSBPrinterRemovedCallback
end


-------------------------------------------------------------------------------
-- Callback to receive meta-events associated with USB device appearance
-- and disappearance.
-- This must be called from genericStatus.
-- @tab t Event table
-- @local
function _M.usbCallback(t)
    dbg.debug('', t)
    for k,v in pairs(t) do
        if v[1] == 'event' then
            if v[2] == 'added' and ev_lib then
                eventDevices[k] = ev_lib.openEvent(k)
                socks.addSocket(eventDevices[k], eventCallback)
            elseif v[2] == 'removed' and eventDevices[k] ~= nil then
                socks.removeSocket(eventDevices[k])
                eventDevices[k] = nil
            end
        elseif v[1] == 'partition' then
            if v[2] == 'added' then
                utils.call(userStorageAddedCallback, v[3])
            elseif v[2] == 'removed' then
                utils.call(userStorageRemovedCallback)
            end
        elseif v[1] == 'printer' then
          if v[2] == 'added' then
                utils.call(userUSBPrinterAddedCallback, v[3])
            elseif v[2] == 'removed' then
                utils.call(userUSBPrinterRemovedCallback)
            end
        end
    end

    utils.call(libUSBSerialCallback, t)
    utils.call(userUSBRegisterCallback, t)
end

-------------------------------------------------------------------------------
-- Setup a serial handler
-- @func callback Callback function that accepts data byte at a time
-- @int[opt] baud Baud rate to use (default 9600)
-- @int[opt] data Number of data bits per byte (default 8)
-- @string[opt] parity Type of parity bit used (default 'none')
-- @int[opt] stopbits Number of stop bits used (default 1)
-- @string[opt] flow Flavour of flow control used (default 'off')
-- @usage
-- -- Refer to the myUSBApp example provided.
--
-- local usb = require 'rinLibrary.rinUSB'
--
-- -- The call back takes three arguments:
-- --     c The character just read from the serial device
-- --     err The error indication if c is nil
-- --     port The incoming serial port
-- -- The call back is called on open, close and when a character is read.  For the
-- -- open and close calls, the character argument is nil and the error argument is
-- -- either "open" or "close".  The call back is not invoked when writing to the
-- -- serial deivce.
-- local function usbSerialHandler(c, err, port)
--     print("USB serial", c, err)
-- end
-- usb.serialUSBdeviceHandler(usbSerialHandler)
function _M.serialUSBdeviceHandler(callback, baud, data, parity, stopbits, flow)
    local b = naming.convertNameToValue(tostring(baud), baudRates, rs232.RS232_BAUD_9600)
    local d = naming.convertNameToValue(tostring(data), dataBits, rs232.RS232_DATA_8)
    local p = naming.convertNameToValue(parity, parityOptions, rs232.RS232_PARITY_NONE)
    local s = naming.convertNameToValue(tostring(stopbits), stopBitsOptions, rs232.RS232_STOP_1)
    local f = naming.convertNameToValue(flow, flowControl, rs232.RS232_FLOW_OFF)

    if callback == nil then
        libUSBSerialCallback = nil
    else
        utils.checkCallback(callback)
        libUSBSerialCallback = function (t)
            for k, v in pairs(t) do
                if v[1] == "serial" then
                    if v[2] == "added" then
                        local port = v[3]
                        local noerr = rs232.RS232_ERR_NOERROR

                        assert(port:set_baud_rate(b) == noerr)
	                    assert(port:set_data_bits(d) == noerr)
		                assert(port:set_parity(p) == noerr)
		                assert(port:set_stop_bits(s) == noerr)
		                assert(port:set_flow_control(f) == noerr)

                        socks.addSocket(port, function ()
                                                  local e, c, s = port:read(10000, 0)
                                                  if s == 0 then
                                                      socks.removeSocket(port)
                                                      callback(nil, "close", port)
                                                  else
                                                      callback(c, rs232ErrorTable[e], port)
                                                  end
                                              end)
                        callback(nil, "open", port)
                    elseif v[2] == 'removed' then
                        local port = v[3]
                        if port then
                            socks.removeSocket(port)
                            callback(nil, "close", port)
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Called to initialise the USB port if in use
-- This routing is called automatically by the rinApp framework.
-- @usage
-- local usb = require 'rinUSB'
-- usb.initUSB()
function _M.initUSB()
    if usb then
        socks.addSocket(usb.init(), usb.receiveCallback)
        usb.registerCallback(_M.usbCallback)
        usb.checkDev()  -- call to check if any usb devices already mounted
    end
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
--- USB Storage Helper Functions
--
-- A selection of functions to make accessing USB storage devices a little
-- easier.
-- @section Storage Helpers

-------------------------------------------------------------------------------
-- Schedule a file commit but don't run it until event processing occurs.
--
-- This allows this function to be called liberally without incurring undue
-- overhead.
-- @usage
-- usb.commitFileChanges()
function _M.commitFileChanges()
    if storageEvent == nil then
        storageEvent = timers.addEvent(function()
            storageEvent = nil
            utils.sync(false)
        end)
    end
end

-------------------------------------------------------------------------------
-- Check is a file exists are the specified path
-- @string path Path to the file to be tested
-- @treturn bool True if the file exists
-- @usage
-- if usb.fileExists('hello.lua') then
-- end
function _M.fileExists(path)
    return posix.stat(path, 'type') == 'regular'
end

-------------------------------------------------------------------------------
-- Check is a directory exists are the specified path
-- @string path Path to the directory to be tested
-- @treturn bool True if the directory exists
-- @usage
-- if usb.directoryExists('/tmp') then
-- end
function _M.directoryExists(path)
    return posix.stat(path, 'type') == 'directory'
end

-------------------------------------------------------------------------------
-- Make a directory, if one doesn't already exist in that location.
-- @string path Path to the directory
-- @treturn int Result code, 0 being no error
-- @usage
-- usb.makeDirectory(usbMountPoint .. '/logFile/myLogs')
function _M.makeDirectory(path)
    _M.commitFileChanges()
    return os.execute('mkdir -p "'..path..'"')
end

-------------------------------------------------------------------------------
-- Local function for running a function in a fork and waiting for it to end.
-- This allows the connection with the indicator to be kept alive if 
-- the rinApp.delay function is passed in.
local function runInFork(timeout, delayFunc, execPath, execArgs)
  
  local cpid = unistd.vfork_spawn(execPath, execArgs)
  
  -- Try for 10 seconds.
  for i = 0, timeout do
    local pid, strRet, exitStatus = posix.wait(cpid, posix.WNOHANG)
    -- If we successfully waited, return 0.
    if pid > 0 then
      return exitStatus
    end
    delayFunc(1)
  end
  
  -- Otherwise return 1.
  return 1
end

-------------------------------------------------------------------------------
-- Copy all files in the specified directory to the destination
-- @string src Source diretory or mount point
-- @string dest Destination directory or mount point
-- @treturn int Result code, 0 being no error
-- @int[opt] timeout Time in seconds to try to copy. Default is 10.
-- @func[opt] delayFunc Function to call to delay. Default is posix.sleep, but a 
-- better option would be rinApp.delay
-- @usage
-- usb.copyDirectory('log', usbPath)
function _M.copyDirectory(src, dest, timeout, delayFunc)
    timeout = timeout or 10
    delayFunc = delayFunc or posix.sleep

    _M.makeDirectory(dest)
    return runInFork(timeout, delayFunc, "/bin/sh", 
        {[0] = "sh", "-c", 'cp -a "'..src..'"/* "'..dest..'"/'})
end

-------------------------------------------------------------------------------
-- Copy all files containing name from the source to the destination
-- @string src Source file
-- @string dest Destination file
-- @int[opt] timeout Time in seconds to try to copy. Default is 10.
-- @func[opt] delayFunc Function to call to delay. Default is posix.sleep, but a 
-- better option would be rinApp.delay
-- @treturn int Result code, 0 being no error
-- @usage
-- usb.copyFile(localPath .. '/log.csv', usbPath .. '/log.csv')
function _M.copyFile(src, dest, timeout, delayFunc)
    timeout = timeout or 10
    delayFunc = delayFunc or posix.sleep

    _M.commitFileChanges()
    return runInFork(timeout, delayFunc, "/bin/cp", 
        {[0] = "cp", "-dp", src, dest})
end

-------------------------------------------------------------------------------
-- Copy all files containing name from the source to the destination
-- @string src Source diretory or mount point
-- @string dest Destination directory or mount point
-- @string name Fragment in file name to check for
-- @int[opt] timeout Time in seconds to try to copy. Default is 10.
-- @func[opt] delayFunc Function to call to delay. Default is posix.sleep, but a 
-- better option would be rinApp.delay
-- @treturn int Result code, 0 being no error
-- @usage
-- usb.copyFiles(localPath, usbPath, '.txt')
function _M.copyFiles(src, dest, name, timeout, delayFunc)
    local i
    timeout = timeout or 10
    delayFunc = delayFunc or posix.sleep

    if name == nil then
        return _M.copyDirectory(src, dest)
    end
    _M.makeDirectory(dest)

    return runInFork(timeout, delayFunc, "/bin/sh", 
              {[0] = "sh", "-c", 'cp -dp "'..src..'"/*"'..name..'"* "'..dest..'"/'})
end

-------------------------------------------------------------------------------
-- Install a specified package into the system
--
-- You will have to restart the module before changes take effect.
-- @string pkg Package file path
-- @usage
-- usb.installPackages(usbPath .. '/L000-517-1.1.1-M02.rpk')
function _M.installPackage(pkg)
    _M.commitFileChanges()
    return os.execute('/usr/local/bin/rinfwupgrade ' .. pkg)
end

-------------------------------------------------------------------------------
-- Install all packages from the given directory into the system.
--
-- You will have to restart the module before changes take effect.
-- @string dir Directory containing packages
-- @usage
-- usb.installPackages(usbPath .. '/packages')
function _M.installPackages(dir)
    local packages = posix.glob(dir .. '/*.[oOrR][Pp][kK]')
    if packages ~= nil then
        for _, p in pairs(packages) do
            _M.installPackage(p)
        end
    end
end

-------------------------------------------------------------------------------
-- Unmount a partition and remove the directory
-- 
-- Note: On the C500, device.usbEject() should be called.
-- @string path Location of mounted partition
-- @treturn int Result code, 0 being no error
-- @usage
-- usb.unmount(usbPath)
function _M.unmount(path)
    _M.commitFileChanges()
    return partition and partition.umount(path)
end

return _M
