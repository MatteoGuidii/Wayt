# Wayt — Brand Guide

## App Icon

The Wayt icon is a stylized **W** with an integrated **hourglass** shape, representing "wait time" — the core product concept.

### Icon Anatomy

The icon consists of 3 elements:

1. **Outer W Legs** — Two diagonal lines forming the left and right strokes of the W
2. **Inner Hourglass** — Two lines rising from the W base converging at a pinch point, topped by a horizontal bar and two angled lines forming a triangle
3. **Background** — Rounded rectangle with gradient fill

### Measurements (1024×1024 viewBox)

#### Background
- Viewbox: `1024 × 1024`
- Corner radius: `224`
- Fill: gradient (see Colors below)

#### Outer W Legs
- Left leg: `(150, 200)` → `(350, 824)`
- Right leg: `(874, 200)` → `(674, 824)`
- Stroke width: `80`
- Stroke cap: `round`

#### Inner Hourglass — Lower V
- Left line: `(350, 824)` → `(512, 560)`
- Right line: `(674, 824)` → `(512, 560)`
- Pinch point: `(512, 560)`
- Stroke width: `80`
- Stroke cap: `round`

#### Inner Hourglass — Upper Triangle
- Top bar: `(400, 336)` → `(624, 336)`
- Left side: `(400, 336)` → `(512, 560)`
- Right side: `(624, 336)` → `(512, 560)`
- Stroke width: `80`
- Stroke cap: `round`

#### Design Notes
- The upper triangle and lower V share the same angle ratio (0.5)
- The pinch point `(512, 560)` is where all inner lines converge
- The lower V connects directly to the outer W leg base points
- All strokes use `round` line caps for a friendly, modern feel

---

## Colors

### Primary — Background Gradient
- **Direction:** vertical, top to bottom
- **Top:** `#FFD600` (bright yellow)
- **Bottom:** `#CC7A00` (deep ochre)
- CSS: `linear-gradient(180deg, #FFD600 0%, #CC7A00 100%)`

### Logo Mark
- **Color:** `#FFFFFF` (pure white)

### Color Palette

| Role | Hex | Name |
|---|---|---|
| Gradient Start | `#FFD600` | Bright Yellow |
| Gradient End | `#CC7A00` | Deep Ochre |
| Logo / Mark | `#FFFFFF` | White |

### Color Psychology
- **Yellow:** Energy, optimism, warmth, attention — signals "go" and real-time awareness
- **Ochre gradient:** Grounds the brightness, adds depth and sophistication
- **White logo:** Clean, readable, accessible on the warm background

---

## Usage Rules

1. **Do not** rotate or skew the icon
2. **Do not** change the stroke widths or line positions
3. **Do not** use a flat color instead of the gradient for the primary icon
4. **Do not** add shadows, outlines, or effects to the mark
5. **Maintain** the rounded corners (`rx="224"` at 1024px scale)
6. The icon should always have **equal padding** on all sides when placed in containers

---

## File Reference

| File | Purpose |
|---|---|
| `wayt-icon.svg` | Production-ready app icon (1024×1024) |
