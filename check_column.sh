#!/bin/bash

# Check if a file name was provided
if [ $# -eq 0 ]; then
    echo "Please provide a CSV file name as an argument."
    exit 1
fi

# Store the file name
file="$1"

# Check if the file exists
if [ ! -f "$file" ]; then
    echo "File not found: $file"
    exit 1
fi

# Extract the 3rd column and check values
awk -F',' '{
    if (NR > 1) {  # Skip the header row
        if ($3 != "ACTIVE" && $3 != "INACTIVE") {
            print "Invalid value in row " NR ": " $3
        }
    }
}' "$file"

echo "Validation complete."
