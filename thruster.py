import itertools
import numpy as np

def is_valid_configuration(grid, x, y, z):
    """ Check if every thruster has at least one adjacent redstone link """
    directions = [(-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)]
    for i in range(x):
        for j in range(y):
            for k in range(z):
                if grid[i, j, k] == "T":
                    # Check if there is at least one adjacent redstone link
                    has_redstone_link = False
                    for dx, dy, dz in directions:
                        ni, nj, nk = i + dx, j + dy, k + dz
                        if 0 <= ni < x and 0 <= nj < y and 0 <= nk < z and grid[ni, nj, nk] == "R":
                            has_redstone_link = True
                            break
                    if not has_redstone_link:
                        return False
    return True

def max_thrusters_configuration(x, y, z):
    """ Find the configuration with the maximum thrusters and valid redstone link adjacency """
    max_thrusters = 0
    best_configuration = None
    
    # Iterate over all possible configurations
    for config in itertools.product("TR", repeat=x*y*z):
        grid = np.array(config).reshape((x, y, z))
        
        # Count the number of thrusters in this configuration
        thruster_count = np.sum(grid == "T")
        
        # Check if the configuration is valid and update the best configuration if it has more thrusters
        if thruster_count > max_thrusters and is_valid_configuration(grid, x, y, z):
            max_thrusters = thruster_count
            best_configuration = grid
    
    return max_thrusters, best_configuration

# Input grid size from user
x = int(input("Enter the x dimension: "))
y = int(input("Enter the y dimension: "))
z = int(input("Enter the z dimension: "))

# Get the best configuration
max_thrusters, best_configuration = max_thrusters_configuration(x, y, z)

# Output the result
print(f"Maximum number of thrusters: {max_thrusters}")
print("Best configuration:")
print(best_configuration)
