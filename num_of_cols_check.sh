#!/bin/bash

# Input file name
INPUT_FILE="input.csv"

# Output file for rows that do not have 52 columns
OUTPUT_FILE="invalid_rows.txt"

# Temporary directory for storing chunk results
TEMP_DIR="temp_results"
mkdir -p "$TEMP_DIR"

# Number of lines per chunk
LINES_PER_CHUNK=1000000

# Split the input file into smaller chunks
split -l $LINES_PER_CHUNK "$INPUT_FILE" chunk_

# Function to process a chunk
process_chunk() {
  local chunk_file=$1
  local temp_output="${TEMP_DIR}/${chunk_file}.out"

  awk -F'|' 'NF != 52 {print FNR}' "$chunk_file" > "$temp_output"
}

export -f process_chunk
export TEMP_DIR

# Use GNU Parallel to process chunks in parallel
ls chunk_* | parallel process_chunk {}

# Combine the results from all chunks into the final output file
cat ${TEMP_DIR}/chunk_*.out > "$OUTPUT_FILE"

# Clean up temporary files
rm -r "$TEMP_DIR"
rm chunk_*

echo "Check completed. Invalid rows (if any) are listed in $OUTPUT_FILE."
