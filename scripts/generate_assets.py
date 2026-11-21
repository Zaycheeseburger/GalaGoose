import os
import math
import shutil
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "Space_shooter_source")
MEM_DIR = os.path.join(ROOT, "mem")
SIM_DIR = os.path.join(ROOT, "sim_work")

os.makedirs(MEM_DIR, exist_ok=True)
os.makedirs(SIM_DIR, exist_ok=True)


def rgb888_to_444(r, g, b):
    return ((int(r) >> 4) << 8) | ((int(g) >> 4) << 4) | (int(b) >> 4)


def quantize_444(r, g, b):
    r4 = (int(r) >> 4) * 17
    g4 = (int(g) >> 4) * 17
    b4 = (int(b) >> 4) * 17
    return (r4, g4, b4)


# ---------------------------------------------------------------------------
# 1. Fixed Arcade Palette (Indices 0..47)
# ---------------------------------------------------------------------------
FIXED_PALETTE = {
    0: (0, 0, 0),         # Transparent
    1: (22, 24, 34),      # Goose dark outline (#161822)
    2: (255, 252, 240),   # Goose white body
    3: (200, 194, 178),   # Goose gray shadow
    4: (238, 162, 58),    # Goose orange beak/feet
    5: (192, 118, 36),    # Goose dark orange beak/feet
    6: (255, 255, 96),    # Thruster core yellow
    7: (255, 112, 24),    # Thruster outer orange
    # Form 2: Blue Goose
    8: (48, 208, 255),    # Blue goose bright cyan-blue
    9: (16, 112, 224),    # Blue goose shadow royal blue
    # Form 3: 8-color Rainbow spectrum (indices 16..23)
    16: (255, 48, 64),    # Red
    17: (255, 144, 32),   # Orange
    18: (255, 240, 48),   # Yellow
    19: (48, 240, 96),    # Green
    20: (32, 232, 255),   # Cyan
    21: (64, 128, 255),   # Blue
    22: (168, 64, 255),   # Purple
    23: (255, 64, 208),   # Magenta
    # Arcade UI / Galaga / FX colors (24..47)
    24: (255, 255, 255),  # Pure White
    25: (0, 255, 255),    # Pure Cyan
    26: (48, 144, 255),   # Sky Blue
    27: (16, 48, 176),    # Deep Blue
    28: (255, 32, 32),    # Bright Red
    29: (160, 16, 24),    # Dark Red
    30: (255, 144, 16),   # Bright Orange
    31: (255, 240, 32),   # Bright Yellow
    32: (48, 240, 80),    # Bright Green
    33: (16, 128, 48),    # Dark Green
    34: (255, 64, 224),   # Hot Pink / Magenta
    35: (144, 32, 224),   # Violet
    36: (255, 208, 32),   # Gold
    37: (192, 200, 216),  # Silver
    38: (80, 88, 112),    # Steel Gray
    39: (16, 16, 24),     # Solid Outline Black (non-zero!)
    40: (255, 176, 192),  # Light Pink
    41: (128, 255, 208),  # Mint
}
# Fill unused slots 10..15, 42..47 with dark neutral
for idx in range(48):
    if idx not in FIXED_PALETTE:
        FIXED_PALETTE[idx] = (16, 16, 24)


# ---------------------------------------------------------------------------
# 2. Goose Sprite Extraction (23x23 grid -> 32x32 x 2 animation frames)
# ---------------------------------------------------------------------------
def build_goose_frames():
    im = np.array(Image.open(os.path.join(SRC_DIR, "goose.jpg")).convert("RGB"))
    # Sample center of each 32x32 block (23x23)
    grid = im[16::32, 16::32]  # shape (23, 23, 3)
    assert grid.shape[:2] == (23, 23), f"Unexpected grid shape {grid.shape}"

    def classify_pixel(rgb):
        r, g, b = int(rgb[0]), int(rgb[1]), int(rgb[2])
        # Teal background [8, 165, 122] and ground shadow [13, 108, 86]
        if g > r + 40 and g > 85:
            return 0  # transparent
        # Dark outline [26, 29, 41]
        if r < 65 and g < 65 and b < 75:
            return 1
        # Orange beak/feet
        if r > 180 and g > 100 and b < 110:
            if g > 150:
                return 4
            return 5
        # Warm white vs gray shadow
        if r > 225 and g > 220 and b > 200:
            return 2
        if r > 150 and g > 145 and b > 120:
            return 3
        return 1

    base = np.zeros((32, 32), dtype=np.uint8)
    ox, oy = 4, 4  # center 23x23 inside 32x32 (x: 4..26, y: 4..26)
    for y in range(23):
        for x in range(23):
            # Remove bottom ground shadow row (row 20..21 where teal shadow exists)
            c = classify_pixel(grid[y, x])
            # Also explicitly suppress any lone green-ish pixels
            r, g, b = int(grid[y, x][0]), int(grid[y, x][1]), int(grid[y, x][2])
            if g > r + 25 and b > r + 15:
                c = 0
            base[oy + y, ox + x] = c

    # Frame 0: Base goose + twin space thrusters tucked under feet
    f0 = base.copy()
    for fx in [12, 13, 19, 20]:
        f0[26, fx] = 6
        f0[27, fx] = 7

    # Frame 1: Slight wing/bob + longer animated thruster flame
    f1 = np.zeros((32, 32), dtype=np.uint8)
    f1[0:31, :] = base[1:32, :]  # subtle 1px hover bob
    for fx in [12, 13, 19, 20]:
        f1[25, fx] = 6
        f1[26, fx] = 6
        f1[27, fx] = 7
        f1[28, fx] = 7
    f1[27, 11] = 7
    f1[27, 21] = 7

    return [f0, f1]


