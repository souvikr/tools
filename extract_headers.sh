#!/bin/bash

# Define the output Python file
output_file="headers.py"

# Start the Python dictionary
echo "required_columns = {" > $output_file

# Loop through each CSV file
for csv_file in file*.csv; do
    # Get the filename without the extension
    filename=$(basename "$csv_file" .csv)

    # Extract the header from the CSV file
    header=$(head -n 1 "$csv_file")

    # Convert the header to a Python list format with single quotes
    header_list=$(echo "$header" | awk -v RS=',' '{print "'"'" $0 "'"'" }' | paste -sd "," - | sed 's/,/, /g')

    # Append the filename and header list to the Python dictionary
    echo "    '$filename': [$header_list]," >> $output_file
done

# End the Python dictionary
echo "}" >> $output_file

# Print the size of each list
python3 - <<EOF
import headers

for key, value in headers.required_columns.items():
    print(f"{key}: {len(value)} columns")
EOF
