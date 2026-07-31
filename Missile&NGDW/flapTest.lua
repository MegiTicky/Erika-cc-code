local topFlap = peripheral.wrap("top")
local bottomFlap = peripheral.wrap("bottom")
local leftFlap = peripheral.wrap("back")
local rightFlap = peripheral.wrap("front")

topFlap.setAngle(0)
leftFlap.setAngle(0)
bottomFlap.setAngle(0)
rightFlap.setAngle(0)

local function PID(Kp, Ki, Kd, error, integral, prev_error, dt, min_out, max_out)
    -- Safety check for dt
    if dt <= 0 then dt = 0.05 end
    
    -- Proportional term
    local P = Kp * error
    
    -- Integral term (accumulate)
    integral = integral + error * dt
    local I = Ki * integral
    
    -- Derivative term
    local derivative = (error - prev_error) / dt
    local D = Kd * derivative
    
    -- Total output
    local output = P + I + D
    
    -- Clamp output if limits are provided
    if min_out and max_out then
        output = math.max(min_out, math.min(max_out, output))
    end
    
    -- Return output and updated state for next call
    return output, integral, error
end

while true do
    rollError = 