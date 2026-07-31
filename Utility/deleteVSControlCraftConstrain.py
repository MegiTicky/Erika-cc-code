import os

# Get the script directory
script_dir = os.path.dirname(os.path.abspath(__file__))

# Find all matching files
matches = []
for root, dirs, files in os.walk(script_dir):
    for file in files:
        if file == "vscontrolcraft_Constrains.dat":
            matches.append(os.path.join(root, file))

# Display results
if not matches:
    print("No files named 'vscontrolcraft_Constrains.dat' found.")
else:
    print("Found the following files:")
    for path in matches:
        print(path)
    
    confirm = input("\nDo you want to delete all of these files? (y/n): ").strip().lower()
    if confirm == 'y':
        for path in matches:
            try:
                os.remove(path)
                print(f"Deleted: {path}")
            except Exception as e:
                print(f"Failed to delete {path}: {e}")
    else:
        print("Aborted. No files were deleted.")
