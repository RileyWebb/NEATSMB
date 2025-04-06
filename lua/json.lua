-- json.lua
-- A simple JSON encoder/decoder for Lua
local json = {}

-- Helper functions
local function escape_str(s)
    local escapes = {
        ['"'] = '\\"',
        ['\\'] = '\\\\',
        ['/'] = '\\/',
        ['\b'] = '\\b',
        ['\f'] = '\\f',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t'
    }
    return s:gsub('[%z\1-\31"\\/]', escapes)
end

-- Encode a Lua value to JSON
function json.encode(value)
    local kind = type(value)
    
    if kind == 'nil' then
        return 'null'
    elseif kind == 'boolean' then
        return value and 'true' or 'false'
    elseif kind == 'number' then
        if value ~= value then -- NaN
            return 'null'
        elseif value >= math.huge then -- Infinity
            return '1e9999'
        elseif value <= -math.huge then -- -Infinity
            return '-1e9999'
        else
            return tostring(value)
        end
    elseif kind == 'string' then
        return '"' .. escape_str(value) .. '"'
    elseif kind == 'table' then
        local is_array = true
        local i = 1
        for k in pairs(value) do
            if k ~= i then
                is_array = false
                break
            end
            i = i + 1
        end
        
        if is_array then
            local parts = {}
            for _, v in ipairs(value) do
                table.insert(parts, json.encode(v))
            end
            return '[' .. table.concat(parts, ',') .. ']'
        else
            local parts = {}
            for k, v in pairs(value) do
                if type(k) == 'string' then
                    table.insert(parts, '"' .. escape_str(k) .. '":' .. json.encode(v))
                end
            end
            return '{' .. table.concat(parts, ',') .. '}'
        end
    else
        error("Unsupported type for JSON encoding: " .. kind)
    end
end

-- Decode JSON to Lua value
function json.decode(str)
    local pos = 1
    
    local function skip_whitespace()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' then
                pos = pos + 1
            else
                break
            end
        end
    end
    
    local function parse_value()
        skip_whitespace()
        local c = str:sub(pos, pos)
        
        if c == '{' then
            return parse_object()
        elseif c == '[' then
            return parse_array()
        elseif c == '"' then
            return parse_string()
        elseif c == 't' then
            return parse_literal('true', true)
        elseif c == 'f' then
            return parse_literal('false', false)
        elseif c == 'n' then
            return parse_literal('null', nil)
        else
            return parse_number()
        end
    end
   
    local function parse_object()
        pos = pos + 1 -- skip '{'
        local obj = {}
        
        skip_whitespace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        
        while true do
            local key = parse_string()
            skip_whitespace()
            if str:sub(pos, pos) ~= ':' then
                error("Expected ':' at position " .. pos)
            end
            pos = pos + 1
            skip_whitespace()
            local value = parse_value()
            obj[key] = value
            
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == '}' then
                pos = pos + 1
                return obj
            elseif c ~= ',' then
                error("Expected ',' or '}' at position " .. pos)
            end
            pos = pos + 1
            skip_whitespace()
        end
    end
    
    local function parse_array()
        pos = pos + 1 -- skip '['
        local arr = {}
        local i = 1
        
        skip_whitespace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        
        while true do
            arr[i] = parse_value()
            i = i + 1
            
            skip_whitespace()
            local c = str:sub(pos, pos)
            if c == ']' then
                pos = pos + 1
                return arr
            elseif c ~= ',' then
                error("Expected ',' or ']' at position " .. pos)
            end
            pos = pos + 1
            skip_whitespace()
        end
    end
    
    local function parse_string()
        pos = pos + 1 -- skip opening '"'
        local result = ''
        local escaping = false
        
        while pos <= #str do
            local c = str:sub(pos, pos)
            pos = pos + 1
            
            if escaping then
                if c == 'b' then
                    result = result .. '\b'
                elseif c == 'f' then
                    result = result .. '\f'
                elseif c == 'n' then
                    result = result .. '\n'
                elseif c == 'r' then
                    result = result .. '\r'
                elseif c == 't' then
                    result = result .. '\t'
                else
                    result = result .. c
                end
                escaping = false
            elseif c == '\\' then
                escaping = true
            elseif c == '"' then
                return result
            else
                result = result .. c
            end
        end
        
        error("Unterminated string")
    end
    
    local function parse_literal(literal, value)
        if str:sub(pos, pos + #literal - 1) == literal then
            pos = pos + #literal
            return value
        else
            error("Expected '" .. literal .. "' at position " .. pos)
        end
    end
    
    local function parse_number()
        local start_pos = pos
        local is_float = false
        
        -- Optional sign
        if str:sub(pos, pos) == '-' then
            pos = pos + 1
        end
        
        -- Integer part
        if str:sub(pos, pos) == '0' then
            pos = pos + 1
        elseif str:sub(pos, pos):match('[1-9]') then
            pos = pos + 1
            while str:sub(pos, pos):match('[0-9]') do
                pos = pos + 1
            end
        else
            error("Invalid number at position " .. pos)
        end
        
        -- Fraction part
        if str:sub(pos, pos) == '.' then
            is_float = true
            pos = pos + 1
            if not str:sub(pos, pos):match('[0-9]') then
                error("Expected digit after decimal point at position " .. pos)
            end
            while str:sub(pos, pos):match('[0-9]') do
                pos = pos + 1
            end
        end
        
        -- Exponent part
        if str:sub(pos, pos):match('[eE]') then
            is_float = true
            pos = pos + 1
            if str:sub(pos, pos):match('[+-]') then
                pos = pos + 1
            end
            if not str:sub(pos, pos):match('[0-9]') then
                error("Expected digit in exponent at position " .. pos)
            end
            while str:sub(pos, pos):match('[0-9]') do
                pos = pos + 1
            end
        end
        
        local num_str = str:sub(start_pos, pos - 1)
        if is_float then
            return tonumber(num_str)
        else
            return math.floor(tonumber(num_str))
        end
    end
    
    local result = parse_value()
    skip_whitespace()
    if pos <= #str then
        error("Unexpected character at position " .. pos)
    end
    return result
end

return json