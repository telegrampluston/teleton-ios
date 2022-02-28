import os
import pathlib
import sys
import zipfile
import glob

def last_modified(s):
    return os.stat(s).st_mtime

if __name__ == '__main__':
    bazel_out_path = os.path.abspath(os.path.join(os.path.dirname( __file__ ), '..', 'bazel-out'))
    subfolders = [ f.path for f in os.scandir(bazel_out_path) if f.is_dir() and f.name.startswith('applebin_ios-ios_armv7')]
    subfolders.sort(key=last_modified, reverse=True)
    dsym_path = os.path.abspath(os.path.join(subfolders[0], 'bin', 'Telegram'))
    sys.stdout.write(dsym_path)
    sys.exit(0)
