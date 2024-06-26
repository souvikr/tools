#!/bin/bash

# Check if a filename is provided
if [ $# -eq 0 ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

FILENAME=$1
LINE_NUMBERS_TO_DELETE=(2) # Always delete the second line
DELETED_COUNT=0

# Use awk to process the file: replace "NULL" with blanks and find the line numbers of rows that do not have 52 columns
awk -F'|' '{
  for (i = 1; i <= NF; i++) {
    if ($i == "NULL") $i = ""
  }
  if (NF != 52) {
    print NR
  } else {
    print $0
  }
}' OFS='|' "$FILENAME" > "$FILENAME.tmp"

# Read the temporary file to find lines to delete
awk -F'|' '{
  if (NF != 52) {
    print NR
  }
}' "$FILENAME.tmp" | while read -r line_number; do
  # Avoid adding the second line twice
  if [ "$line_number" -ne 2 ]; then
    LINE_NUMBERS_TO_DELETE+=("$line_number")
  fi
  DELETED_COUNT=$((DELETED_COUNT + 1))
done

# Update the deleted count if the second line is not already counted
if [ ${#LINE_NUMBERS_TO_DELETE[@]} -gt $DELETED_COUNT ]; then
  DELETED_COUNT=$((DELETED_COUNT + 1))
fi

# Check if any lines need to be deleted
if [ ${#LINE_NUMBERS_TO_DELETE[@]} -gt 0 ]; then
  # Use sed to delete the lines in one go
  sed -i.bak -e "$(printf '%sd;' "${LINE_NUMBERS_TO_DELETE[@]}")" "$FILENAME.tmp"
  mv "$FILENAME.tmp" "$FILENAME"
  echo "Number of rows deleted: $DELETED_COUNT"
else
  mv "$FILENAME.tmp" "$FILENAME"
  echo "No rows deleted. All rows have 52 columns."
fi
