#!/usr/bin/env python3
"""Turn the raw passes written by render_assets.gd into the committed presentation PNGs.

Usage: python3 tools/art/compose_renders.py <jobs.json> [--clean]

The Godot script renders each view at twice its final size with no anti-aliasing, so every
pixel is either covered or empty. This step downsamples with a premultiplied Lanczos filter
(clean edges over any background), keys the unshaded sea plane out of the profile so the hull
is cut at the waterline, and draws the white recognition outline from the normal and depth
passes the way the old Freestyle render did.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

BEAUTY = (1200, 640)
THUMB = (240, 128)
PROFILE = (768, 224)
KEY = np.array([0, 255, 0], dtype=np.int16)
FACE_GREY = 0.23  # target median sRGB tone of the visible profile faces; the game tints the drawing
OUTLINE_DILATE = 1  # pixels at 2x, so the finished line is about 1.5 px like Freestyle's 1.7


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0


def downsample(rgba, size):
    """Premultiplied Lanczos resize: the colour of a covered pixel never bleeds into or from
    the transparent background."""
    a = rgba[..., 3:4]
    pre = np.concatenate([rgba[..., :3] * a, a], axis=-1)
    # Pillow has no float RGBA mode, so the four premultiplied channels are resized as "F" images.
    channels = [Image.fromarray(pre[..., i].astype(np.float32), mode="F").resize(size, Image.LANCZOS) for i in range(4)]
    out = np.stack([np.asarray(c, dtype=np.float64) for c in channels], axis=-1)
    alpha = np.clip(out[..., 3:4], 0, 1)
    rgb = np.where(alpha > 1e-4, out[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    return np.concatenate([np.clip(rgb, 0, 1), alpha], axis=-1)


def save(rgba, path):
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, optimize=True)


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def key_mask(rgba):
    rgb = (rgba[..., :3] * 255).astype(np.int16)
    return (np.abs(rgb - KEY).sum(axis=-1) < 24) & (rgba[..., 3] > 0.5)


def edges_from(mask, threshold_fn):
    """Mark a pixel when a 4-neighbour differs by more than the threshold."""
    h, w = mask.shape[:2]
    edge = np.zeros((h, w), dtype=bool)
    for dy, dx in ((0, 1), (1, 0)):
        a = threshold_fn(slice(0, h - dy), slice(0, w - dx), slice(dy, h), slice(dx, w))
        edge[:h - dy, :w - dx] |= a
        edge[dy:, dx:] |= a
    return edge


def dilate(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy == 0 and dx == 0:
                continue
            ys = slice(max(0, dy), min(h, h + dy))
            xs = slice(max(0, dx), min(w, w + dx))
            ys2 = slice(max(0, -dy), min(h, h - dy))
            xs2 = slice(max(0, -dx), min(w, w - dx))
            out[ys2, xs2] |= mask[ys, xs]
    return out


def profile(job):
    raw = job["raw"]
    sid = job["id"]
    grey = load(os.path.join(raw, sid + "_pgrey.png"))
    normal = load(os.path.join(raw, sid + "_pnormal.png"))
    depth = load(os.path.join(raw, sid + "_pdepth.png"))
    sea = key_mask(grey)
    covered = (grey[..., 3] > 0.5) & ~sea
    # Flat grey faces: keep the renderer's shading but pin the mean of the visible faces to the
    # recognition-drawing tone so every class reads the same after tinting.
    lum = srgb_to_linear(grey[..., :3]).mean(axis=-1)
    if covered.any():
        lum = lum * (srgb_to_linear(np.array(FACE_GREY)) / max(1e-6, np.median(lum[covered])))
    tone = linear_to_srgb(np.clip(lum, 0, 0.85))
    # The unshaded normal and depth passes are written linearly by the compatibility renderer,
    # while the shaded grey pass is sRGB-encoded like any picture.
    n = normal[..., :3] * 2.0 - 1.0
    d = (depth[..., 0] - 0.2) / 0.8
    valid = covered
    crease = edges_from(valid, lambda y0, x0, y1, x1: valid[y0, x0] & valid[y1, x1] & ((n[y0, x0] * n[y1, x1]).sum(axis=-1) < np.cos(np.radians(38))))
    step = edges_from(valid, lambda y0, x0, y1, x1: valid[y0, x0] & valid[y1, x1] & (np.abs(d[y0, x0] - d[y1, x1]) > 0.035))
    silhouette = edges_from(valid, lambda y0, x0, y1, x1: valid[y0, x0] != valid[y1, x1]) & valid
    outline = dilate(crease | step | silhouette, OUTLINE_DILATE) & (valid | dilate(valid, OUTLINE_DILATE))
    out = np.zeros(grey.shape, dtype=np.float64)
    out[..., 0] = out[..., 1] = out[..., 2] = tone
    out[..., 3] = valid.astype(np.float64)
    out[outline, :3] = 1.0
    out[outline, 3] = 1.0
    return downsample(out, PROFILE)


def main():
    args = sys.argv[1:]
    clean = "--clean" in args
    jobs = json.load(open([a for a in args if not a.startswith("--")][0]))
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    for job in jobs:
        sid, raw = job["id"], job["raw"]
        out_root = job.get("out") or os.path.join(root, "assets")
        out_dir = os.path.join(out_root, "weapons" if job["kind"] == "weapon" else "platforms")
        os.makedirs(out_dir, exist_ok=True)
        beauty = load(os.path.join(raw, sid + "_beauty.png"))
        save(downsample(beauty, BEAUTY), os.path.join(out_dir, sid + "_beauty.png"))
        save(downsample(beauty, THUMB), os.path.join(out_dir, sid + "_thumb.png"))
        used = [sid + "_beauty.png"]
        if job["kind"] != "weapon":
            plan = load(os.path.join(raw, sid + "_plan.png"))
            save(downsample(plan, tuple(job["plan_size"])), os.path.join(out_dir, sid + "_plan.png"))
            save(profile(job), os.path.join(out_dir, sid + "_profile.png"))
            used += [sid + "_plan.png", sid + "_pgrey.png", sid + "_pnormal.png", sid + "_pdepth.png"]
        if clean:
            for name in used:
                try:
                    os.remove(os.path.join(raw, name))
                except OSError:
                    pass
        print("COMPOSED", sid)


if __name__ == "__main__":
    main()
