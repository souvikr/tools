#!/bin/bash

# Input file name
INPUT_FILE="input.txt"

# Output file for rows that do not have 52 columns
OUTPUT_FILE="invalid_rows.txt"

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Use awk to check each row
awk -F'|' 'NF != 52 {print NR}' "$INPUT_FILE" > "$OUTPUT_FILE"

echo "Check completed. Invalid rows (if any) are listed in $OUTPUT_FILE."
