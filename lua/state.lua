-- PPU Name Table Addresses
local NAME_TABLE_1 = 0x2000
local NAME_TABLE_2 = 0x2400

-- Screen and Tile Constants
local SCREEN_WIDTH, SCREEN_HEIGHT, TILE_SIZE, GRID_SIZE = 256, 240, 8, 16

-- Collidable tile values in SMB (update as needed)
local collidable_tiles = {
    0xB4, 0xB5, 0xB6, 0xB7, -- Ground
    0x53, 0x54, 0x55, 0x56, -- ? Block
    0x57, 0x58, 0x59, 0x5A, -- Broken ? Block
    0x45, 0x47, -- Brick Block
    0x60, 0x61, 0x62, 0x63, -- Pipe Top
    0x64, 0x65, 0x66, 0x67, -- Pipe Top-Bottom
    0x68, 0x69, 0x6A, -- Pipe Body
    0xAB, 0xAC, 0xAD, 0xAE  -- Block
}

-- hitbox coordinate offsets (x1,y1,x2,y2)
local mario_hb = 0x04AC; -- 1x4
local enemy_hb = 0x04B0; -- 5x4
local coin_hb  = 0x04E0; -- 3x4
local fiery_hb = 0x04C8; -- 2x4
local hammer_hb= 0x04D0; -- 9x4
local power_hb = 0x04C4; -- 1x4

-- addresses to check, to see whether the hitboxes should be drawn at all
local mario_ch = 0x000E;
local enemy_ch = 0x000F;
local coin_ch  = 0x0030;
local fiery_ch = 0x0024;
local hammer_ch= 0x002A;
local power_ch = 0x0014;

local marioXLowByteAddress = 0x0086 -- High byte of Mario's X position
local marioXHighByteAddress = 0x006D -- Low byte of Mario's X position

-- Convert array to lookup table for quick checks
local collidable_lookup = {}
for _, tile in ipairs(collidable_tiles) do
    collidable_lookup[tile] = true
end

-- Get active name tables based on current page
local function getActiveNameTables()
    local page = memory.readbyte(0x071A)
    return page % 2 == 0 and NAME_TABLE_1 or NAME_TABLE_2, page % 2 == 0 and NAME_TABLE_2 or NAME_TABLE_1
end

-- Get collidable 16x16 tile positions
local function getCollidableTilePositions()
    local scrollX = memory.readbyte(0x071C)  -- Horizontal scroll position
    local tileOffset = math.floor(scrollX / TILE_SIZE)
    local activeTable1, activeTable2 = getActiveNameTables()
    local tilePositions = {}

    -- Iterate over the screen in 16x16 tile blocks
    for y = 0, 14 do  -- 15 blocks high
        for x = 0, 15 + tileOffset do -- 16 blocks wide, including wrapped section
            local baseX, baseY = (x % 16) * 2, y * 2  -- 8x8 grid indexing
            local collidable = false

            -- Check if any of the 2x2 8x8 tiles within this 16x16 block are collidable
            for dy = 0, 1 do
                for dx = 0, 1 do
                    local tileAddress = (x < 16 and activeTable1 or activeTable2) + (baseX + dx) + ((baseY + dy) * 32)
                    local tileValue = ppu.readbyte(tileAddress)
                    if collidable_lookup[tileValue] then
                        collidable = true
                        break
                    end
                end
                if collidable then break end
            end

            if collidable then
                table.insert(tilePositions, {x = x * GRID_SIZE - scrollX, y = y * GRID_SIZE})
            end
        end
    end
    
    return tilePositions
end


-- Function to process entities and their bounding boxes
local function processEntity(hb, ch)
    if (memory.readbyte(ch) > 0) then
        -- Read the bounding box coordinates
        local a, b, c, d = memory.readbyte(hb), memory.readbyte(hb+1), memory.readbyte(hb+2), memory.readbyte(hb+3)
        
        -- Calculate and display midpoint
        local midX = (a + c) / 2
        local midY = (b + d) / 2

        return math.floor(midX / GRID_SIZE), midY / GRID_SIZE
    end
end

function getState()
    local state = {}

    state.alive = true
    state.progress = memory.readbyte(marioXLowByteAddress) + (memory.readbyte(marioXHighByteAddress) * 256)

    if (memory.readbyte(0x000E) == 0x0B) or (memory.readbyte(0x00B5) > 1) then --and () then
        state.alive = false
    end

    state.inputs = {}          -- create the matrix
    for x=0,32 do
        state.inputs[x] = {}     -- create a new row
      for y=0,32 do
        state.inputs[x][y] = 0
      end
    end

    local tilePositions = getCollidableTilePositions()

    for _, pos in ipairs(tilePositions) do
        if (pos.x >= - GRID_SIZE) and (pos.x < SCREEN_WIDTH) and (pos.y >= 0) and (pos.y < SCREEN_HEIGHT) then
            state.inputs[math.floor(pos.x / GRID_SIZE) + 1][math.floor(pos.y / GRID_SIZE)] = 1
        end
    end

    -- Get Mario's Position
    local x, y = processEntity(mario_hb, mario_ch)
    if (x ~= nil) and (y ~= nil) and (x >= 0) and (x < SCREEN_WIDTH/TILE_SIZE) and (y >= 0) and (y < SCREEN_HEIGHT/TILE_SIZE) then
        state.inputs[math.floor(x)][math.floor(y)] = 4
    end

    -- Process Enemies
    for i = 0, 4 do
        x, y = processEntity(enemy_hb + i * 4, enemy_ch + i)
        if (x ~= nil) and (y ~= nil) and (x >= 0) and (x < SCREEN_WIDTH/TILE_SIZE) and (y >= 0) and (y < SCREEN_HEIGHT/TILE_SIZE) then
            state.inputs[math.floor(x)][math.floor(y)] = 2
        end
    end

    x, y = processEntity(power_hb, power_ch)
    if (x ~= nil) and (y ~= nil) and (x >= 0) and (x < SCREEN_WIDTH/TILE_SIZE) and (y >= 0) and (y < SCREEN_HEIGHT/TILE_SIZE)then
        state.inputs[math.floor(x)][math.floor(y)] = 3
    end

    return state
end