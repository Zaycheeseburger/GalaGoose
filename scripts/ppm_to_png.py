import glob, os
import numpy as np
from PIL import Image

SIM_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sim_work")

for ppm_path in sorted(glob.glob(os.path.join(SIM_DIR, "*.ppm"))):
    with open(ppm_path, "r") as f:
        tokens = f.read().split()
    assert tokens[0] == "P3", f"Bad header in {ppm_path}"
    w, h, maxv = int(tokens[1]), int(tokens[2]), int(tokens[3])
    vals = np.array(tokens[4:], dtype=np.uint8).reshape(h, w, 3)
    rgb = (vals.astype(np.uint16) * 255 // maxv).astype(np.uint8)
    png_path = os.path.splitext(ppm_path)[0] + ".png"
    Image.fromarray(rgb).save(png_path)
    print("Converted", os.path.basename(png_path))
