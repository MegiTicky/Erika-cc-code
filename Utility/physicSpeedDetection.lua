local function realVelocityCalculation()
    local oldTime = os.clock()
    local oldPosition = ship.getWorldspacePosition()
    local realVelocity = {x = 0, y = 0, z = 0}

    while true do
        local newTime = os.clock()
        local newPosition = ship.getWorldspacePosition()
        local deltaTime = newTime - oldTime

        if deltaTime > 0 then
            -- Compute real velocity
            realVelocity.x = (newPosition.x - oldPosition.x) / deltaTime
            realVelocity.y = (newPosition.y - oldPosition.y) / deltaTime
            realVelocity.z = (newPosition.z - oldPosition.z) / deltaTime

            -- Get apparent velocity from ship API
            local apparentVelocity = ship.getVelocity()

            -- Compute deviation index
            local realSpeed = math.sqrt(realVelocity.x^2 + realVelocity.y^2 + realVelocity.z^2)
            local apparentSpeed = math.sqrt(apparentVelocity.x^2 + apparentVelocity.y^2 + apparentVelocity.z^2)

            local deviationIndex = 0
            if realSpeed > 0 then
                deviationIndex = (apparentSpeed - realSpeed) / realSpeed
            end

            -- Print results
            print(string.format("Real Speed: %.2f m/s | Apparent Speed: %.2f m/s | Deviation Index: %.2f%%", 
                realSpeed, apparentSpeed, deviationIndex * 100))
        end

        -- Update previous values
        oldPosition = newPosition
        oldTime = newTime
        sleep(0.5)  -- Slight delay to reduce computation load
    end
end

realVelocityCalculation()