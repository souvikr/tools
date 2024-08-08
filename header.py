# extract_headers.py
import pandas as pd
from config import files

def extract_headers(files):
    headers_dict = {}
    for key, file_path in files.items():
        try:
            df = pd.read_csv(file_path)
            headers = list(df.columns)
            headers_dict[key] = headers
        except FileNotFoundError:
            print(f"File {file_path} does not exist.")
        except pd.errors.EmptyDataError:
            print(f"File {file_path} is empty.")
    return headers_dict

def save_headers(headers_dict, output_file):
    with open(output_file, 'w') as f:
        f.write('headers = {\n')
        for key, headers in headers_dict.items():
            f.write(f"    '{key}': {headers},\n")
        f.write('}\n')

def main():
    headers_dict = extract_headers(files)
    save_headers(headers_dict, 'headers.py')

if __name__ == '__main__':
    main()
