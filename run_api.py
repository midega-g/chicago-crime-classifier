#!/usr/bin/env python3
"""
Simple script to run the Chicago Crime Prediction API
"""
import sys
import subprocess
from pathlib import Path

def main():
    # Get the project root directory
    project_root = Path(__file__).parent
    api_script = project_root / "src" / "predict-api.py"
    
    if not api_script.exists():
        print(f"Error: API script not found at {api_script}")
        sys.exit(1)
    
    print("Starting Chicago Crime Prediction API...")
    print("Access the web interface at: http://localhost:8000")
    print("Press Ctrl+C to stop the server")
    print("-" * 50)
    
    try:
        # Run the API script
        subprocess.run([sys.executable, str(api_script)], cwd=str(project_root))
    except KeyboardInterrupt:
        print("\nAPI server stopped.")
    except Exception as e:
        print(f"Error running API: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()