#!/bin/bash

# Input file name
INPUT_FILE="input.csv"

# Extract the base name of the input file (without the path and extension)
BASE_NAME=$(basename "$INPUT_FILE" .csv)

# Output file name with input file name appended
OUTPUT_FILE="${BASE_NAME}_invalid_rows.txt"

# Temporary directory for storing chunk results
TEMP_DIR="temp_results"
mkdir -p "$TEMP_DIR"

# Number of lines per chunk
LINES_PER_CHUNK=1000000

# Clear the output file if it exists
> "$OUTPUT_FILE"

# Split the input file into smaller chunks
split -l $LINES_PER_CHUNK "$INPUT_FILE" chunk_

# Function to process a chunk
process_chunk() {
  local chunk_file=$1
  local temp_output="${TEMP_DIR}/${chunk_file}.out"

  awk -F'|' '{
    if (NF != 52) {
      print "Row " FNR ": " NF " columns"
    }
  }' "$chunk_file" > "$temp_output"
}

# Process each chunk sequentially
for chunk_file in chunk_*; do
  process_chunk "$chunk_file"
done

# Combine the results from all chunks into the final output file
cat ${TEMP_DIR}/chunk_*.out > "$OUTPUT_FILE"

# Clean up temporary files
rm -r "$TEMP_DIR"
rm chunk_*

echo "Check completed. Invalid rows (if any) are listed in $OUTPUT_FILE."
