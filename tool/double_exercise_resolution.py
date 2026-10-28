#!/usr/bin/env python3
"""Doubles the resolution of exercise thumbnails from 192x128 to 384x256 by
downloading original photos from yuhonas/free-exercise-db and resizing with Lanczos.
"""
import concurrent.futures
import io
import os
import re
import sys
import urllib.request
from PIL import Image

TARGET_SIZE = (384, 256)
BASE_URL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises"

def process_image(entry):
    filepath, ex_id, frame = entry
    url = f"{BASE_URL}/{ex_id}/{frame}.jpg"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
        img = Image.open(io.BytesIO(data))
        # Ensure RGB
        if img.mode != 'RGB':
            img = img.convert('RGB')
        # Resize to 384x256
        resized = img.resize(TARGET_SIZE, Image.Resampling.LANCZOS)
        resized.save(filepath, "JPEG", quality=88)
        return True, ex_id, frame
    except Exception as e:
        return False, ex_id, f"{frame}: {e}"

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    assets_dir = os.path.join(root, "assets", "exercises")
    if not os.path.isdir(assets_dir):
        print(f"Directory {assets_dir} not found.")
        sys.exit(1)

    pattern = re.compile(r"^(.+)_(0|1)\.jpg$")
    tasks = []
    for fname in os.listdir(assets_dir):
        m = pattern.match(fname)
        if m:
            ex_id = m.group(1)
            frame = m.group(2)
            filepath = os.path.join(assets_dir, fname)
            tasks.append((filepath, ex_id, frame))

    print(f"Found {len(tasks)} exercise images to update to {TARGET_SIZE[0]}x{TARGET_SIZE[1]}.")

    completed = 0
    errors = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(process_image, t): t for t in tasks}
        for future in concurrent.futures.as_completed(futures):
            success, ex_id, msg = future.result()
            completed += 1
            if not success:
                errors += 1
                if errors <= 10:
                    print(f"Error for {ex_id}: {msg}")
            if completed % 100 == 0 or completed == len(tasks):
                print(f"Progress: {completed}/{len(tasks)} (errors: {errors})")

    print(f"Finished. Total: {completed}, Errors: {errors}")

if __name__ == '__main__':
    main()