# ---------------------------------------------------------------------------
# 3. Face Extraction + GrabCut Background Removal
# ---------------------------------------------------------------------------
def _smooth_closed_poly(pts, samples_per_seg=12):
    """Catmull-Rom closed spline interpolation for smooth curved head/jaw contours."""
    n = len(pts)
    out = []
    for i in range(n):
        p0 = pts[(i - 1) % n]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n]
        for s in range(samples_per_seg):
            t = s / float(samples_per_seg)
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t +
                       (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 +
                       (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t +
                       (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 +
                       (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return np.array(out, dtype=np.int32)


def extract_face_rgba(filename, crop_box_frac, ellipse_center_frac, ellipse_axes_frac,
                      bg_color_hint=None, boost_brightness=1.0, boost_contrast=1.0,
                      target_size=32, border_color=(24, 28, 48),
                      tilt_deg=0.0, gamma=1.0, fgd_thresh=0.52, pr_fgd_thresh=0.95,
                      collar_mode=None, use_clahe_seg=False, mask_blur=0,
                      poly_frac=None, hair_grabcut_y_frac=0.55,
                      use_alpha_mask=False):
    """
    Loads portrait image, crops to head/face region, runs GrabCut + refinement
    (or curved anatomical contour + hair GrabCut when poly_frac is supplied,
    or uses existing alpha channel when use_alpha_mask is True)
    to cleanly remove background and shirt/shoulders, adds subtle dark outline,
    and resizes cleanly to target_size x target_size RGBA.
    """
    path = os.path.join(SRC_DIR, filename)
    if use_alpha_mask:
        pil_im = Image.open(path)
        if pil_im.mode != "RGBA":
            pil_im = pil_im.convert("RGBA")
        arr = np.array(pil_im)
        alpha = arr[:, :, 3]
        ys, xs = np.where(alpha > 20)
        if len(xs) > 0 and len(ys) > 0:
            bx0, bx1 = xs.min(), xs.max() + 1
            by0, by1 = ys.min(), ys.max() + 1
            cropped = pil_im.crop((bx0, by0, bx1, by1))
        else:
            cropped = pil_im

        if boost_brightness != 1.0:
            rgb = ImageEnhance.Brightness(cropped.convert("RGB")).enhance(boost_brightness)
            cropped = Image.merge("RGBA", (*rgb.split(), cropped.split()[3]))
        if boost_contrast != 1.0:
            rgb = ImageEnhance.Contrast(cropped.convert("RGB")).enhance(boost_contrast)
            cropped = Image.merge("RGBA", (*rgb.split(), cropped.split()[3]))

        inner = target_size - 2
        bw, bh = cropped.size
        fit_scale = min(inner / bw, inner / bh)
        nw = max(1, int(round(bw * fit_scale)))
        nh = max(1, int(round(bh * fit_scale)))
        pil_small = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

        canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
        px = (target_size - nw) // 2
        py = (target_size - nh) // 2
        canvas.paste(pil_small, (px, py))

        arr_c = np.array(canvas)
        alpha_c = arr_c[:, :, 3] > 110
        arr_c[:, :, 3] = np.where(alpha_c, 255, 0)

        padded = np.pad(alpha_c, 1, mode="constant", constant_values=False)
        dilated = (
            padded[:-2, 1:-1] | padded[2:, 1:-1] |
            padded[1:-1, :-2] | padded[1:-1, 2:]
        )
        outline = dilated & (~alpha_c)
        arr_c[outline, 0] = border_color[0]
        arr_c[outline, 1] = border_color[1]
        arr_c[outline, 2] = border_color[2]
        arr_c[outline, 3] = 255

        return Image.fromarray(arr_c, "RGBA")

    pil_im = Image.open(path).convert("RGB")
    w, h = pil_im.size
    x0 = int(crop_box_frac[0] * w)
    y0 = int(crop_box_frac[1] * h)
    x1 = int(crop_box_frac[2] * w)
    y1 = int(crop_box_frac[3] * h)
    cropped = pil_im.crop((x0, y0, x1, y1))

    if gamma != 1.0:
        arr_g = np.asarray(cropped, dtype=np.float32) / 255.0
        arr_g = np.clip((arr_g ** gamma) * 255.0, 0, 255).astype(np.uint8)
        cropped = Image.fromarray(arr_g, "RGB")
    if boost_brightness != 1.0:
        cropped = ImageEnhance.Brightness(cropped).enhance(boost_brightness)
    if boost_contrast != 1.0:
        cropped = ImageEnhance.Contrast(cropped).enhance(boost_contrast)

    # Work at reasonable resolution (~256px) for accurate GrabCut
    cw, ch = cropped.size
    scale = 256.0 / max(cw, ch)
    rw, rh = max(64, int(cw * scale)), max(64, int(ch * scale))
    work_rgb = np.array(cropped.resize((rw, rh), Image.Resampling.LANCZOS))
    work_bgr = cv2.cvtColor(work_rgb, cv2.COLOR_RGB2BGR)

    seg_bgr = work_bgr
    if use_clahe_seg:
        lab = cv2.cvtColor(work_bgr, cv2.COLOR_BGR2LAB)
        l_ch, a_ch, b_ch = cv2.split(lab)
        clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
        seg_bgr = cv2.cvtColor(cv2.merge([clahe.apply(l_ch), a_ch, b_ch]), cv2.COLOR_LAB2BGR)

    if poly_frac is not None:
        # Map full-image normalized coordinates into cropped working canvas
        poly_px = [
            ((px - crop_box_frac[0]) / (crop_box_frac[2] - crop_box_frac[0]) * rw,
             (py - crop_box_frac[1]) / (crop_box_frac[3] - crop_box_frac[1]) * rh)
            for (px, py) in poly_frac
        ]
        smooth_pts = _smooth_closed_poly(poly_px, samples_per_seg=10)
        poly_mask = np.zeros((rh, rw), dtype=np.uint8)
        cv2.fillPoly(poly_mask, [smooth_pts], 255)

        # Refine top hair boundary with GrabCut while preserving smooth cheek/chin/jaw contour
        mask = np.full((rh, rw), cv2.GC_BGD, dtype=np.uint8)
        k_erode = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
        k_dilate = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
        inner_core = cv2.erode(poly_mask, k_erode, iterations=1)
        outer_band = cv2.dilate(poly_mask, k_dilate, iterations=1)
        hair_y_px = int(hair_grabcut_y_frac * rh)

        # Lower face/jaw/cheek: lock closely to curved spline contour so skin highlights never notch
        mask[poly_mask > 0] = cv2.GC_FGD
        # Upper hair/ears band: let GrabCut trace natural hair silhouette
        upper_band = (outer_band > 0) & (inner_core == 0)
        upper_band[hair_y_px:, :] = False
        mask[upper_band] = cv2.GC_PR_FGD

        bgd_model = np.zeros((1, 65), np.float64)
        fgd_model = np.zeros((1, 65), np.float64)
        cv2.grabCut(seg_bgr, mask, None, bgd_model, fgd_model, 5, cv2.GC_INIT_WITH_MASK)
        fg_mask = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
        # Guarantee smooth lower jawline/chin & never exceed outer_band
        fg_mask[hair_y_px:, :] = poly_mask[hair_y_px:, :]
        fg_mask[outer_band == 0] = 0
    else:
        mask = np.full((rh, rw), cv2.GC_PR_BGD, dtype=np.uint8)
        # Mark outer margin as definite background
        m = max(3, int(0.03 * min(rw, rh)))
        mask[:m, :] = cv2.GC_BGD
        mask[-m:, :] = cv2.GC_BGD
        mask[:, :m] = cv2.GC_BGD
        mask[:, -m:] = cv2.GC_BGD

        if collar_mode is None:
            # Mark bottom-left & bottom-right corners (shoulders/collar area) as definite BGD
            mask[int(0.84 * rh):, :int(0.18 * rw)] = cv2.GC_BGD
            mask[int(0.84 * rh):, int(0.82 * rw):] = cv2.GC_BGD

        # Rotated elliptical head prior: inner ellipse = definite FGD, outer = probable FGD
        cx = float(ellipse_center_frac[0] * rw)
        cy = float(ellipse_center_frac[1] * rh)
        ax = max(1.0, float(ellipse_axes_frac[0] * rw))
        ay = max(1.0, float(ellipse_axes_frac[1] * rh))

        yy, xx = np.ogrid[:rh, :rw]
        dx = xx - cx
        dy = yy - cy
        if tilt_deg != 0.0:
            rad = math.radians(tilt_deg)
            c_a, s_a = math.cos(rad), math.sin(rad)
            rx = dx * c_a + dy * s_a
            ry = -dx * s_a + dy * c_a
        else:
            rx, ry = dx, dy
        dist_norm = (rx / ax) ** 2 + (ry / ay) ** 2
        mask[dist_norm <= pr_fgd_thresh] = cv2.GC_PR_FGD
        mask[dist_norm <= fgd_thresh] = cv2.GC_FGD

        # If pure white/light uniform background hint is given, pre-mark very bright outer pixels as BGD
        if bg_color_hint == "white":
            bright = (work_rgb[:, :, 0] > 238) & (work_rgb[:, :, 1] > 238) & (work_rgb[:, :, 2] > 238)
            mask[bright & (dist_norm > 0.72)] = cv2.GC_BGD
        elif bg_color_hint == "light_studio":
            gray = work_rgb.mean(axis=2)
            sat = work_rgb.max(axis=2) - work_rgb.min(axis=2)
            bg_cand = (gray > 180) & (sat < 35) & (dist_norm > 0.78)
            mask[bg_cand] = cv2.GC_BGD

        bgd_model = np.zeros((1, 65), np.float64)
        fgd_model = np.zeros((1, 65), np.float64)
        cv2.grabCut(seg_bgr, mask, None, bgd_model, fgd_model, 6, cv2.GC_INIT_WITH_MASK)

        fg_mask = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)

    # Keep only the largest connected component (the head!)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(fg_mask, connectivity=8)
    if num_labels > 1:
        # Find component closest to center with large area
        best_lbl = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        fg_mask = np.where(labels == best_lbl, 255, 0).astype(np.uint8)

    # Smooth mask edges slightly & fill internal holes
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    fg_mask = cv2.morphologyEx(fg_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    if mask_blur > 0:
        fg_mask = cv2.GaussianBlur(fg_mask, (mask_blur, mask_blur), 0)
        fg_mask = np.where(fg_mask > 120, 255, 0).astype(np.uint8)
    # Fill holes using floodfill from border on inverted mask
    inv = cv2.bitwise_not(fg_mask)
    h_ff, w_ff = inv.shape
    ff_mask = np.zeros((h_ff + 2, w_ff + 2), np.uint8)
    cv2.floodFill(inv, ff_mask, (0, 0), 0)
    fg_mask = cv2.bitwise_or(fg_mask, inv)

    # Trim tightly to foreground bounding box and fit nicely into (target_size - 2) inside target_size
    ys, xs = np.where(fg_mask > 0)
    if len(xs) > 0 and len(ys) > 0:
        bx0, bx1 = xs.min(), xs.max() + 1
        by0, by1 = ys.min(), ys.max() + 1
        rgba_hi = np.dstack([work_rgb, fg_mask])[by0:by1, bx0:bx1]
    else:
        rgba_hi = np.dstack([work_rgb, fg_mask])

    pil_hi = Image.fromarray(rgba_hi, "RGBA")
    inner = target_size - 2
    # Preserve aspect ratio inside inner x inner
    bw, bh = pil_hi.size
    fit_scale = min(inner / bw, inner / bh)
    nw = max(1, int(round(bw * fit_scale)))
    nh = max(1, int(round(bh * fit_scale)))
    pil_small = pil_hi.resize((nw, nh), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    px = (target_size - nw) // 2
    py = (target_size - nh) // 2
    canvas.paste(pil_small, (px, py))

    arr = np.array(canvas)
    # Hard alpha threshold for crisp pixel sprite
    alpha = arr[:, :, 3] > 110
    arr[:, :, 3] = np.where(alpha, 255, 0)

    # Add 1px crisp dark outline around head so dark hair stands out against space
    padded = np.pad(alpha, 1, mode="constant", constant_values=False)
    dilated = (
        padded[:-2, 1:-1] | padded[2:, 1:-1] |
        padded[1:-1, :-2] | padded[1:-1, 2:]
    )
    outline = dilated & (~alpha)
    arr[outline, 0] = border_color[0]
    arr[outline, 1] = border_color[1]
    arr[outline, 2] = border_color[2]
    arr[outline, 3] = 255

    return Image.fromarray(arr, "RGBA")


def build_portraits():
    # Tuned crop boxes (x0, y0, x1, y1) focusing strictly on face/head (no shirts/shoulders)
    specs = {
        "pf": dict(
            filename="pf.jpg",
            crop_box_frac=(0.08, 0.07, 0.79, 0.82),
            ellipse_center_frac=(0.49, 0.50),
            ellipse_axes_frac=(0.37, 0.43),
            bg_color_hint=None,
            boost_brightness=1.18,
            boost_contrast=1.22,
            target_size=32,
            border_color=(64, 160, 255),  # Subtle blue outline for space contrast
            gamma=0.72,
            use_clahe_seg=True,
            mask_blur=5,
            hair_grabcut_y_frac=0.52,
            poly_frac=[
                (0.42, 0.09), (0.54, 0.11), (0.64, 0.17), (0.69, 0.25),
                (0.70, 0.34), (0.70, 0.38), (0.73, 0.38), (0.75, 0.43),
                (0.75, 0.49), (0.72, 0.525), (0.70, 0.52), (0.71, 0.59),
                (0.69, 0.67), (0.64, 0.74), (0.58, 0.785), (0.51, 0.79),
                (0.44, 0.76), (0.37, 0.69), (0.31, 0.61), (0.29, 0.64),
                (0.25, 0.62), (0.22, 0.55), (0.22, 0.52), (0.18, 0.46),
                (0.14, 0.37), (0.125, 0.28), (0.15, 0.20), (0.22, 0.13),
                (0.32, 0.10),
            ],
        ),
        "ppuen": dict(
            filename="ppuen.jpg",
            crop_box_frac=(0.14, 0.03, 0.86, 0.82),
            ellipse_center_frac=(0.50, 0.50),
            ellipse_axes_frac=(0.40, 0.44),
            bg_color_hint="white",
            boost_brightness=1.05,
            boost_contrast=1.12,
            target_size=32,
            border_color=(48, 224, 144),  # Mint-green space rim
        ),
        "ppeem": dict(
            filename="ppeem.jpg",
            crop_box_frac=(0.18, 0.11, 0.80, 0.77),
            ellipse_center_frac=(0.50, 0.50),
            ellipse_axes_frac=(0.39, 0.44),
            bg_color_hint="light_studio",
            boost_brightness=1.08,
            boost_contrast=1.15,
            target_size=32,
            border_color=(255, 192, 48),  # Gold commander rim
        ),
        "pping": dict(
            filename="pping.jpg",
            crop_box_frac=(0.10, 0.13, 0.86, 0.82),
            ellipse_center_frac=(0.50, 0.52),
            ellipse_axes_frac=(0.40, 0.43),
            bg_color_hint="light_studio",
            boost_brightness=1.05,
            boost_contrast=1.15,
            target_size=32,
            border_color=(255, 80, 180),  # Magenta heavy rim
        ),
        "ajv": dict(
            filename="ajv.png",
            crop_box_frac=(0.08, 0.02, 0.85, 0.82),
            ellipse_center_frac=(0.48, 0.48),
            ellipse_axes_frac=(0.38, 0.43),
            bg_color_hint=None,
            boost_brightness=1.02,
            boost_contrast=1.10,
            target_size=80,
            border_color=(255, 48, 48),   # Fiery Boss Crimson aura rim
            mask_blur=7,
            hair_grabcut_y_frac=0.26,
            poly_frac=[
                (0.45, 0.04), (0.57, 0.06), (0.67, 0.10), (0.74, 0.16),
                (0.77, 0.23), (0.77, 0.30), (0.75, 0.365), (0.78, 0.37),
                (0.805, 0.42), (0.80, 0.50), (0.78, 0.56), (0.73, 0.575),
                (0.71, 0.65), (0.65, 0.71), (0.56, 0.765), (0.45, 0.795),
                (0.34, 0.795), (0.28, 0.775), (0.24, 0.735), (0.20, 0.67),
                (0.175, 0.58), (0.155, 0.49), (0.106, 0.45), (0.104, 0.405),
                (0.155, 0.385), (0.17, 0.28), (0.19, 0.18), (0.26, 0.11),
                (0.35, 0.06),
            ],
        ),
        "ajv2": dict(
            filename="ajv2.png",
            crop_box_frac=(0.0, 0.0, 1.0, 1.0),
            ellipse_center_frac=(0.50, 0.50),
            ellipse_axes_frac=(0.50, 0.50),
            bg_color_hint=None,
            boost_brightness=1.02,
            boost_contrast=1.10,
            target_size=80,
            border_color=(255, 48, 48),   # Fiery Boss Crimson aura rim
            mask_blur=0,
            hair_grabcut_y_frac=0.50,
            poly_frac=None,
            use_alpha_mask=True,
        ),
    }

    out = {}
    for key, kw in specs.items():
        out[key] = extract_face_rgba(**kw)
    return out


# ---------------------------------------------------------------------------
# 4. Galaga-Style Bullets, Explosions, Power-Ups, Title Banner & 8x8 Font
# ---------------------------------------------------------------------------
def build_fx_sprites():
    """
    fx_rom layout (all indexed 0..47):
      - 4 explosion frames of 32x32 (4 * 1024 = 4096 bytes)
      - 3 power-up orbs of 16x16 (3 * 256 = 768 bytes)
      - 4 bullet sprites of 16x16 (4 * 256 = 1024 bytes):
          0: Player Form 1 single Galaga twin-tip laser
          1: Player Form 2 blue plasma spear
          2: Player Form 3 rainbow star orb
          3: Enemy/Boss fiery plasma orb
    Total = 5888 bytes (pad to 6144 bytes)
    """
    exps = []
    # 4-frame classic Galaga starburst explosion (32x32)
    for f in range(4):
        arr = np.zeros((32, 32), dtype=np.uint8)
        cx, cy = 15.5, 15.5
        r_outer = [6, 11, 14, 15][f]
        r_inner = [0, 3, 7, 11][f]
        for y in range(32):
            for x in range(32):
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy)
                ang = math.atan2(dy, dx)
                spikes = 0.78 + 0.28 * math.cos(8 * ang + f * 0.7)
                if r_inner <= d <= r_outer * spikes:
                    if f == 0:
                        arr[y, x] = 24 if d < 3 else 31
                    elif f == 1:
                        arr[y, x] = 31 if d < 6 else (30 if d < 9 else 28)
                    elif f == 2:
                        arr[y, x] = 24 if abs(dx) < 2 or abs(dy) < 2 else (28 if d < 10 else 25)
                    else:
                        if ((x + y) & 1) == 0:
                            arr[y, x] = 25 if d < 13 else 26
        exps.append(arr)

    # 3 Power-up orbs (16x16)
    orbs = []
    # Orb 0: Blue Evo Gem (upgrades Form 1 -> Form 2)
    o0 = np.zeros((16, 16), dtype=np.uint8)
    for y in range(16):
        for x in range(16):
            dx, dy = abs(x - 7.5), abs(y - 7.5)
            d = dx + dy
            if d <= 7.5:
                o0[y, x] = 24 if d >= 6.5 else (8 if d >= 3.5 else 25)
    # '2' or '+' glyph in middle
    o0[6:10, 7:9] = 24
    o0[7:9, 6:10] = 24
    orbs.append(o0)

    # Orb 1: Rainbow Star Evo Gem (upgrades Form 2 -> Form 3)
    o1 = np.zeros((16, 16), dtype=np.uint8)
    for y in range(16):
        for x in range(16):
            dx, dy = abs(x - 7.5), abs(y - 7.5)
            if (dx + dy <= 7.5) or (max(dx, dy) <= 5.5):
                if dx + dy >= 6.5 or max(dx, dy) >= 5.0:
                    o1[y, x] = 24
                else:
                    o1[y, x] = 16 + ((x + y) & 7)
    o1[7:9, 7:9] = 24
    orbs.append(o1)

    # Orb 2: Heart Extra Life
    o2 = np.zeros((16, 16), dtype=np.uint8)
    heart = [
        "................",
        "................",
        "...1111..1111...",
        "..1RRRR11RRRR1..",
        ".1RRWWRRRRRRRR1.",
        ".1RRWRRRRRRRRR1.",
        ".1RRRRRRRRRRRR1.",
        "..1RRRRRRRRRR1..",
        "...1RRRRRRRR1...",
        "....1RRRRRR1....",
        ".....1RRRR1.....",
        "......1RR1......",
        ".......11.......",
        "................",
        "................",
        "................",
    ]
    for y, row in enumerate(heart):
        for x, ch in enumerate(row):
            if ch == "1":
                o2[y, x] = 24
            elif ch == "R":
                o2[y, x] = 28
            elif ch == "W":
                o2[y, x] = 40
    orbs.append(o2)

    # 4 Bullet sprites (16x16): Nexys A7 FPGA boards for player forms 1..3 + Enemy fiery pellet
    def build_nexys_bullet_rgba():
        im = Image.open(os.path.join(SRC_DIR, "NexysA7.jpg")).convert("RGB")
        rgb = np.array(im)
        h, w = rgb.shape[:2]
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        # Flood-fill pure white outer background from all 4 corners while keeping inner white silkscreen/ports
        ff = np.zeros((h + 2, w + 2), np.uint8)
        tmp = bgr.copy()
        for sx, sy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
            cv2.floodFill(tmp, ff, (sx, sy), (0, 0, 0),
                          (22, 22, 22), (22, 22, 22), cv2.FLOODFILL_FIXED_RANGE | (255 << 8))
        alpha = np.where(ff[1:-1, 1:-1] == 255, 0, 255).astype(np.uint8)
        ys, xs = np.where(alpha > 0)
        bx0, bx1 = xs.min(), xs.max() + 1
        by0, by1 = ys.min(), ys.max() + 1
        cropped_rgb = Image.fromarray(rgb[by0:by1, bx0:bx1], "RGB")
        cropped_rgb = ImageEnhance.Contrast(cropped_rgb).enhance(1.18)
        cropped_rgb = ImageEnhance.Color(cropped_rgb).enhance(1.20)
        rgba_crop = np.dstack([np.array(cropped_rgb), alpha[by0:by1, bx0:bx1]])
        pil_crop = Image.fromarray(rgba_crop, "RGBA").resize((16, 16), Image.Resampling.LANCZOS)
        arr16 = np.array(pil_crop)
        arr16[:, :, 3] = np.where(arr16[:, :, 3] > 96, 255, 0)
        return arr16

    nexys_rgba = build_nexys_bullet_rgba()

    # Bul 3: Enemy Fiery Pellet
    b3 = np.zeros((16, 16), dtype=np.uint8)
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d <= 5.2:
                b3[y, x] = 31 if d <= 2.2 else (30 if d <= 3.7 else 28)

    return exps, orbs, nexys_rgba, b3


def build_logo():
    """Creates a crisp 256x64 retro arcade GALAGOOSE title banner."""
    w, h = 256, 64
    img = Image.new("RGB", (w, h), (0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Try built-in or bold blocky pixel text rendered manually using a 5x7 pixel font
    FONT5X7 = {
        'G': ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
        'A': ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        'L': ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        'E': ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        ' ': ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    }

    arr = np.zeros((h, w), dtype=np.uint8)
    # Outer arcade neon frame
    arr[2:4, 6:250] = 26
    arr[60:62, 6:250] = 26
    arr[2:62, 6:8] = 26
    arr[2:62, 248:250] = 26
    # Corner accents
    arr[1:5, 5:9] = 36
    arr[1:5, 247:251] = 36
    arr[59:63, 5:9] = 36
    arr[59:63, 247:251] = 36

    text = "GALAGOOSE"
    scale_x, scale_y = 4, 5
    start_x = 18
    start_y = 14
    for idx, ch in enumerate(text):
        glyph = FONT5X7[ch]
        gx = start_x + idx * (6 * scale_x)
        # Drop shadow in deep blue / red
        for row_i, row in enumerate(glyph):
            for col_i, bit in enumerate(row):
                if bit == '1':
                    x0 = gx + col_i * scale_x
                    y0 = start_y + row_i * scale_y
                    arr[y0+2:y0+scale_y+2, x0+2:x0+scale_x+2] = 29
        # Main chrome/gold/cyan gradient fill
        for row_i, row in enumerate(glyph):
            for col_i, bit in enumerate(row):
                if bit == '1':
                    x0 = gx + col_i * scale_x
                    y0 = start_y + row_i * scale_y
                    if idx < 4:  # "GALA" in Galaga red/gold/orange
                        c = 31 if row_i < 2 else (30 if row_i < 4 else 28)
                    else:       # "GOOSE" in crisp cyan/white/blue
                        c = 24 if row_i < 2 else (25 if row_i < 5 else 26)
                    arr[y0:y0+scale_y, x0:x0+scale_x] = c

    # Subtitle bar stripes
    arr[53:55, 24:232] = 36
    return arr


def build_font_8x8():
    """
    Creates 128 x 8x8 1-bit bitmap font glyphs (1024 bytes).
    Uses crisp built-in 8x8 patterns for ASCII 32..95 + arrows & icons.
    """
    # Compact 5x7 standard ASCII glyphs embedded in 8x8
    GLYPHS = {
        ' ': [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
        '!': [0x18,0x18,0x18,0x18,0x18,0x00,0x18,0x00],
        '+': [0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00],
        '-': [0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00],
        '.': [0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00],
        '/': [0x06,0x0C,0x18,0x30,0x60,0x40,0x00,0x00],
        ':': [0x00,0x18,0x18,0x00,0x18,0x18,0x00,0x00],
        '<': [0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x00],
        '=': [0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00],
        '>': [0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x00],
        '?': [0x3C,0x66,0x06,0x1C,0x18,0x00,0x18,0x00],
        '[': [0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00],
        ']': [0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00],
        '_': [0x00,0x00,0x00,0x00,0x00,0x00,0x7E,0x00],
        '0': [0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00],
        '1': [0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00],
        '2': [0x3C,0x66,0x06,0x1C,0x30,0x60,0x7E,0x00],
        '3': [0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00],
        '4': [0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x0C,0x00],
        '5': [0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00],
        '6': [0x3C,0x60,0x7C,0x66,0x66,0x66,0x3C,0x00],
        '7': [0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00],
        '8': [0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00],
        '9': [0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00],
        'A': [0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00],
        'B': [0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00],
        'C': [0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00],
        'D': [0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00],
        'E': [0x7E,0x60,0x60,0x7C,0x60,0x60,0x7E,0x00],
        'F': [0x7E,0x60,0x60,0x7C,0x60,0x60,0x60,0x00],
        'G': [0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00],
        'H': [0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00],
        'I': [0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00],
        'J': [0x1E,0x0C,0x0C,0x0C,0x6C,0x6C,0x38,0x00],
        'K': [0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00],
        'L': [0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00],
        'M': [0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00],
        'N': [0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00],
        'O': [0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
        'P': [0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00],
        'Q': [0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0x00],
        'R': [0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00],
        'S': [0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00],
        'T': [0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00],
        'U': [0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
        'V': [0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00],
        'W': [0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00],
        'X': [0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00],
        'Y': [0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00],
        'Z': [0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00],
        # Special glyphs in 0x01..0x0F
        '\x01': [0x00,0x6C,0xFE,0xFE,0x7C,0x38,0x10,0x00],  # Heart icon
        '\x02': [0x18,0x18,0x7E,0x3C,0x3C,0x66,0x42,0x00],  # Star icon
        '\x03': [0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF],  # Solid bar block
        '\x04': [0x00,0x18,0x3C,0x7E,0x3C,0x18,0x00,0x00],  # Diamond
    }
    rom = np.zeros((128 * 8,), dtype=np.uint8)
    for ch, rows in GLYPHS.items():
        code = ord(ch)
        for r in range(8):
            rom[code * 8 + r] = rows[r]
    return rom


# ---------------------------------------------------------------------------
# 5. Chiptune Audio ROM Generator (Multi-track BGM)
# ---------------------------------------------------------------------------
def build_bgm_rom():
    """
    Generates bgm_rom.mem: 512 x 16-bit entries.
    Track 0 (0..127): Title / Galaga Fanfare (loop 64 steps)
    Track 1 (128..255): Space Action Theme (loop 128 steps)
    Track 2 (256..383): Boss AJV Intense Theme (loop 128 steps)
    Track 3 (384..511): Victory / Game Over Stingers (64 steps each)
    Entry format: [15:10] lead_note (0=rest, 1..48 MIDI-like index),
                  [9:4]   bass_note (0=rest, 1..48),
                  [3:0]   drum_mask (bit0=kick, bit1=snare, bit2=hat, bit3=accent)
    """
    # Note mapping: 1=C3 .. 36=B5 (3 octaves, 12 notes/oct)
    NOTE_IDX = {
        'R': 0,
        'C3': 1, 'C#3': 2, 'D3': 3, 'D#3': 4, 'E3': 5, 'F3': 6, 'F#3': 7, 'G3': 8, 'G#3': 9, 'A3': 10, 'A#3': 11, 'B3': 12,
        'C4': 13, 'C#4': 14, 'D4': 15, 'D#4': 16, 'E4': 17, 'F4': 18, 'F#4': 19, 'G4': 20, 'G#4': 21, 'A4': 22, 'A#4': 23, 'B4': 24,
        'C5': 25, 'C#5': 26, 'D5': 27, 'D#5': 28, 'E5': 29, 'F5': 30, 'F#5': 31, 'G5': 32, 'G#5': 33, 'A5': 34, 'A#5': 35, 'B5': 36,
        'C6': 37,
    }

    def pack(lead, bass, drum):
        return ((NOTE_IDX[lead] & 0x3F) << 10) | ((NOTE_IDX[bass] & 0x3F) << 4) | (drum & 0xF)

    rom = [0] * 512

    # Track 0: Classic Galaga-style hero fanfare (64 steps repeated x2)
    t0_lead = [
        'G4','R','C5','R','E5','R','G5','E5',  'F5','R','D5','R','B4','R','G4','R',
        'A4','B4','C5','D5','E5','R','C5','R',  'D5','R','G5','R','G5','R','R','R',
        'E5','R','G5','R','A5','R','G5','E5',  'F5','E5','D5','C5','D5','R','G4','R',
        'C5','D5','E5','G5','A5','G5','E5','D5','C5','R','G4','R','C5','R','R','R',
    ]
    t0_bass = [
        'C3','C4','C3','C4','C3','C4','C3','C4', 'G3','G4','G3','G4','G3','G4','G3','G4',
        'A3','A4','A3','A4','A3','A4','A3','A4', 'G3','G4','G3','G4','G3','B3','D4','G3',
        'C3','C4','C3','C4','A3','A4','A3','A4', 'F3','F4','F3','F4','G3','G4','G3','G4',
        'C3','G3','C4','G3','F3','G3','G3','G3', 'C3','G3','C4','G3','C3','R','R','R',
    ]
    for i in range(64):
        drum = (1 if i % 4 == 0 else 0) | (2 if i % 8 == 4 else 0) | (4 if i % 2 == 1 else 0)
        val = pack(t0_lead[i], t0_bass[i], drum)
        rom[i] = val
        rom[64 + i] = val

    # Track 1: High-energy Space Battle (128 steps)
    pat_a_lead = [
        'E5','E5','R','E5','R','C5','E5','R',  'G5','R','R','R','G4','R','R','R',
        'C5','R','R','G4','R','R','E4','R',    'A4','R','B4','R','A#4','A4','R','R',
        'G4','E5','G5','A5','R','F5','G5','R', 'E5','R','C5','D5','B4','R','R','R',
        'C5','D5','E5','G5','E5','C5','D5','B4','C5','R','G4','R','C5','R','R','R',
    ]
    pat_b_lead = [
        'A4','C5','E5','A5','G5','E5','C5','A4','D5','F5','A5','G5','F5','D5','B4','G4',
        'C5','E5','G5','C6','B5','G5','E5','C5','F5','E5','D5','C5','B4','D5','G5','R',
        'E5','C5','D5','B4','C5','A4','B4','G4','A4','B4','C5','D5','E5','F5','G5','R',
        'A5','G5','F5','E5','D5','C5','B4','G4','C5','R','G5','R','C5','R','R','R',
    ]
    pat_bass = [
        'C3','C4','C3','C4','C3','C4','C3','C4', 'G3','G4','G3','G4','G3','G4','G3','G4',
        'A3','A4','A3','A4','E3','E4','E3','E4', 'F3','F4','F3','F4','G3','G4','G3','G4',
    ] * 4
    for i in range(128):
        lead = pat_a_lead[i] if i < 64 else pat_b_lead[i - 64]
        drum = (1 if i % 4 == 0 else 0) | (2 if i % 4 == 2 else 0) | (4 if i % 2 == 1 else 0)
        rom[128 + i] = pack(lead, pat_bass[i], drum)

    # Track 2: Boss AJV Menacing Theme (128 steps - fast minor arpeggios)
    boss_bar1 = ['E4','G4','B4','E5','D#5','B4','G4','E4', 'E4','G4','A#4','E5','D5','A#4','G4','E4']
    boss_bar2 = ['C5','B4','A4','G4','F#4','A4','C5','F#5','E5','D#5','B4','G4','F#4','E4','D#4','B3']
    boss_bar3 = ['E5','R','E5','G5','F#5','R','D#5','B4', 'C5','R','E5','C5','B4','R','A4','F#4']
    boss_bar4 = ['G4','A4','B4','C5','D#5','E5','F#5','G5','A5','G5','F#5','E5','D#5','B4','E5','R']
    boss_lead = (boss_bar1 + boss_bar2 + boss_bar3 + boss_bar4) * 2
    boss_bass = (['E3','E4','E3','E4']*4 + ['C3','C4','B3','B4']*2 + ['A3','A4','B3','B4']*2) * 4
    for i in range(128):
        drum = (1 if i % 2 == 0 else 0) | (2 if i % 4 == 2 else 0) | (4 if i % 2 == 1 else 0)
        rom[256 + i] = pack(boss_lead[i], boss_bass[i], drum)

    # Track 3: Victory (384..447) and Game Over (448..511)
    vic_lead = ['C5','E5','G5','C6','R','G5','C6','R'] + ['R']*56
    vic_bass = ['C3','G3','C4','E4','R','G3','C4','R'] + ['R']*56
    for i in range(64):
        rom[384 + i] = pack(vic_lead[i], vic_bass[i], 1 if i < 8 and i % 2 == 0 else 0)

    go_lead = ['E5','D#5','D5','C#5','C5','R','G4','R','C4','R','R','R'] + ['R']*52
    go_bass = ['C3','B3','A#3','A3','G#3','R','G3','R','C3','R','R','R'] + ['R']*52
    for i in range(64):
        rom[448 + i] = pack(go_lead[i], go_bass[i], 2 if i in (0, 2, 4, 8) else 0)

    return rom


# ---------------------------------------------------------------------------
# 6. Quantize Portraits to Indices 48..255 and Write .mem Files
# ---------------------------------------------------------------------------
def write_mem_hex(path, data, width_hex=2):
    with open(path, "w") as f:
        for v in data:
            f.write(f"{int(v):0{width_hex}X}\n")
    shutil.copy2(path, os.path.join(SIM_DIR, os.path.basename(path)))


def main():
    goose_frames = build_goose_frames()
    portraits = build_portraits()
    exps, orbs, nexys_rgba, enemy_bul = build_fx_sprites()
    logo = build_logo()
    font = build_font_8x8()
    bgm = build_bgm_rom()

    # Collect opaque pixels from all 5 portraits + Nexys A7 board to build optimal 208-color palette (48..255)
    sample_pixels = []
    for name in ["pf", "ppuen", "ppeem", "pping", "ajv", "ajv2"]:
        arr = np.array(portraits[name])
        opaque = arr[arr[:, :, 3] > 0][:, :3]
        # Repeat smaller sprites so each face gets equal weight in median cut
        reps = max(1, 6400 // max(1, len(opaque)))
        sample_pixels.append(np.tile(opaque, (reps, 1)))
    nexys_opaque = nexys_rgba[nexys_rgba[:, :, 3] > 0][:, :3]
    sample_pixels.append(np.tile(nexys_opaque, (max(1, 4800 // max(1, len(nexys_opaque))), 1)))
    all_px = np.vstack(sample_pixels)
    # Build Pillow image from sample pixels and quantize to 208 colors
    side = int(math.ceil(math.sqrt(len(all_px))))
    padded = np.zeros((side * side, 3), dtype=np.uint8)
    padded[:len(all_px)] = all_px
    sample_img = Image.fromarray(padded.reshape(side, side, 3), "RGB")
    q_img = sample_img.quantize(colors=208, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    q_pal = q_img.getpalette()[:208 * 3]

    # Build full 256-entry RGB444 palette
    palette_rgb888 = [(0, 0, 0)] * 256
    for idx, rgb in FIXED_PALETTE.items():
        palette_rgb888[idx] = quantize_444(*rgb)
    for i in range(208):
        r, g, b = q_pal[i * 3 : i * 3 + 3]
        palette_rgb888[48 + i] = quantize_444(r, g, b)

    pal_444 = [rgb888_to_444(*c) for c in palette_rgb888]
    pal_arr_48_255 = np.array(palette_rgb888[48:], dtype=np.int32)  # (208, 3)

    def map_rgba_to_indices(pil_rgba):
        arr = np.array(pil_rgba)
        h, w = arr.shape[:2]
        out = np.zeros((h, w), dtype=np.uint8)
        mask = arr[:, :, 3] > 0
        rgb = arr[mask][:, :3].astype(np.int32)
        # Nearest Euclidean match in palette[48..255]
        dists = ((rgb[:, None, :] - pal_arr_48_255[None, :, :]) ** 2).sum(axis=2)
        best = 48 + np.argmin(dists, axis=1)
        out[mask] = best.astype(np.uint8)
        return out

    enemy_maps = {name: map_rgba_to_indices(portraits[name]) for name in ["pf", "ppuen", "ppeem", "pping"]}
    boss_map1 = map_rgba_to_indices(portraits["ajv"])
    boss_map2 = map_rgba_to_indices(portraits["ajv2"])
    boss_map = boss_map1

    # Quantize Nexys A7 board sprite (16x16) for player bullets (Forms 1..3)
    nexys_bul_base = map_rgba_to_indices(Image.fromarray(nexys_rgba, "RGBA"))
    b0 = nexys_bul_base.copy()
    b1 = nexys_bul_base.copy()
    for lx in range(2, 14, 2):
        b1[13, lx] = 25  # Glowing cyan LEDs for Blue Goose
    b2 = nexys_bul_base.copy()
    for lx in range(2, 14):
        b2[13, lx] = 16 + (lx & 7)  # Glowing rainbow LED bar for Rainbow Goose
    buls = [b0, b1, b2, enemy_bul]

    # Write .mem files
    write_mem_hex(os.path.join(MEM_DIR, "pal_rom.mem"), pal_444, width_hex=3)
    write_mem_hex(os.path.join(MEM_DIR, "goose_rom.mem"),
                  np.concatenate([goose_frames[0].flatten(), goose_frames[1].flatten()]), width_hex=2)
    write_mem_hex(os.path.join(MEM_DIR, "enemy_rom.mem"),
                  np.concatenate([enemy_maps[k].flatten() for k in ["pf", "ppuen", "ppeem", "pping"]]), width_hex=2)
    boss_flat = np.concatenate([boss_map1.flatten(), boss_map2.flatten()])
    write_mem_hex(os.path.join(MEM_DIR, "boss_rom.mem"), boss_flat, width_hex=2)

    fx_flat = np.concatenate(
        [e.flatten() for e in exps] +
        [o.flatten() for o in orbs] +
        [b.flatten() for b in buls] +
        [np.zeros(256, dtype=np.uint8)]  # pad to 6144
    )
    write_mem_hex(os.path.join(MEM_DIR, "fx_rom.mem"), fx_flat, width_hex=2)
    write_mem_hex(os.path.join(MEM_DIR, "logo_rom.mem"), logo.flatten(), width_hex=2)
    write_mem_hex(os.path.join(MEM_DIR, "font_rom.mem"), font.flatten(), width_hex=2)
    write_mem_hex(os.path.join(MEM_DIR, "bgm_rom.mem"), bgm, width_hex=4)

    # -----------------------------------------------------------------------
    # 7. Visual Sprite Preview Sheet (sprite_preview.png)
    # -----------------------------------------------------------------------
    def idx_to_rgb_img(idx_arr, form=0, scale=4):
        h, w = idx_arr.shape
        rgb = np.full((h, w, 3), (12, 16, 36), dtype=np.uint8)  # dark space bg
        for y in range(h):
            for x in range(w):
                idx = int(idx_arr[y, x])
                if idx == 0:
                    continue
                if form == 1 and idx in (2, 3):
                    idx = 8 if idx == 2 else 9
                elif form == 2 and idx in (2, 3):
                    idx = 16 + (((y >> 1) + 0) & 7)
                rgb[y, x] = palette_rgb888[idx]
        im = Image.fromarray(rgb, "RGB")
        if scale != 1:
            im = im.resize((w * scale, h * scale), Image.Resampling.NEAREST)
        return im

    sheet = Image.new("RGB", (1020, 620), (14, 18, 38))
    draw = ImageDraw.Draw(sheet)

    draw.text((20, 12), "GALAGOOSE HARDWARE SPRITE SHEET PREVIEW (4-bit VGA Quantized)", fill=(255, 240, 80))

    # Row 1: Goose Forms 1, 2, 3 (32x32 @ 3x = 96x96)
    draw.text((20, 40), "PLAYER GOOSE EVOLUTIONS (32x32):", fill=(120, 220, 255))
    for i, (lbl, frm, frame_idx) in enumerate([
        ("F1: WHITE (1-SHOT)", 0, 0),
        ("F1: FLY ANIM", 0, 1),
        ("F2: BLUE (2-SHOT)", 1, 0),
        ("F3: RAINBOW (180 ARC)", 2, 0),
    ]):
        x = 20 + i * 160
        sheet.paste(idx_to_rgb_img(goose_frames[frame_idx], form=frm, scale=3), (x, 62))
        draw.text((x, 164), lbl, fill=(230, 230, 230))

    # Row 2: Cropped Face Enemies (32x32 @ 3x = 96x96)
    draw.text((20, 195), "ENEMIES (CROPPED FACES, BG REMOVED, 32x32):", fill=(120, 220, 255))
    for i, name in enumerate(["pf", "ppuen", "ppeem", "pping"]):
        x = 20 + i * 160
        sheet.paste(idx_to_rgb_img(enemy_maps[name], scale=3), (x, 218))
        draw.text((x, 320), name.upper(), fill=(255, 200, 100))

    # Right side: Boss AJV (80x80 @ 2x: Phase 1 & Phase 2 Enraged)
    draw.text((660, 25), "LAST BOSS: AJV PHASE 1 & 2:", fill=(255, 100, 100))
    sheet.paste(idx_to_rgb_img(boss_map1, scale=2), (660, 48))
    draw.text((660, 212), "NORMAL AJV", fill=(200, 200, 200))
    sheet.paste(idx_to_rgb_img(boss_map2, scale=2), (830, 48))
    draw.text((830, 212), "ENRAGED AJV2", fill=(255, 80, 80))

    # Row 3: Explosions, Orbs, Bullets
    draw.text((20, 350), "GALAGA FX: EXPLOSIONS (32x32), POWER-UPS & BULLETS (16x16):", fill=(120, 220, 255))
    for i, e in enumerate(exps):
        sheet.paste(idx_to_rgb_img(e, scale=2), (20 + i * 74, 375))
    for i, o in enumerate(orbs):
        sheet.paste(idx_to_rgb_img(o, scale=3), (330 + i * 64, 382))
    for i, b in enumerate(buls):
        sheet.paste(idx_to_rgb_img(b, scale=3), (540 + i * 56, 382))

    # Row 4: Title Logo
    draw.text((20, 465), "TITLE LOGO (256x64):", fill=(120, 220, 255))
    sheet.paste(idx_to_rgb_img(logo, scale=2), (20, 486))

    preview_path = os.path.join(MEM_DIR, "sprite_preview.png")
    sheet.save(preview_path)
    print(f"Generated all .mem files and {preview_path}")


if __name__ == "__main__":
    main()
