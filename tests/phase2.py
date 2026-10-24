"""Compatibility entry point for the complete Phase 2 test suite."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('validate.py')), run_name='__main__')
