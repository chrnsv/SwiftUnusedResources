import os
import shutil
import zipfile
import json
from sys import argv
from argparse import ArgumentParser

def create_artifact_bundle(sur_executable_path, version):
    # Define paths
    bundle_name = f"sur-{version}.artifactbundle"
    bundle_dir = f"{bundle_name}_bundle"
    sur_dest_path = os.path.join(bundle_dir, "bin", "sur")
    
    # Create bundle directory structure
    os.makedirs(os.path.dirname(sur_dest_path), exist_ok=True)
    
    # Copy the sur executable to the bundle
    shutil.copy(sur_executable_path, sur_dest_path)
    
    # Create an info.json file
    info_path = os.path.join(bundle_dir, "info.json")
    metadata = {
        "schemaVersion": "1.0",
        "artifacts": {
            "sur": {
                "version": version,
                "type": "executable",
                "variants": [
                    {
                        "path": "bin/sur",
                        "supportedTriples": ["x86_64-apple-macosx", "arm64-apple-macosx"]
                    }
                ]
            }
        }
    }
    with open(info_path, "w") as info_file:
        json.dump(metadata, info_file, indent=4)
    
    # Compress the bundle into a zip file
    bundle_zip_path = f"{bundle_name}.zip"
    with zipfile.ZipFile(bundle_zip_path, 'w', zipfile.ZIP_DEFLATED) as bundle_zip:
        for root, _, files in os.walk(bundle_dir):
            for file in files:
                file_path = os.path.join(root, file)
                bundle_zip.write(file_path, os.path.relpath(file_path, bundle_dir))
    
    # Clean up the temporary bundle directory
    shutil.rmtree(bundle_dir)
    
    print(f"Artifact bundle created: {bundle_zip_path}")

def parse_arguments(args):
    parser = ArgumentParser(description="Create an artifact bundle for the sur executable")
    
    parser.add_argument("-e", "--executable", help="The path to the sur executable")
    parser.add_argument("-v", "--version", help="The version of the sur executable")
    
    return parser.parse_args(args)

def main():
    args = parse_arguments(argv[1:])
    create_artifact_bundle(args.executable, args.version)
    
if __name__ == '__main__':
    main()
