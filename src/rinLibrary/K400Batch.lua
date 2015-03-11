-------------------------------------------------------------------------------
--- Batching scale functions.
-- Functions to support the K410 Batching and products
-- @module rinLibrary.K400Batch
-- @author Pauli
-- @copyright 2015 Rinstrum Pty Ltd
-------------------------------------------------------------------------------

local csv       = require 'rinLibrary.rinCSV'
local canonical = require('rinLibrary.namings').canonicalisation
local dbg       = require "rinLibrary.rinDebug"
local utils     = require 'rinSystem.utilities'

local cb = utils.cb

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule function begins here
return function (_M, private, deprecated)
local numStages, numMaterials = 0, 0

-------------------------------------------------------------------------------
-- Query the number of materials available in the display.
-- @return Number of material slots in display's database
-- @usage
-- print('We can deal with '..device.getNativeMaterialCount()..' materials.')
function _M.getNativeMaterialCount()
    return numMaterials
end

-------------------------------------------------------------------------------
-- Query the number of batching stages available in the display.
-- @return Number of batching stages in display's database
-- @usage
-- print('We can deal with '..device.getNativeStageCount()..' stages.')
function _M.getNativeStageCount()
    return numStages
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -
-- Submodule register definitions hinge on the model type
private.registerDeviceInitialiser(function()
    local batching = private.batching(true)
    local recipes, materialCSV, recipesCSV = {}
    local materialRegs, stageRegisters = {}, {}
    local stageDevice = _M

    if batching then
        numStages = 10
        numMaterials = private.valueByDevice{ default=1, k411=6, k412=20, k415=6 }

        private.addRegisters{
            product_time            = 0xB106,
            product_time_average    = 0xB107,
            product_error           = 0xB108,
            product_error_pc        = 0xB109,
            product_error_average   = 0xB10A,
            product_menu_op_stages  = 0xB10B,
            material_spec           = 0xC100,
        }

-------------------------------------------------------------------------------
-- Add a block of registers to the register file
-- Update the definition table so the value is the register name
-- @param prefix Prefix to be applied to the register name
-- @param regs Table of register and base step pairs.
-- @param qty Number of times to step for these registers
-- @local
        local function blockRegs(prefix, regs, qty)
            for name, v in pairs(regs) do
                local n = prefix..name
                private.addRegisters { [n] = v[1] }
                if qty > 1 then
                    for i = 1, qty do
                        private.addRegisters { [n..i] = v[1] + (i-1) * v[2] }
                    end
                end
                regs[name] = n
            end
        end

        -- Load material register names into the register database
        materialRegs = {
            name                = { 0xC081, 0x01 },
            flight              = { 0xC101, 0x10 },
            medium              = { 0xC102, 0x10 },
            fast                = { 0xC103, 0x10 },
            total               = { 0xC104, 0x10 },
            num                 = { 0xC105, 0x10 },
            error               = { 0xC106, 0x10 },
            error_pc            = { 0xC107, 0x10 },
            error_average       = { 0xC108, 0x10 }
        }
        blockRegs('material_', materialRegs, numMaterials)

        -- Load stage register names into the register database
        stageRegisters = {
            type                = { 0xC400, 0x0100 },
            fill_slow           = { 0xC401, 0x0100 },
            fill_medium         = { 0xC402, 0x0100 },
            fill_fast           = { 0xC403, 0x0100 },
            fill_ilock          = { 0xC404, 0x0100 },
            fill_output         = { 0xC405, 0x0100 },
            fill_feeder         = { 0xC406, 0x0100 },
            fill_material       = { 0xC407, 0x0100 },
            fill_start_action   = { 0xC408, 0x0100 },
            fill_correction     = { 0xC409, 0x0100 },
            fill_jog_on         = { 0xC40A, 0x0100 },
            fill_jog_off        = { 0xC40B, 0x0100 },
            fill_jog_set        = { 0xC40C, 0x0100 },
            fill_delay_start    = { 0xC40D, 0x0100 },
            fill_delay_check    = { 0xC40E, 0x0100 },
            fill_delay_end      = { 0xC40F, 0x0100 },
            fill_max_set        = { 0xC412, 0x0100 },
            fill_input          = { 0xC413, 0x0100 },
            fill_direction      = { 0xC414, 0x0100 },
            fill_input_wait     = { 0xC415, 0x0100 },
            fill_source         = { 0xC416, 0x0100 },
            fill_pulse_scale    = { 0xC417, 0x0100 },
            fill_tol_lo         = { 0xC420, 0x0100 },
            fill_tol_high       = { 0xC421, 0x0100 },
            fill_tol_target     = { 0xC422, 0x0100 },
            dump_dump           = { 0xC440, 0x0100 },
            dump_output         = { 0xC441, 0x0100 },
            dump_enable         = { 0xC442, 0x0100 },
            dump_ilock          = { 0xC443, 0x0100 },
            dump_type           = { 0xC444, 0x0100 },
            dump_correction     = { 0xC445, 0x0100 },
            dump_delay_start    = { 0xC446, 0x0100 },
            dump_delay_check    = { 0xC447, 0x0100 },
            dump_delay_end      = { 0xC448, 0x0100 },
            dump_jog_on_time    = { 0xC449, 0x0100 },
            dump_jog_off_time   = { 0xC44A, 0x0100 },
            dump_jog_set        = { 0xC44B, 0x0100 },
            dump_target         = { 0xC44C, 0x0100 },
            dump_pulse_time     = { 0xC44D, 0x0100 },
            dump_on_tol         = { 0xC44E, 0x0100 },
            dump_off_tol        = { 0xC44F, 0x0100 },
            pulse_output        = { 0xC460, 0x0100 },
            pulse_pulse         = { 0xC461, 0x0100 },
            pulse_delay_start   = { 0xC462, 0x0100 },
            pulse_delay_end     = { 0xC463, 0x0100 },
            pulse_start_action  = { 0xC464, 0x0100 },
            pulse_link          = { 0xC466, 0x0100 },
            pulse_time          = { 0xC467, 0x0100 },
            pulse_name          = { 0xC468, 0x0100 },
            pulse_prompt        = { 0xC469, 0x0100 },
            pulse_input         = { 0xC46A, 0x0100 },
            pulse_timer         = { 0xC46B, 0x0100 }
        }
        blockRegs('stage_', stageRegisters, numStages)
    end

-------------------------------------------------------------------------------
-- Load the material and stage CSV files into memory
-- @function loadBatchingTables
-- @usage
-- device.loadBatchingTables()  -- reload the batching databases
    private.exposeFunction('loadBatchingTables', batching, function()
        materialCSV = csv.loadCSV{
            fname = 'materials.csv',
            --labels = materialRegs
        }

        recipesCSV = csv.loadCSV{
            fname = 'recipes.csv',
            labels = { 'recipe', 'datafile' }
        }

        recipes = {}
        for _, r in csv.records(recipesCSV) do
            recipes[canonical(r.recipe)] = csv.loadCSV {
                fname = r.datafile
            }
            --dbg.info('loading', r.recipe, recipes[canonical(r.recipe)])
        end
    end)
    if batching then
        _M.loadBatchingTables()
    end

-------------------------------------------------------------------------------
-- Return a material CSV record
-- @function getMaterial
-- @param m Material name
-- @return CSV record for the given material or nil on error
-- @return Error message or nil for no error
-- @usage
-- local sand = device.getMaterial('sand')
    private.exposeFunction('getMaterial', batching, function(m)
        local _, r = csv.getRecordCSV(materialCSV, m, 'name')
        if r == nil then
            return nil, 'Material does not exist'
        end
        return r
    end)

-------------------------------------------------------------------------------
-- Set the current material in the indicator
-- @function setMaterialRegisters
-- @param m Material name to set to
-- @return nil if success, error message if failure
-- @usage
-- device.setCurrentMaterial 'sand'
    private.exposeFunction('setMaterialRegisters', batching, function(m)
        local rec, err = _M.getMaterial(m)
        if err == nil then
            for name, reg in pairs(materialRegs) do
                if rec[name] then
                    _M.setRegister(reg, rec[name])
                end
            end
        end
    end)

-------------------------------------------------------------------------------
-- Set the current stage in the indicator
-- @function setStageRegisters
-- @param S Stage record to set to
-- @usage
-- device.setStageRegisters { type='', fill_slow=1 }
    private.exposeFunction('setStageRegisters', batching, function(s)
        for name, reg in pairs(stageRegisters) do
            if s[name] then
                _M.setRegister(reg, s[name])
            end
        end

        stageDevice = s.device or _M
    end)

-------------------------------------------------------------------------------
-- Return a CSV file that contains the stages in a specified recipe.
-- @param r Names of recipe
-- @return Recipe CSV table or nil on error
-- @return Error indicator or nil for no error
-- @usage
-- local cementCSV = device.getRecipe 'cement'
    private.exposeFunction('getRecipe', batching, function(r)
        local rec = csv.getRecordCSV(recipesCSV, r, 'recipe')
        if rec == nil then
            return nil, 'recipe does not exist'
        end
        local z = recipes[canonical(rec.recipe)]
        return z, nil
    end)

-------------------------------------------------------------------------------
-- Return a CSV file that contains the stages in a user selected recipe.
-- @param prompt User prompt
-- @param default Default selection, nil for none
-- @return Recipe CSV table or nil on error
-- @return Error indicator or nil for no error
-- @usage
-- local cementCSV = device.getRecipe 'cement'
    private.exposeFunction('selectRecipe', batching, function(prompt, default)
        local recipes = csv.getColCSV(recipesCSV, 'recipe')
        local q = _M.selectOption(prompt or 'RECIPE', recipes, default)
        if q ~= nil then
            return _M.getRecipe(q)
        end
        return nil, 'cancelled'
    end)

-------------------------------------------------------------------------------
-- Run a batching process
-- @function runRecipe
-- @param rname Recipe name
-- @return Error code
-- @usage
-- device.runRecipe 'cement'
    private.exposeFunction('recipeFSM', batching, function(args)
        local rname = args[1] or args.name
        local recipe, err = _M.getRecipe(rname)
        if err then return nil, err end

        local deviceFinder = cb(args.device, function() return _M end)

        -- Extract the stages from the recipe CSV in a useable manner
        if csv.numRowsCSV(recipe) < 1 then return nil, 'no stages' end

        local stages = {}
        for i = 1, csv.numRowsCSV(recipe) do
            table.insert(stages, csv.getRowRecord(recipe, i))
        end
        table.sort(stages, function(a, b) return a.order < b.order end)

        -- Execute the stages sequentially in a FSM
        local pos, prev = 1, nil
        local fsm = _M.stateMachine { rname }
                        .state { 'init' }
        while pos <= #stages do
            local spos, epos = pos, pos
            while epos < #stages and stages[pos].order and stages[pos].order == stages[epos+1].order do
                epos = epos + 1
            end
            pos = epos + 1

            -- Sanity check to prevent using the same device twice
            if spos ~= epos then
                local used = {}
                for i = spos, epos do
                    local d = stages[i].device or _M
                    if used[d] then
                        return nil, 'duplicate device in stage '..stages[spos].order
                    end
                    used[d] = true
                end
            end

            -- Add a state to the FSM including a transition from the previous state
            local curName = 'ST'..(stages[spos].order or spos)
            fsm.state { curName, enter=function()
                            for i = spos, epos do
                                local d = deviceFinder(stages[i].device)
                                d.setMaterialRegisters(material)
                                d.setStageRegisters(stages[i])
                                --d.beginStage()
                            end
                        end }

            if prev then
                fsm.trans { prev, curName, cond=function()
                            for i = spos, epos do
                                local d = deviceFinder(stages[i].device)
                                if not d.allStatusSet('idle') then
                                    return false
                                end
                            end
                            return true
                        end }
            else
                fsm.trans { 'init', curName, event='begin' }
            end
            prev = curName
        end
        fsm.trans { prev, 'init', event='reset' }
        return fsm, nil
    end)

--- Material definition fields
--
-- These are the fields in the materials.csv material definition file.
-- They are loaded into and retrieved from the first material registers and
-- are intended to be used to allow an unlimited number of materials regardless
-- of the number of built in materials supported.
--@table MaterialFields
-- @field name Material name, this is the key field to specify a material by
-- @field flight flight
-- @field medium medium
-- @field fast fast
-- @field total total
-- @field num num
-- @field error error
-- @field error_pc error_pc
-- @field error_average error_average

--- Batching Registers
--
-- These registers define the extra information about materials and the batch stages.
-- In all cases below, replace the <i>X</i> by an integer 1 .. ? that represents the
-- material or stage of interest.  Additionally, all are available without the X and,
-- in this case, the 1 is implied.
--@table batchingRegisters
-- @field material_spec ?
-- @field material_nameX name of the Xth material
-- @field material_flightX flight for the Xth material
-- @field material_mediumX medium for the Xth material
-- @field material_fastX fast for the Xth material
-- @field material_totalX total for the Xth material
-- @field material_numX num for the Xth material
-- @field material_errorX error for the Xth material
-- @field material_error_pcX error_pc for the Xth material
-- @field material_error_averageX error_average for the Xth material
-- @field product_time ?
-- @field product_time_average ?
-- @field product_error ?
-- @field product_error_pc ?
-- @field product_error_average ?
-- @field product_menu_op_stages ?
-- @field stage_typeX for the Xth stage
-- @field stage_fill_slowX for the Xth stage
-- @field stage_fill_mediumX for the Xth stage
-- @field stage_fill_fastX for the Xth stage
-- @field stage_fill_ilockX for the Xth stage
-- @field stage_fill_outputX for the Xth stage
-- @field stage_fill_feederX for the Xth stage
-- @field stage_fill_materialX for the Xth stage
-- @field stage_fill_start_actionX for the Xth stage
-- @field stage_fill_correctionX for the Xth stage
-- @field stage_fill_jog_onX for the Xth stage
-- @field stage_fill_jog_offX for the Xth stage
-- @field stage_fill_jog_setX for the Xth stage
-- @field stage_fill_delay_startX for the Xth stage
-- @field stage_fill_delay_checkX for the Xth stage
-- @field stage_fill_delay_endX for the Xth stage
-- @field stage_fill_max_setX for the Xth stage
-- @field stage_fill_inputX for the Xth stage
-- @field stage_fill_directionX for the Xth stage
-- @field stage_fill_input_waitX for the Xth stage
-- @field stage_fill_sourceX for the Xth stage
-- @field stage_fill_pulse_scaleX for the Xth stage
-- @field stage_fill_tol_loX for the Xth stage
-- @field stage_fill_tol_highX for the Xth stage
-- @field stage_fill_tol_targetX for the Xth stage
-- @field stage_dump_dumpX for the Xth stage
-- @field stage_dump_outputX for the Xth stage
-- @field stage_dump_enableX for the Xth stage
-- @field stage_dump_ilockX for the Xth stage
-- @field stage_dump_typeX for the Xth stage
-- @field stage_dump_correctionX for the Xth stage
-- @field stage_dump_delay_startX for the Xth stage
-- @field stage_dump_delay_checkX for the Xth stage
-- @field stage_dump_delay_endX for the Xth stage
-- @field stage_dump_jog_on_timeX for the Xth stage
-- @field stage_dump_jog_off_timeX for the Xth stage
-- @field stage_dump_jog_setX for the Xth stage
-- @field stage_dump_targetX for the Xth stage
-- @field stage_dump_pulse_timeX for the Xth stage
-- @field stage_dump_on_tolX for the Xth stage
-- @field stage_dump_off_tolX for the Xth stage
-- @field stage_pulse_outputX for the Xth stage
-- @field stage_pulse_pulseX for the Xth stage
-- @field stage_pulse_delay_startX for the Xth stage
-- @field stage_pulse_delay_endX for the Xth stage
-- @field stage_pulse_start_actionX for the Xth stage
-- @field stage_pulse_linkX for the Xth stage
-- @field stage_pulse_timeX for the Xth stage
-- @field stage_pulse_nameX for the Xth stage
-- @field stage_pulse_promptX for the Xth stage
-- @field stage_pulse_inputX for the Xth stage
-- @field stage_pulse_timerX for the Xth stage

end)
end
