local engine = peripheral.wrap("front")
local left = peripheral.wrap("left")
local right = peripheral.find("Create_RotationSpeedController")
local suspensionMotor = peripheral.find("electric_motor")

local function pullFuel()
    while true do
        engine.pullFluid("back",20,"createdieselgenerators:biodiesel")
        print("fuelPulled")
        sleep(1)
    end
end

parallel.waitForAny(
    pullFuel
)