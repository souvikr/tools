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
        echo "Headers are identical for $diff_file."
    else
        echo "Headers are different for $diff_file." > "$diff_file"
        echo "File 1 header: $header1" >> "$diff_file"
        echo "File 2 header: $header2" >> "$diff_file"
    fi
}

# Check if exactly three arguments (folder paths) are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 folder1 folder2 output_folder"
    exit 1
fi

# Assign folder paths to variables
folder1=$1
folder2=$2
output_folder=$3

# Check if both folders exist
if [ ! -d "$folder1" ] || [ ! -d "$folder2" ]; then
    echo "Both folders must exist."
    exit 1
fi

# Create output folder if it doesn't exist
mkdir -p "$output_folder"

# Iterate over CSV files in folder1
for file1 in "$folder1"/*.csv; do
    # Get the filename without the folder path
    filename=$(basename "$file1")
    file2="$folder2/$filename"
    diff_file="$output_folder/${filename%.csv}_diff.txt"

    # Check if the corresponding file exists in folder2
    if [ ! -f "$file2" ]; then
        echo "File $file2 does not exist."
        continue
    fi

    # Get headers of both files
    header1=$(get_header "$file1")
    header2=$(get_header "$file2")

    # Compare headers and output differences to a file
    compare_headers "$header1" "$header2" "$diff_file"
done
