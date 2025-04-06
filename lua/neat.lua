require('state')
local json = require('json')

-- NEAT (NeuroEvolution of Augmenting Topologies) Implementation in Lua

local NEAT = {}
NEAT.__index = NEAT

-- Configuration Parameters (adjust as needed)
local config = {
    populationSize = 75,
    speciesThreshold = 2.0,
    compatibilityThreshold = 3.0,
    c1 = 1.0, -- Weight difference coefficient
    c2 = 1.0, -- Disjoint difference coefficient
    c3 = 1.0, -- Excess difference coefficient
    addNodeProbability = 0.06,
    addConnectionProbability = 0.1,
    mutateWeightsProbability = 0.8,
    weightMutationPower = 0.2,
    survivalRatio = 0.1,    -- Percentage of top performers to keep
    mutationOnlyRatio = 0.45, -- Percentage of offspring created without crossover
}

-- Genome Structure
local Genome = {}
Genome.__index = Genome

function Genome.new(inputSize, outputSize)
    local self = setmetatable({}, Genome)
    self.connections = {} -- {inNode, outNode, weight, enabled, innovation}
    self.nodes = {}     -- {id, type} (type: "input", "hidden", "output")
    self.fitness = 0
    self.adjustedFitness = 0
    self.species = nil
    self.innovationCounter = 0
    self.inputSize = inputSize
    self.outputSize = outputSize

    -- Initialize input and output nodes
    for i = 1, inputSize do
        self.nodes[i] = { id = i, type = "input" }
    end
    for i = 1, outputSize do
        self.nodes[inputSize + i] = { id = inputSize + i, type = "output" }
    end

    -- Create initial connections between inputs and outputs
    for i = 1, inputSize do
        for j = 1, outputSize do
            self.connections[#self.connections + 1] = {
                i,                 -- inNode
                inputSize + j,     -- outNode
                math.random() * 2 - 1, -- weight (-1 to 1)
                true,              -- enabled
                self.innovationCounter + 1 -- innovation
            }
            self.innovationCounter = self.innovationCounter + 1
        end
    end

    return self
end

function Genome:clone()
    local newGenome = Genome.new(self.inputSize, self.outputSize)
    newGenome.nodes = deepcopy(self.nodes)
    newGenome.connections = deepcopy(self.connections)
    newGenome.innovationCounter = self.innovationCounter
    newGenome.fitness = self.fitness
    newGenome.adjustedFitness = self.adjustedFitness
    return newGenome
end

