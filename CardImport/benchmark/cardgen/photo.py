"""Turn a clean rendered card into a simulated phone photo of the card lying on a surface."""
import math

import cv2
import numpy as np


# ---------------------------------------------------------------- backgrounds

def _lowfreq(rng, h, w, cells_y, cells_x):
    small = rng.standard_normal((max(2, cells_y), max(2, cells_x))).astype(np.float32)
    return cv2.resize(small, (w, h), interpolation=cv2.INTER_CUBIC)


def bg_wood(rng, h, w):
    horiz = rng.random() < 0.5
    H, W = (h, w) if horiz else (w, h)
    y = np.arange(H, dtype=np.float32)[:, None]
    warp = _lowfreq(rng, H, W, 6, 3) * 18 + _lowfreq(rng, H, W, 30, 4) * 3
    period = rng.uniform(22, 48) * H / 1000
    rings = np.sin(2 * np.pi * (y + warp) / period)
    streak = cv2.resize(rng.standard_normal((H // 3 + 1, max(2, W // 60))).astype(np.float32), (W, H), interpolation=cv2.INTER_LINEAR)
    fine = cv2.resize(rng.standard_normal((H, max(2, W // 120))).astype(np.float32), (W, H), interpolation=cv2.INTER_LINEAR)
    fine = np.clip(fine, -2.5, 2.5)
    t = 0.5 + 0.2 * rings + 0.1 * streak + 0.07 * fine + 0.1 * _lowfreq(rng, H, W, 3, 3)
    # plank seams
    plank = int(H / rng.uniform(2.5, 4.5))
    seam = np.zeros((H, 1), np.float32)
    off = rng.integers(0, plank)
    for s in range(int(off), H, plank):
        seam[max(0, s - 2):s + 2] = 1
    t = np.clip(t, 0, 1)
    palettes = [((88, 52, 28), (168, 116, 72)), ((120, 80, 45), (196, 150, 100)), ((60, 38, 24), (122, 82, 52)), ((150, 110, 70), (214, 178, 130))]
    dark, light = [np.array(c, np.float32) for c in palettes[rng.integers(len(palettes))]]
    img = dark[None, None, ::-1] + (light - dark)[None, None, ::-1] * t[..., None]  # BGR
    img *= (1 - 0.45 * seam[..., None])
    img += rng.normal(0, 3, img.shape).astype(np.float32)
    if not horiz:
        img = np.ascontiguousarray(np.transpose(img, (1, 0, 2)))
    return img


def bg_white_table(rng, h, w):
    base = np.array([rng.uniform(222, 240), rng.uniform(224, 242), rng.uniform(226, 244)], np.float32)  # BGR
    img = np.ones((h, w, 3), np.float32) * base
    img += _lowfreq(rng, h, w, 4, 5)[..., None] * 5
    if rng.random() < 0.35:  # faint, irregular marble veins (multi-octave noise)
        v = _lowfreq(rng, h, w, 5, 5) + 0.5 * _lowfreq(rng, h, w, 17, 17) + 0.25 * _lowfreq(rng, h, w, 41, 41)
        veins = np.exp(-(np.abs(v) * 22) ** 2)
        veins *= np.clip(_lowfreq(rng, h, w, 3, 3) + 0.3, 0, 1)  # veins fade in and out
        img -= cv2.GaussianBlur(veins, (0, 0), 1.2)[..., None] * rng.uniform(6, 12)
    img += rng.normal(0, 2.2, img.shape).astype(np.float32)
    return img


def bg_dark_fabric(rng, h, w):
    cols = [(52, 46, 42), (70, 40, 30), (40, 40, 44), (35, 52, 38), (60, 45, 60)]  # BGR
    base = np.array(cols[rng.integers(len(cols))], np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    p = rng.uniform(3.0, 5.0)
    ang = rng.uniform(0, np.pi)
    u = xx * math.cos(ang) + yy * math.sin(ang)
    v = -xx * math.sin(ang) + yy * math.cos(ang)
    weave = np.sin(2 * np.pi * u / p) * np.sin(2 * np.pi * v / p)
    folds = _lowfreq(rng, h, w, 3, 4)
    img = base[None, None, :] * (1 + 0.10 * weave[..., None] + 0.18 * folds[..., None])
    img += rng.normal(0, 4, img.shape).astype(np.float32)
    return img


BACKGROUNDS = {"wood": bg_wood, "white_table": bg_white_table, "dark_fabric": bg_dark_fabric}


def add_clutter(rng, img):
    """Draw 1-3 objects (pen, coffee ring, paper sheet, phone) around the frame edges."""
    h, w = img.shape[:2]
    n = int(rng.integers(1, 4))
    kinds = []
    for _ in range(n):
        k = ["pen", "ring", "paper", "phone"][rng.integers(4)]
        kinds.append(k)
        cx, cy = (rng.uniform(0, 1) * w, rng.choice([rng.uniform(0, .15), rng.uniform(.85, 1)]) * h) if rng.random() < .5 else \
                 (rng.choice([rng.uniform(0, .12), rng.uniform(.88, 1)]) * w, rng.uniform(0, 1) * h)
        ang = rng.uniform(0, 180)
        layer = np.zeros((h, w), np.uint8)
        if k == "pen":
            L, T = w * rng.uniform(.35, .55), max(6, w * .018)
            box = cv2.boxPoints(((cx, cy), (L, T), ang)).astype(np.int32)
            cv2.fillConvexPoly(layer, box, 255)
            col = [(30, 30, 30), (140, 60, 20), (40, 40, 160), (200, 200, 200)][rng.integers(4)]
            m = cv2.GaussianBlur(layer, (0, 0), 1.2).astype(np.float32)[..., None] / 255
            sh = cv2.GaussianBlur(np.roll(layer, (int(T * .6), int(T * .6)), (0, 1)), (0, 0), T * .6).astype(np.float32)[..., None] / 255
            img *= (1 - .35 * sh)
            img[:] = img * (1 - m) + np.array(col, np.float32) * m
        elif k == "ring":
            r = w * rng.uniform(.05, .08)
            cv2.circle(layer, (int(cx), int(cy)), int(r), 255, max(2, int(r * .08)))
            m = cv2.GaussianBlur(layer, (0, 0), 2.5).astype(np.float32)[..., None] / 255
            img *= (1 - .28 * m * np.array([1.0, .8, .55], np.float32))
        elif k == "paper":
            L, T = w * rng.uniform(.5, .8), w * rng.uniform(.6, .9)
            box = cv2.boxPoints(((cx, cy), (L, T), ang)).astype(np.int32)
            cv2.fillConvexPoly(layer, box, 255)
            m = cv2.GaussianBlur(layer, (0, 0), 1.0).astype(np.float32)[..., None] / 255
            sh = cv2.GaussianBlur(layer, (0, 0), w * .01).astype(np.float32)[..., None] / 255
            img *= (1 - .25 * sh)
            paper = np.ones_like(img) * np.array([238, 240, 242], np.float32)
            for yy in range(0, h, max(12, int(w * .022))):  # ruled lines
                cv2.line(paper, (0, yy), (w, yy), (225, 200, 185), 1)
            M = cv2.getRotationMatrix2D((cx, cy), -ang, 1.0)
            paper = cv2.warpAffine(paper, M, (w, h), borderMode=cv2.BORDER_REFLECT)
            img[:] = img * (1 - m) + paper * m
        else:  # phone
            L, T = w * .22, w * .45
            box = cv2.boxPoints(((cx, cy), (L, T), ang)).astype(np.int32)
            cv2.fillConvexPoly(layer, box, 255)
            m = cv2.GaussianBlur(layer, (0, 0), 1.5).astype(np.float32)[..., None] / 255
            sh = cv2.GaussianBlur(layer, (0, 0), w * .015).astype(np.float32)[..., None] / 255
            img *= (1 - .4 * sh)
            img[:] = img * (1 - m) + np.array([22, 22, 26], np.float32) * m
    return kinds


# ---------------------------------------------------------------- geometry

def card_quad(rng, cw, ch, W, H, fill, tilt_deg, rot_deg):
    """Project a cw x ch card tilted in 3D onto a W x H frame. Returns 4x2 float32 (tl,tr,br,bl)."""
    f = W * rng.uniform(0.85, 1.15)
    ax = math.radians(tilt_deg) * rng.choice([-1, 1]) * rng.uniform(0.6, 1.0)
    ay_mag = math.sqrt(max(0.0, math.radians(tilt_deg) ** 2 - ax ** 2))
    ay = ay_mag * rng.choice([-1, 1])
    az = math.radians(rot_deg)
    Rx = np.array([[1, 0, 0], [0, math.cos(ax), -math.sin(ax)], [0, math.sin(ax), math.cos(ax)]])
    Ry = np.array([[math.cos(ay), 0, math.sin(ay)], [0, 1, 0], [-math.sin(ay), 0, math.cos(ay)]])
    Rz = np.array([[math.cos(az), -math.sin(az), 0], [math.sin(az), math.cos(az), 0], [0, 0, 1]])
    R = Rz @ Ry @ Rx
    pts = np.array([[-cw / 2, -ch / 2, 0], [cw / 2, -ch / 2, 0], [cw / 2, ch / 2, 0], [-cw / 2, ch / 2, 0]], np.float64)
    # distance so that the card spans `fill` of the frame along its limiting dimension
    scale = min(fill * W / cw, fill * H / ch)
    D = f / scale
    P = (R @ pts.T).T + np.array([0, 0, D])
    proj = np.stack([f * P[:, 0] / P[:, 2], f * P[:, 1] / P[:, 2]], 1)
    span = proj.max(0) - proj.min(0)
    margin = np.array([W, H]) - span
    off = np.array([rng.uniform(-0.25, 0.25) * max(0, margin[0]), rng.uniform(-0.25, 0.25) * max(0, margin[1])])
    centre = (proj.max(0) + proj.min(0)) / 2
    quad = proj - centre + np.array([W / 2, H / 2]) + off
    return quad.astype(np.float32)


def rounded_mask(h, w, r):
    m = np.full((h, w), 255, np.uint8)
    if r <= 0:
        return m
    m[:r, :r] = 0; m[:r, -r:] = 0; m[-r:, :r] = 0; m[-r:, -r:] = 0
    for cx, cy in [(r, r), (w - r - 1, r), (r, h - r - 1), (w - r - 1, h - r - 1)]:
        cv2.circle(m, (cx, cy), r, 255, -1)
    return m


# ---------------------------------------------------------------- main entry

def simulate_photo(card_bgr, rng, params):
    """params: dict with keys long_edge, bg, clutter, fill, tilt, rot, uneven, shadow, glare,
    blur_sigma, motion_len, noise_sigma, jpeg_q, frame_portrait. Returns (uint8 BGR image, quad)."""
    ch0, cw0 = card_bgr.shape[:2]
    L = params["long_edge"]
    portrait = params["frame_portrait"]
    W, H = (int(L * 3 / 4), L) if portrait else (L, int(L * 3 / 4))
    bg = BACKGROUNDS[params["bg"]](rng, H, W)
    kinds = add_clutter(rng, bg) if params["clutter"] else []

    quad = card_quad(rng, cw0, ch0, W, H, params["fill"], params["tilt"], params["rot"])
    # pre-scale the card close to its on-frame size to avoid aliasing in the perspective warp
    target_w = np.linalg.norm(quad[1] - quad[0])
    s = min(1.0, target_w * 1.25 / cw0)
    card = cv2.resize(card_bgr, (max(8, int(cw0 * s)), max(8, int(ch0 * s))), interpolation=cv2.INTER_AREA) if s < 1 else card_bgr.copy()
    ch, cw = card.shape[:2]
    cardf = card.astype(np.float32)
    # paper grain + slight edge darkening (card thickness)
    cardf += rng.normal(0, 2.0, cardf.shape).astype(np.float32)
    mask = rounded_mask(ch, cw, int(min(ch, cw) * rng.uniform(0.0, 0.035)))
    edge = cv2.GaussianBlur(255 - cv2.erode(mask, np.ones((3, 3), np.uint8), iterations=2), (0, 0), 1.5).astype(np.float32)[..., None] / 255
    cardf *= (1 - 0.25 * edge)

    src = np.array([[0, 0], [cw, 0], [cw, ch], [0, ch]], np.float32)
    M = cv2.getPerspectiveTransform(src, quad)
    warped = cv2.warpPerspective(cardf, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    wmask = cv2.warpPerspective(mask, M, (W, H), flags=cv2.INTER_LINEAR).astype(np.float32) / 255
    wmask = cv2.GaussianBlur(wmask, (0, 0), 0.6)[..., None]

    # contact shadow under the card (always) + offset soft drop shadow
    d = max(2, int(L * rng.uniform(0.004, 0.012)))
    dx, dy = int(d * rng.uniform(-1, 1)), int(d * rng.uniform(0.3, 1.2))
    sh = np.roll(wmask[..., 0], (dy, dx), (0, 1))
    sh = cv2.GaussianBlur(sh, (0, 0), L * 0.006)
    bg *= (1 - rng.uniform(0.25, 0.45) * sh[..., None])
    img = bg * (1 - wmask) + warped * wmask

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # lighting: global vignette + optional strong uneven gradient / hotspot
    vig = 1 - 0.18 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) / 2
    light = vig
    if params["uneven"]:
        ang = rng.uniform(0, 2 * np.pi)
        g = ((xx - W / 2) * math.cos(ang) + (yy - H / 2) * math.sin(ang)) / (max(W, H) / 2)
        strength = rng.uniform(0.18, 0.32)
        light = light * (1 + strength * g)
        hx, hy = rng.uniform(0.2, 0.8) * W, rng.uniform(0.2, 0.8) * H
        hot = np.exp(-(((xx - hx) ** 2 + (yy - hy) ** 2) / (2 * (0.35 * max(W, H)) ** 2)))
        light = light * (0.9 + 0.22 * hot)
    img *= light[..., None]
    # colour cast (white balance)
    t = rng.uniform(-1, 1)  # white balance: cool (t<0) .. warm (t>0)
    cast = np.array([1 - 0.06 * t, 1 + rng.uniform(-0.01, 0.01), 1 + 0.06 * t], np.float32)  # BGR
    img *= cast[None, None, :]

    if params["shadow"]:  # soft shadow of the phone / hand falling across part of the card
        poly = []
        side = rng.integers(4)
        c = quad.mean(0)
        r = max(W, H)
        a0 = rng.uniform(0, 2 * np.pi)
        pts = [c + np.array([math.cos(a0 + t), math.sin(a0 + t)]) * r * rng.uniform(0.3, 0.9) for t in np.linspace(-0.9, 0.9, 5)]
        far = [c + np.array([math.cos(a0 + t), math.sin(a0 + t)]) * r * 2 for t in (0.9, -0.9)]
        poly = np.array(pts + far, np.int32)
        sm = np.zeros((H, W), np.uint8)
        cv2.fillPoly(sm, [poly], 255)
        sm = cv2.GaussianBlur(sm, (0, 0), L * rng.uniform(0.02, 0.05)).astype(np.float32) / 255
        img *= (1 - rng.uniform(0.25, 0.42) * sm)[..., None]

    if params["glare"]:
        gx, gy = quad.mean(0) + rng.uniform(-0.25, 0.25, 2) * np.array([W, H]) * 0.5
        gs = L * rng.uniform(0.06, 0.12)
        gl = np.exp(-(((xx - gx) ** 2) / (2 * (gs * 1.8) ** 2) + ((yy - gy) ** 2) / (2 * gs ** 2)))
        img += (gl * rng.uniform(40, 80))[..., None] * wmask

    if params["blur_sigma"] > 0:
        img = cv2.GaussianBlur(img, (0, 0), params["blur_sigma"])
    if params["motion_len"] > 0:
        k = np.zeros((params["motion_len"], params["motion_len"]), np.float32)
        k[params["motion_len"] // 2, :] = 1
        Mk = cv2.getRotationMatrix2D((params["motion_len"] / 2 - .5, params["motion_len"] / 2 - .5), rng.uniform(0, 180), 1)
        k = cv2.warpAffine(k, Mk, k.shape[::-1])
        k /= k.sum()
        img = cv2.filter2D(img, -1, k)
    # sensor noise (slightly luminance-correlated) and mild ISP sharpening
    lum = img.mean(2, keepdims=True) / 255
    img += rng.normal(0, params["noise_sigma"], img.shape).astype(np.float32) * (0.6 + 0.6 * (1 - lum))
    if params["blur_sigma"] == 0 and params["motion_len"] == 0:
        bl = cv2.GaussianBlur(img, (0, 0), 1.0)
        img = cv2.addWeighted(img, 1.25, bl, -0.25, 0)
    out = np.clip(img, 0, 255).astype(np.uint8)
    return out, quad, kinds
