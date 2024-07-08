#!/bin/bash

# Check if a filename is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

FILENAME=$1
NEWFILENAME="new_file.csv"
DELETED_COUNT=0

# Use awk to process the file: replace "NULL" with blanks and identify rows that do not have 52 columns
awk -F'|' '
BEGIN { OFS = FS }
{
  # Replace "NULL" with blanks in all columns
  for (i = 1; i <= NF; i++) {
    if ($i == "NULL") $i = ""
  }
  
  # Print only rows with 52 columns to the new file
  if (NF == 52) {
    print $0
  } else {
    DELETED_COUNT++
  }
}
END {
  print DELETED_COUNT > "/dev/stderr"
}
' "$FILENAME" > "$NEWFILENAME"

# Always delete the second line if it exists
if [ $(wc -l < "$NEWFILENAME") -ge 2 ]; then
  sed -i '2d' "$NEWFILENAME"
  DELETED_COUNT=$((DELETED_COUNT + 1))
fi

# Print the number of deleted rows
DELETED_COUNT=$(awk 'END{print NR-1}' <<< "$DELETED_COUNT")
echo "Number of rows deleted: $DELETED_COUNT"
