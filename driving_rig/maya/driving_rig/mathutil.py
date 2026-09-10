"""Pure-Python maths for the importer — no Maya, no numpy, fully unit-tested outside Maya.

Conventions (match Godot and Maya): right-handed, Y-up, column vectors, quaternions xyzw.

Rotation order: the chassis and camera use Maya rotate order **zxy** (rotate Z first, then
X, then Y, i.e. R = Ry · Rx · Rz). Heading (Y) is outermost, so a car can spin through any
number of turns with no gimbal trouble; the singularity sits at ±90° *pitch* (nose straight
up), where cars rarely go — and the continuity unroll handles it when they do. Maya's
default xyz would put the singularity at ±90° *heading*, which a car crosses constantly.
"""
from __future__ import annotations

import math

TAU = 2.0 * math.pi
ROTATE_ORDER_ZXY = 2   # Maya rotateOrder enum: xyz 0, yzx 1, zxy 2, xzy 3, yxz 4, zyx 5


# --- vectors (3-tuples) -------------------------------------------------------

def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_len(a):
    return math.sqrt(v_dot(a, a))


def v_norm(a):
    ln = v_len(a)
    return (a[0] / ln, a[1] / ln, a[2] / ln) if ln > 1e-12 else (0.0, 0.0, 0.0)


# --- quaternions (x, y, z, w) -------------------------------------------------

def q_norm(q):
    ln = math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
    return (q[0] / ln, q[1] / ln, q[2] / ln, q[3] / ln)


def q_slerp(a, b, f):
    """Shortest-arc slerp. Inputs need not be hemisphere-aligned."""
    dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
    if dot < 0.0:
        b = (-b[0], -b[1], -b[2], -b[3])
        dot = -dot
    if dot > 0.9995:
        return q_norm(tuple(a[i] + (b[i] - a[i]) * f for i in range(4)))
    th = math.acos(dot)
    s = math.sin(th)
    wa = math.sin((1.0 - f) * th) / s
    wb = math.sin(f * th) / s
    return tuple(a[i] * wa + b[i] * wb for i in range(4))


def q_to_matrix(q):
    """3×3 rotation matrix (rows), column-vector convention: v' = M · v."""
    x, y, z, w = q
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def m_mul_v(m, v):
    return (v_dot(m[0], v), v_dot(m[1], v), v_dot(m[2], v))


def m_mul(a, b):
    return tuple(tuple(sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)) for r in range(3))


def q_rotate(q, v):
    return m_mul_v(q_to_matrix(q), v)


# --- Euler zxy ----------------------------------------------------------------

def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def euler_zxy_to_matrix(e):
    """(rx, ry, rz) radians, Maya rotate order zxy → R = Ry · Rx · Rz."""
    return m_mul(rot_y(e[1]), m_mul(rot_x(e[0]), rot_z(e[2])))


def matrix_to_euler_zxy(m):
    """Principal solution, |rx| ≤ 90°. For R = Ry·Rx·Rz:
       m[1][2] = −sin rx,  m[0][2] = sin ry·cos rx,  m[2][2] = cos ry·cos rx,
       m[1][0] = cos rx·sin rz,  m[1][1] = cos rx·cos rz."""
    sx = max(-1.0, min(1.0, -m[1][2]))
    rx = math.asin(sx)
    if abs(sx) < 0.999999:
        ry = math.atan2(m[0][2], m[2][2])
        rz = math.atan2(m[1][0], m[1][1])
    else:   # gimbal: only ry ± rz is defined; put it all in ry
        rz = 0.0
        ry = math.atan2(-m[2][0], m[0][0])
    return (rx, ry, rz)


def _wrap_near(a, ref):
    return a + TAU * round((ref - a) / TAU)


def euler_closest(e, prev):
    """The equivalent zxy solution closest to `prev` — both algebraic solutions, each
    shifted by whole turns per axis. This is the continuity unroll: no 180° flips, and
    heading keeps accumulating through multiple turns."""
    best = None
    best_d = None
    for cand in (e, (math.pi - e[0], e[1] + math.pi, e[2] + math.pi)):
        c = tuple(_wrap_near(cand[i], prev[i]) for i in range(3))
        d = sum((c[i] - prev[i]) ** 2 for i in range(3))
        if best_d is None or d < best_d:
            best, best_d = c, d
    return best


def quats_to_euler_zxy(quats):
    """Sequence of quaternions → continuous zxy Euler sequence (radians)."""
    out = []
    prev = None
    for q in quats:
        e = matrix_to_euler_zxy(q_to_matrix(q))
        if prev is not None:
            e = euler_closest(e, prev)
        out.append(e)
        prev = e
    return out


# --- camera -------------------------------------------------------------------

def vfov_to_focal_mm(vfov_deg, vertical_aperture_in=0.945):
    """Godot Camera3D.fov is vertical (keep_aspect = KEEP_HEIGHT). Maya camera with
    filmFit = vertical: focal = (aperture_mm / 2) / tan(vfov / 2)."""
    return (vertical_aperture_in * 25.4 * 0.5) / math.tan(math.radians(vfov_deg) * 0.5)
