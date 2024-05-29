import requests
import zipfile
import os
import sys

def download_file(url, file_name):
    try:
        # Send a HTTP request to the URL
        response = requests.get(url)
        
        # Check if the request was successful
        if response.status_code == 200:
            # Open a file in write-binary mode and write the response content
            with open(file_name, 'wb') as file:
                file.write(response.content)
            print(f'File saved as {file_name}')
        else:
            print(f'Failed to retrieve file: HTTP Status Code {response.status_code}')
    except Exception as e:
        print(f'An error occurred: {e}')

def extract_csv_from_zip(zip_file, output_dir, final_csv_name):
    try:
        with zipfile.ZipFile(zip_file, 'r') as z:
            # Extract all contents to the output directory
            z.extractall(output_dir)
            # Find the CSV file and rename it
            for file in z.namelist():
                if file.endswith('.csv'):
                    extracted_csv_path = os.path.join(output_dir, file)
                    final_csv_path = os.path.join(output_dir, final_csv_name)
                    os.rename(extracted_csv_path, final_csv_path)
                    print(f'CSV file saved as {final_csv_name}')
                    return
            raise Exception("No CSV file found in the zip archive")
    except Exception as e:
        print(f'An error occurred while extracting the CSV: {e}')

def main():
    if len(sys.argv) != 2:
        print("Usage: python gleif_automation.py YYYYMMDD")
        return

    date = sys.argv[1]

    if len(date) != 8 or not date.isdigit():
        print("Date must be in the format YYYYMMDD")
        return

    # URL and file names based on the provided date
    url = f'https://goldencopy.gleif.org/api/v2/golden-copies/publishes/lei2/{date}-0000.csv'
    zip_file_name = f'lei2_{date}-0000.zip'
    output_dir = '.'
    final_csv_name = 'gleif-goldencopy-lei2-golden-copy.csv'

    # Download the ZIP file
    download_file(url, zip_file_name)

    # Extract the CSV file and rename it
    extract_csv_from_zip(zip_file_name, output_dir, final_csv_name)

if __name__ == "__main__":
    main()