-- Compatibility Distance
function Genome:compatibilityDistance(other)
    local disjoint = 0
    local excess = 0
    local weightDiff = 0
    local matching = 0

    -- Sort connections by innovation number
    table.sort(self.connections, function(a, b) return a[5] < b[5] end)
    table.sort(other.connections, function(a, b) return a[5] < b[5] end)

    local i, j = 1, 1
    while i <= #self.connections and j <= #other.connections do
        local conn1 = self.connections[i]
        local conn2 = other.connections[j]

        if conn1[5] == conn2[5] then -- Matching genes
            weightDiff = weightDiff + math.abs(conn1[3] - conn2[3])
            matching = matching + 1
            i = i + 1
            j = j + 1
        elseif conn1[5] < conn2[5] then -- Disjoint in self
            disjoint = disjoint + 1
            i = i + 1
        else -- Disjoint in other
            disjoint = disjoint + 1
            j = j + 1
        end
    end

    -- Remaining genes are excess
    excess = (#self.connections - i + 1) + (#other.connections - j + 1)

    local N = math.max(#self.connections, #other.connections, 1) -- Normalize
    local distance = (config.c1 * weightDiff / matching) + (config.c2 * disjoint / N) + (config.c3 * excess / N)

    return distance
end

-- Mutation Functions
function Genome:addNode()
    if #self.connections == 0 then return end

    -- Find an enabled connection to split
    local enabledConnections = {}
    for _, conn in ipairs(self.connections) do
        if conn[4] then table.insert(enabledConnections, conn) end
    end

    if #enabledConnections == 0 then return end

    local conn = enabledConnections[math.random(#enabledConnections)]
    conn[4] = false -- Disable the connection

    local newNodeId = #self.nodes + 1
    self.nodes[newNodeId] = { id = newNodeId, type = "hidden" }

    -- New connection from input node to new node
    self.connections[#self.connections + 1] = {
        conn[1],               -- inNode
        newNodeId,             -- outNode
        1.0,                   -- weight
        true,                  -- enabled
        self.innovationCounter + 1 -- innovation
    }

    -- New connection from new node to output node
    self.connections[#self.connections + 1] = {
        newNodeId,             -- inNode
        conn[2],               -- outNode
        conn[3],               -- weight (same as original connection)
        true,                  -- enabled
        self.innovationCounter + 2 -- innovation
    }

    self.innovationCounter = self.innovationCounter + 2
end

function Genome:addConnection()
    -- Try to find a valid connection to add
    for _ = 1, 100 do -- Try up to 100 times to find a valid connection
        local node1 = self.nodes[math.random(#self.nodes)]
        local node2 = self.nodes[math.random(#self.nodes)]

        -- Check if connection is valid
        if node1.id ~= node2.id and
            node1.type ~= "output" and
            node2.type ~= "input" and
            not self:connectionExists(node1.id, node2.id) then
            self.connections[#self.connections + 1] = {
                node1.id,          -- inNode
                node2.id,          -- outNode
                math.random() * 2 - 1, -- weight (-1 to 1)
                true,              -- enabled
                self.innovationCounter + 1 -- innovation
            }
            self.innovationCounter = self.innovationCounter + 1
            return
        end
    end
end

function Genome:connectionExists(inNode, outNode)
    for _, conn in ipairs(self.connections) do
        if conn[1] == inNode and conn[2] == outNode then
            return true
        end
    end
    return false
end

function Genome:mutateWeights()
    for _, conn in ipairs(self.connections) do
        if math.random() < config.mutateWeightsProbability then
            -- Either perturb or assign a new random value
            if math.random() < 0.9 then
                -- Perturb weight
                conn[3] = conn[3] + (math.random() - 0.5) * config.weightMutationPower
            else
                -- Assign completely new weight
                conn[3] = math.random() * 2 - 1
            end
        end
    end
end

-- Feedforward neural network
function Genome:activate(inputs)
    -- Initialize node values
    local nodeValues = {}

    -- First set all node values to 0
    for _, node in ipairs(self.nodes) do
        nodeValues[node.id] = 0
    end

    -- Then set input node values (using 1-based indexing)
    for i = 1, math.min(#inputs, self.inputSize) do
        nodeValues[i] = inputs[i] or 0 -- Ensure we don't go out of bounds
    end

    -- Process connections in order
    for _, conn in ipairs(self.connections) do
        if conn[4] then -- if enabled
            local inputValue = nodeValues[conn[1]] or 0
            nodeValues[conn[2]] = (nodeValues[conn[2]] or 0) + inputValue * conn[3]
        end
    end

    -- Apply activation function to output nodes
    local outputs = {}
    for i = self.inputSize + 1, self.inputSize + self.outputSize do
        outputs[i - self.inputSize] = self:sigmoid(nodeValues[i] or 0)
    end

    return outputs
end

function Genome:sigmoid(x)
    return 1 / (1 + math.exp(-4.9 * x))
end
function Genome:serialize()
    local serialized = {
        nodes = {},
        connections = {},
        innovationCounter = self.innovationCounter,
        inputSize = self.inputSize,
        outputSize = self.outputSize,
        fitness = self.fitness,
        adjustedFitness = self.adjustedFitness
    }

    -- Serialize nodes
    for id, node in pairs(self.nodes) do
        table.insert(serialized.nodes, {
            id = node.id,
            type = node.type
        })
    end

    -- Serialize connections
    for _, conn in ipairs(self.connections) do
        table.insert(serialized.connections, {
            inNode = conn[1],
            outNode = conn[2],
            weight = conn[3],
            enabled = conn[4],
            innovation = conn[5]
        })
    end

    return json.encode(serialized)
end

function Genome.deserialize(serializedStr)
    local data = json.decode(serializedStr)
    local genome = Genome.new(data.inputSize, data.outputSize)
    genome.innovationCounter = data.innovationCounter
    genome.fitness = data.fitness or 0
    genome.adjustedFitness = data.adjustedFitness or 0

    -- Reconstruct nodes
    genome.nodes = {}
    for _, nodeData in ipairs(data.nodes) do
        genome.nodes[nodeData.id] = {
            id = nodeData.id,
            type = nodeData.type
        }
    end

    -- Reconstruct connections
    genome.connections = {}
    for _, connData in ipairs(data.connections) do
        table.insert(genome.connections, {
            connData.inNode,
            connData.outNode,
            connData.weight,
            connData.enabled,
            connData.innovation
        })
    end

    return genome
end

function Genome:saveToFile(filename)
    local file = io.open(filename, "w")
    if not file then
        emu.print("Failed to open file for writing: " .. filename)
    end
    file:write(self:serialize())
    file:close()
end

function Genome.loadFromFile(filename)
    local file = io.open(filename, "r")
    if not file then
        error("Failed to open file for reading: " .. filename)
    end
    local content = file:read("*a")
    file:close()
    return Genome.deserialize(content)
end

-- NEAT functions
function NEAT:speciate(population)
    local species = {}
    local representatives = {}

    -- Clear old species assignments
    for _, genome in ipairs(population) do
        genome.species = nil
    end

    -- Create species with representatives
    for _, genome in ipairs(population) do
        local foundSpecies = false

        for speciesId, rep in pairs(representatives) do
            if genome:compatibilityDistance(rep) < config.compatibilityThreshold then
                genome.species = speciesId
                if not species[speciesId] then species[speciesId] = {} end
                table.insert(species[speciesId], genome)
                foundSpecies = true
                break
            end
        end

        if not foundSpecies then
            local newSpeciesId = #representatives + 1
            representatives[newSpeciesId] = genome
            genome.species = newSpeciesId
            species[newSpeciesId] = { genome }
        end
    end

    -- Remove empty species
    local validSpecies = {}
    for speciesId, members in pairs(species) do
        if #members > 0 then
            validSpecies[speciesId] = members
        end
    end

    return validSpecies
end

function NEAT:calculateAdjustedFitness(species)
    -- First calculate adjusted fitness for each genome
    for _, members in pairs(species) do
        for _, genome in ipairs(members) do
            genome.adjustedFitness = genome.fitness / #members
        end
    end

    -- Then calculate total adjusted fitness per species
    local speciesFitness = {}
    for speciesId, members in pairs(species) do
        speciesFitness[speciesId] = 0
        for _, genome in ipairs(members) do
            speciesFitness[speciesId] = speciesFitness[speciesId] + genome.adjustedFitness
        end
    end

    return speciesFitness
end

function NEAT:evolve(population)
    local species = self:speciate(population)
    local speciesFitness = self:calculateAdjustedFitness(species)
    local nextGeneration = {}

    -- Calculate total adjusted fitness
    local totalFitness = 0
    for _, fitness in pairs(speciesFitness) do
        totalFitness = totalFitness + fitness
    end

    -- Keep track of best genomes
    local bestGenomes = {}

    -- For each species, create offspring proportional to their fitness contribution
    for speciesId, members in pairs(species) do
        -- Sort by fitness
        table.sort(members, function(a, b) return a.fitness > b.fitness end)

        -- Always keep the best genome from each species (elitism)
        local bestInSpecies = members[1]:clone()
        table.insert(bestGenomes, bestInSpecies)

        -- Calculate how many offspring this species should produce
        local offspringCount = math.floor((speciesFitness[speciesId] / totalFitness) * config.populationSize)
        offspringCount = math.max(1, offspringCount) -- Each species gets at least 1 offspring

        -- Keep top performers (within species elitism)
        local survivors = math.max(1, math.floor(#members * config.survivalRatio))

        -- Create offspring
        for i = 1, offspringCount - 1 do -- -1 because we already have the best genome
            local child

            if math.random() < config.mutationOnlyRatio or #members < 2 then
                -- Mutation only
                child = members[math.random(survivors)]:clone()
            else
                -- Crossover
                local parent1 = members[math.random(survivors)]
                local parent2 = members[math.random(survivors)]
                child = self:crossover(parent1, parent2)
            end

            -- Mutate the child
            if math.random() < config.addNodeProbability then child:addNode() end
            if math.random() < config.addConnectionProbability then child:addConnection() end
            child:mutateWeights()

            table.insert(nextGeneration, child)
        end
    end

    -- Add the best genomes from each species
    for _, genome in ipairs(bestGenomes) do
        table.insert(nextGeneration, genome)
    end

    -- If we don't have enough genomes, fill the rest with random offspring
    while #nextGeneration < config.populationSize do
        local randomSpecies = species[math.random(#species)]
        local parent1 = randomSpecies[math.random(#randomSpecies)]
        local parent2 = randomSpecies[math.random(#randomSpecies)]
        local child = self:crossover(parent1, parent2)

        if math.random() < config.addNodeProbability then child:addNode() end
        if math.random() < config.addConnectionProbability then child:addConnection() end
        child:mutateWeights()

        table.insert(nextGeneration, child)
    end

    return nextGeneration
end

function NEAT:crossover(parent1, parent2)
    -- Make sure parent1 is the fitter one
    if parent2.fitness > parent1.fitness then
        parent1, parent2 = parent2, parent1
    end

    local child = Genome.new(parent1.inputSize, parent1.outputSize)
    child.nodes = deepcopy(parent1.nodes)
    child.innovationCounter = math.max(parent1.innovationCounter, parent2.innovationCounter)

    -- Create connection maps for both parents
    local connections1 = {}
    local connections2 = {}
    for _, conn in ipairs(parent1.connections) do
        connections1[conn[5]] = conn
    end
    for _, conn in ipairs(parent2.connections) do
        connections2[conn[5]] = conn
    end

    -- Iterate through all possible innovation numbers
    local maxInnovation = math.max(parent1.innovationCounter, parent2.innovationCounter)
    for i = 1, maxInnovation do
        if connections1[i] or connections2[i] then
            if connections1[i] and connections2[i] then
                -- Matching gene - randomly select one
                local selected = math.random() < 0.5 and connections1[i] or connections2[i]
                table.insert(child.connections, {
                    selected[1], selected[2], selected[3], selected[4], selected[5]
                })
            elseif connections1[i] then
                -- Disjoint or excess gene from parent1
                table.insert(child.connections, {
                    connections1[i][1], connections1[i][2], connections1[i][3], connections1[i][4], connections1[i][5]
                })
            end
            -- Don't include disjoint/excess from parent2 (since parent1 is fitter)
        end
    end

    return child
end

-- Deep copy function
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function drawInputMatrix(state)
    for x = 1, #state.inputs do       -- Changed to 1-based indexing
        for y = 1, #state.inputs[x] do -- Changed to 1-based indexing
            local color = nil         -- Initialize as nil

            if (state.inputs[x][y] == 1) then
                color = "black"
            elseif (state.inputs[x][y] == 2) then
                color = "red"
            elseif (state.inputs[x][y] == 3) then
                color = "blue"
            elseif (state.inputs[x][y] == 4) then
                color = "white"
            end

            if color then
                gui.setpixel(x - 1, y - 1 + 10, color) -- Adjust for 0-based pixel coordinates
            end
        end
    end
end

function drawCullLine(state, fcStart)
    local scrollX = memory.readbyte(0x071C)
    local pageNumber = memory.readbyte(0x006D)
    local absoluteScrollX = (pageNumber * 256) + scrollX

    local x = ((emu.framecount() - fcStart) * 1.5) - absoluteScrollX
    if (x >= 0) and (x < 255) then
        gui.line(x, 0, x, 255, "red")
    end
end
-- Line Graph Network Visualization
function drawNetworkLineGraph(genome, inputs, outputs)
    local width = 90  -- Width of the visualization
    local height = 120 -- Height of the visualization
    local startX = 256 - width - 5  -- Right side of screen
    local startY = 5   -- Top of screen
    
    -- Calculate node activations
    local activations = {}
    local maxLayer = 0
    local nodesByLayer = {}
    
    -- Organize nodes by layer (BFS to determine layers)
    local function calculateLayers()
        local inputNodes = {}
        local outputNodes = {}
        
        -- Find input and output nodes
        for _, node in ipairs(genome.nodes) do
            if node.type == "input" then
                table.insert(inputNodes, node)
                activations[node.id] = inputs[node.id] or 0
            elseif node.type == "output" then
                table.insert(outputNodes, node)
            end
        end
        
        -- Assign layers
        for _, node in ipairs(inputNodes) do
            node.layer = 0
            nodesByLayer[0] = nodesByLayer[0] or {}
            table.insert(nodesByLayer[0], node)
        end
        
        local changed = true
        while changed do
            changed = false
            for _, conn in ipairs(genome.connections) do
                if conn[4] then -- if enabled
                    local fromNode = genome.nodes[conn[1]]
                    local toNode = genome.nodes[conn[2]]
                    
                    if fromNode.layer and (not toNode.layer or toNode.layer <= fromNode.layer) then
                        toNode.layer = fromNode.layer + 1
                        nodesByLayer[toNode.layer] = nodesByLayer[toNode.layer] or {}
                        table.insert(nodesByLayer[toNode.layer], toNode)
                        maxLayer = math.max(maxLayer, toNode.layer)
                        changed = true
                    end
                end
            end
        end
        
        -- Assign layers to unconnected outputs
        for _, node in ipairs(outputNodes) do
            if not node.layer then
                node.layer = maxLayer + 1
                nodesByLayer[node.layer] = nodesByLayer[node.layer] or {}
                table.insert(nodesByLayer[node.layer], node)
                maxLayer = math.max(maxLayer, node.layer)
            end
        end
    end
    
    calculateLayers()
    
    -- Calculate activations
    for layer = 1, maxLayer do
        if nodesByLayer[layer] then
            for _, node in ipairs(nodesByLayer[layer]) do
                local sum = 0
                for _, conn in ipairs(genome.connections) do
                    if conn[4] and conn[2] == node.id then
                        sum = sum + (activations[conn[1]] or 0) * conn[3]
                    end
                end
                activations[node.id] = genome:sigmoid(sum)
            end
        end
    end
    
    -- Draw the line graph
    local layerWidth = width / math.max(1, maxLayer)
    
    -- Draw connections as lines with fading colors
    for _, conn in ipairs(genome.connections) do
        if conn[4] and genome.nodes[conn[1]].layer and genome.nodes[conn[2]].layer then
            local fromLayer = genome.nodes[conn[1]].layer
            local toLayer = genome.nodes[conn[2]].layer
            local fromX = startX + fromLayer * layerWidth
            local toX = startX + toLayer * layerWidth
            
            -- Find vertical positions (average if multiple nodes in layer)
            local fromY = startY + height/2
            local toY = startY + height/2
            
            if nodesByLayer[fromLayer] then
                for i, node in ipairs(nodesByLayer[fromLayer]) do
                    if node.id == conn[1] then
                        fromY = startY + (i/#nodesByLayer[fromLayer]) * height
                        break
                    end
                end
            end
            
            if nodesByLayer[toLayer] then
                for i, node in ipairs(nodesByLayer[toLayer]) do
                    if node.id == conn[2] then
                        toY = startY + (i/#nodesByLayer[toLayer]) * height
                        break
                    end
                end
            end
            
            -- Color based on weight and activation
            local intensity = math.min(255, math.abs(conn[3] * 255))
            local r, g, b
            if conn[3] > 0 then
                r = intensity
                g = intensity/2
                b = 0
            else
                r = 0
                g = intensity/2
                b = intensity
            end
            
            -- Fade based on source activation
            local fade = activations[conn[1]] or 0
            r = math.floor(r * fade)
            g = math.floor(g * fade)
            b = math.floor(b * fade)
            
            gui.drawline(fromX, fromY, toX, toY, string.format("#%02x%02x%02x", r, g, b))
        end
    end
    
    -- Draw layer markers
    for layer = 0, maxLayer do
        local x = startX + layer * layerWidth
        gui.drawline(x, startY, x, startY + height, "gray")
        
        -- Label layers
        if layer == 0 then
            gui.drawtext(x - 10, startY + height + 5, "In", "white", 8)
        elseif layer == maxLayer then
            gui.drawtext(x - 10, startY + height + 5, "Out", "white", 8)
        end
    end
    
    -- Draw output activations
    local outputY = startY + height + 20
    for i, node in ipairs(nodesByLayer[maxLayer] or {}) do
        local activation = activations[node.id] or 0
        local color = activation > 0.5 and "green" or "red"
        gui.drawtext(startX + width - 30, outputY + (i-1)*10, 
                     string.format("%.2f", activation), color, 8)
    end
end

-- ENTRYPOINT

if (rom.gethash("md5") == not "8e3630186e35d477231bf8fd50e54cdd") then
    emu.print("ERROR: This script only works with Super Mario Bros. (Please source a legal copy... off archive.org)")
    emu.print(rom.gethash("md5"))
end

local generation = 0
local bestFitness = 0

local neat = setmetatable({}, NEAT)
local population = {}
for i = 1, config.populationSize do
    population[i] = Genome.new(16 * 14, 6) -- 16*14 inputs, 6 outputs
end

while (true) do
    generation = generation + 1
    local currentBest = 0

    for _, genome in ipairs(population) do
        savestate.load(savestate.object(1))
        local fcStart = emu.framecount()

        repeat
            state = getState()

            gui.drawtext(16, 16, string.format("Gen: %d Fit: %d Best: %d FC: %d",
                generation, state.progress, bestFitness, (emu.framecount() - fcStart)))
            drawCullLine(state, fcStart)
            drawInputMatrix(state)

            -- Get inputs from state (flatten the input matrix)
            local inputs = {}
            for x = 0, #state.inputs do
                for y = 0, #state.inputs[x] do
                    table.insert(inputs, state.inputs[x][y])
                end
            end

            -- Activate the neural network
            local outputs = genome:activate(inputs)
            
            --drawNetworkLineGraph(genome, inputs, outputs)
            --drawNetwork(genome, inputs, outputs)

            -- Use outputs to control the game
            local buttons = {}
            local buttonMap = { "right", "left", "up", "down", "A", "B" }

            for i = 1, math.min(#outputs, 6) do -- Ensure we don't go beyond 6 outputs
                if outputs[i] > 0.5 then
                    buttons[buttonMap[i]] = true
                end
            end

            -- Write the button presses to joypad
            joypad.write(1, buttons)
            -- etc for other controls

            emu.frameadvance()
        until (state.alive == false) or (emu.framecount() - fcStart) * 1.5 > state.progress

        genome.fitness = state.progress
        if genome.fitness > currentBest then
            currentBest = genome.fitness
        end
        if genome.fitness > bestFitness then
            bestFitness = genome.fitness
        end
    end

    emu.print(string.format("Generation %d - Best Fitness: %d", generation, currentBest))

    local bestGenome = population[1]
    for _, genome in ipairs(population) do
        if genome.fitness > bestGenome.fitness then
            bestGenome = genome
        end
    end
    bestGenome:saveToFile(string.format("genomes/Gen%d.json", generation))

    -- Evolve to the next generation
    population = neat:evolve(population)
end
