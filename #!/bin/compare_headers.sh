#!/bin/bash

# Function to get the header of a CSV file
get_header() {
    local file=$1
    head -n 1 "$file"
}

# Function to compare headers and output differences to a file
compare_headers() {
    local header1=$1
    local header2=$2
    local diff_file=$3

    if [ "$header1" == "$header2" ]; then
        echo "Headers are identical."
    else
        echo "Headers are different." > "$diff_file"
        echo "File 1 header: $header1" >> "$diff_file"
        echo "File 2 header: $header2" >> "$diff_file"
    fi
}

# Check if exactly three arguments (file paths) are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 file1.csv file2.csv diff_output.txt"
    exit 1
fi

# Assign file paths to variables
file1=$1
file2=$2
diff_file=$3

# Check if both files exist
if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
    echo "Both files must exist."
    exit 1
fi

# Get headers of both files
header1=$(get_header "$file1")
header2=$(get_header "$file2")

# Compare headers and output differences to a file
compare_headers "$header1" "$header2" "$diff_file"
