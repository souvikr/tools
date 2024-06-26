#!/bin/bash

# Check if a filename is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

FILENAME=$1
TEMPFILE=$(mktemp)
DELETED_COUNT=0

# Use awk to process the file: replace "NULL" with blanks and identify rows that do not have 52 columns
awk -F'|' '
BEGIN { OFS = FS }
{
  # Replace "NULL" with blanks in all columns
  for (i = 1; i <= NF; i++) {
    if ($i == "NULL") $i = ""
  }
  
  # Print only rows with 52 columns to the temp file
  if (NF == 52) {
    print $0 > "'$TEMPFILE'"
  } else {
    DELETED_COUNT++
  }
}
END {
  print DELETED_COUNT > "/dev/stderr"
}
' "$FILENAME" 2> deleted_count.txt

# Always delete the second line if it exists
if [ $(wc -l < "$TEMPFILE") -ge 2 ]; then
  sed -i '2d' "$TEMPFILE"
  DELETED_COUNT=$((DELETED_COUNT + 1))
fi

# Move the temp file back to the original file
mv "$TEMPFILE" "$FILENAME"

# Print the number of deleted rows
DELETED_COUNT=$(<deleted_count.txt)
echo "Number of rows deleted: $DELETED_COUNT"
rm deleted_count.txt
