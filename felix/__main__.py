"""
Entry point for running Felix as a module: python -m felix
"""

import sys

from felix.cli import main

if __name__ == "__main__":
    sys.exit(main())
