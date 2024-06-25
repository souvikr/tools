#!/bin/bash

# Input file name
INPUT_FILE="input.csv"

# Output file for rows that do not have 52 columns
OUTPUT_FILE="invalid_rows.txt"

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Use awk to check each row and include the number of columns
awk -F'|' '
{
  if (NF != 52) {
    print "Row " NR ": " NF " columns" > "'$OUTPUT_FILE'"
  }
}
' "$INPUT_FILE"

echo "Check completed. Invalid rows (if any) are listed in $OUTPUT_FILE."
