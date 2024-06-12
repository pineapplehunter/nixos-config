#!/usr/bin/env python3

import sys
import zipfile

def main():
    # Check if the archive path and output path were passed as arguments
    if len(sys.argv) != 3:
        print('Usage: {} archive_path output_path'.format(sys.argv[0]))
        sys.exit(1)

    # Check if the file exists inside the archive
    with zipfile.ZipFile(sys.argv[1], 'r') as archive:
        if 'Metadata/thumbnail.png' in archive.namelist():
            # Extract the file to standard output without preserving the folder structure and save it to the specified output path
            with archive.open('Metadata/thumbnail.png', 'r') as thumbnail:
                with open(sys.argv[2], 'wb') as output:
                    output.write(thumbnail.read())
            print('File extracted successfully')
        else:
            # Exit with an error message
            print("File 'Metadata/thumbnail.png' doesn't exist inside the archive")
            sys.exit(1)


if __name__ == '__main__':
    main()