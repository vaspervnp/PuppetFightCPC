"""Build, animate and render the Puppet Fight characters in Blender.

Run inside Blender (via the Blender MCP or `blender -b -P`). Set the globals
REPO (repo root as seen by Blender) and CHARACTERS before exec'ing, e.g.:

    REPO = r"\\\\wsl.localhost\\Ubuntu\\home\\vasilhs\\repos\\PuppetFightCPC"
    CHARACTERS = ["trump", "putin"]
    exec(open(REPO + r"\\tools\\blender_puppets.py").read())

Each character gets its own scene ("PF_<name>") so nothing in the user's
other scenes is touched. Puppets are rigid parts parented to joint empties,
which keeps the felt-puppet look and makes posing a matter of rotating joints.

Every frame is rendered twice with Workbench at 256x256:
  <move>_<n>_id.png    flat material colours (decoded back to material ids)
  <move>_<n>_lit.png   white studio-lit pass (decoded to a light level)
tools/make_sprites.py turns those into 32x64 Mode 0 sprites.
"""
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector

if "REPO" not in globals():
    REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARACTERS = globals().get("CHARACTERS", ["trump", "putin"])
RENDER = globals().get("RENDER", True)

RES = 256           # render size; downsampled 8x4 to 32x64 Mode 0 pixels
CAM_YAW = 30.0      # degrees; 3/4 view of a fighter facing +X
FRAME_UNITS = 2.0   # world units covered by the 64-line sprite height
HEAD_TURN = -25.0   # heads face the viewer a little more than the bodies do


# --------------------------------------------------------------------------
# Character specs
# --------------------------------------------------------------------------
# Material names are looked up in tools/make_sprites.py for colour ramps.

TRUMP = dict(
    name="trump",
    scale=1.0,
    thigh=0.27, shin=0.27, leg_r=0.075, hip_w=0.12,
    torso_h=0.50, torso_size=(0.26, 0.31, 0.30), belly=0.06,
    shoulder_w=0.29, upper_arm=0.30, forearm=0.28, arm_r=0.075,
    hand_r=0.052,                      # famously small hands
    head_size=(0.33, 0.31, 0.34), neck=0.05,
    suit="suit_navy", pants="suit_navy", shirt="shirt", tie="tie_red",
    tie_len=0.56, skin="skin_orange", hair="hair_yellow", shoe="shoe",
)

PUTIN = dict(
    name="putin",
    scale=0.93,
    thigh=0.27, shin=0.27, leg_r=0.07, hip_w=0.11,
    torso_h=0.48, torso_size=(0.20, 0.27, 0.28), belly=0.0,
    shoulder_w=0.26, upper_arm=0.30, forearm=0.28, arm_r=0.072,
    hand_r=0.065,
    head_size=(0.30, 0.28, 0.36), neck=0.05,
    suit="suit_grey", pants="suit_grey", shirt="shirt", tie="tie_blue",
    tie_len=0.34, skin="skin_pink", hair="hair_grey", shoe="shoe",
)

SPECS = {"trump": TRUMP, "putin": PUTIN}

MATERIALS = [
    "suit_navy", "suit_grey", "shirt", "tie_red", "tie_blue",
    "skin_orange", "skin_pink", "hair_yellow", "hair_grey", "shoe",
    "eye_white", "pupil", "mouth", "brow", "phone",
    # arms get their own materials (near/far) so the sprite converter can
    # draw separation lines where a sleeve crosses the jacket
    "arm_navy_n", "arm_navy_f", "arm_grey_n", "arm_grey_f",
]


def id_colour(i):
    """Distinct flat colour per material, decoded later by exact match."""
    r = (i * 67 + 40) % 256
    g = (i * 131 + 90) % 256
    b = (i * 199 + 20) % 256
    return (r / 255, g / 255, b / 255)


# --------------------------------------------------------------------------
# Construction helpers
# --------------------------------------------------------------------------

def get_material(name):
    m = bpy.data.materials.get("PF_" + name)
    if m is None:
        m = bpy.data.materials.new("PF_" + name)
    c = id_colour(MATERIALS.index(name))
    m.diffuse_color = (c[0], c[1], c[2], 1.0)
    return m


def new_empty(sc, name, parent, loc):
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = 0.05
    sc.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_mode = "XYZ"
    return o


def new_part(sc, name, kind, parent, loc, size, mat, rot=(0, 0, 0)):
    """kind: sphere | cyl | box. size is half-extents (x, y, z)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    if kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0,
                              radius2=1.0, depth=2.0)
    else:
        bmesh.ops.create_cube(bm, size=2.0)
    bm.to_mesh(me)
    bm.free()
    if kind != "box":
        me.shade_smooth()
    me.materials.append(get_material(mat))
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.parent = parent
    o.location = loc
    o.scale = size
    o.rotation_euler = [math.radians(a) for a in rot]
    return o


def limb(sc, prefix, parent, length, radius, mat, end_cap=True):
    """Cylinder hanging down (-Z) from the parent joint origin."""
    new_part(sc, prefix + "_seg", "cyl", parent, (0, 0, -length / 2),
             (radius, radius, length / 2), mat)
    new_part(sc, prefix + "_top", "sphere", parent, (0, 0, 0),
             (radius, radius, radius), mat)
    if end_cap:
        new_part(sc, prefix + "_end", "sphere", parent, (0, 0, -length),
                 (radius, radius, radius), mat)


# --------------------------------------------------------------------------
# Heads: the caricature lives here
# --------------------------------------------------------------------------

def trump_head(sc, s, head):
    hx, hy, hz = s["head_size"]
    sk = s["skin"]
    new_part(sc, "head", "sphere", head, (0, 0, hz), (hx, hy, hz), sk)
    # heavy jowls / jaw
    new_part(sc, "jaw", "sphere", head, (0.05, 0, hz * 0.55), (hx * 0.9, hy * 0.95, hz * 0.55), sk)
    new_part(sc, "nose", "sphere", head, (hx * 0.98, 0, hz * 1.0), (0.06, 0.05, 0.06), sk)
    for side, y in (("R", -1), ("L", 1)):
        new_part(sc, "ear_" + side, "sphere", head, (-0.02, y * hy * 0.98, hz * 1.0), (0.05, 0.03, 0.08), sk)
        # squinting eyes: small, narrow
        new_part(sc, "eye_" + side, "sphere", head, (hx * 0.9, y * 0.12, hz * 1.22), (0.05, 0.075, 0.04), "eye_white")
        new_part(sc, "pupil_" + side, "sphere", head, (hx * 0.98, y * 0.12, hz * 1.21), (0.035, 0.035, 0.035), "pupil")
        new_part(sc, "brow_" + side, "box", head, (hx * 0.92, y * 0.12, hz * 1.36), (0.04, 0.08, 0.022), "hair_yellow", rot=(y * 8, 0, 0))
    # pursed "O" mouth, pushed out past the jowls
    new_part(sc, "mouth", "sphere", head, (hx * 1.08, 0, hz * 0.66), (0.05, 0.075, 0.05), "mouth")
    # the hair: a big swoop forward over the forehead plus a mane at the back
    hair = s["hair"]
    new_part(sc, "hair_top", "sphere", head, (-0.02, 0, hz * 1.62), (hx * 1.08, hy * 1.08, hz * 0.55), hair)
    new_part(sc, "hair_swoop", "sphere", head, (hx * 0.62, -0.03, hz * 1.66), (0.2, 0.26, 0.11), hair, rot=(0, -15, 0))
    new_part(sc, "hair_back", "sphere", head, (-hx * 0.55, 0, hz * 1.15), (hx * 0.62, hy * 1.04, hz * 0.7), hair)


def putin_head(sc, s, head):
    hx, hy, hz = s["head_size"]
    sk = s["skin"]
    # egg-shaped, tall forehead
    new_part(sc, "head", "sphere", head, (0, 0, hz), (hx, hy, hz), sk)
    new_part(sc, "cheeks", "sphere", head, (0.04, 0, hz * 0.62), (hx * 0.85, hy * 0.92, hz * 0.5), sk)
    new_part(sc, "nose", "sphere", head, (hx * 0.98, 0, hz * 0.88), (0.05, 0.035, 0.07), sk)
    for side, y in (("R", -1), ("L", 1)):
        new_part(sc, "ear_" + side, "sphere", head, (-0.02, y * hy * 0.98, hz * 0.95), (0.05, 0.03, 0.08), sk)
        # cold narrow eyes
        new_part(sc, "eye_" + side, "sphere", head, (hx * 0.92, y * 0.11, hz * 1.08), (0.045, 0.07, 0.03), "eye_white")
        new_part(sc, "pupil_" + side, "sphere", head, (hx * 0.99, y * 0.11, hz * 1.08), (0.032, 0.032, 0.03), "pupil")
        new_part(sc, "brow_" + side, "box", head, (hx * 0.95, y * 0.11, hz * 1.2), (0.03, 0.075, 0.016), "brow", rot=(-y * 6, 0, 0))
    # thin smirk
    new_part(sc, "mouth", "box", head, (hx * 0.98, 0.02, hz * 0.62), (0.04, 0.08, 0.018), "mouth", rot=(6, 0, 0))
    # receding thin hair: back and sides only, high bald dome
    hair = s["hair"]
    new_part(sc, "hair_back", "sphere", head, (-hx * 0.35, 0, hz * 1.25), (hx * 0.75, hy * 1.03, hz * 0.72), hair)
    new_part(sc, "hair_front", "sphere", head, (hx * 0.25, 0, hz * 1.78), (hx * 0.45, hy * 0.55, hz * 0.18), hair)


HEADS = {"trump": trump_head, "putin": putin_head}


# --------------------------------------------------------------------------
# Body
# --------------------------------------------------------------------------

def build_character(s):
    scn = "PF_" + s["name"]
    old = bpy.data.scenes.get(scn)
    if old is not None:
        for o in list(old.collection.all_objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    sc = bpy.data.scenes.new(scn)

    J = {}
    hip_z = s["thigh"] + s["shin"] + 0.08
    root = J["root"] = new_empty(sc, "root", None, (0, 0, hip_z))
    root.scale = (s["scale"],) * 3

    # legs: near = -Y (towards camera), far = +Y
    for side, y in (("N", -1), ("F", 1)):
        hp = J["hp" + side] = new_empty(sc, "hip" + side, root, (0, y * s["hip_w"], 0))
        limb(sc, "thigh" + side, hp, s["thigh"], s["leg_r"], s["pants"])
        kn = J["kn" + side] = new_empty(sc, "knee" + side, hp, (0, 0, -s["thigh"]))
        limb(sc, "shin" + side, kn, s["shin"], s["leg_r"] * 0.95, s["pants"], end_cap=False)
        an = J["an" + side] = new_empty(sc, "ankle" + side, kn, (0, 0, -s["shin"]))
        new_part(sc, "shoe" + side, "sphere", an, (0.06, 0, -0.03), (0.13, 0.075, 0.06), s["shoe"])

    # pelvis + torso
    new_part(sc, "pelvis", "sphere", root, (0, 0, 0.02), (0.17, s["hip_w"] + 0.08, 0.1), s["pants"])
    torso = J["torso"] = new_empty(sc, "torso", root, (0, 0, 0))
    tx, ty, tz = s["torso_size"]
    th = s["torso_h"]
    new_part(sc, "jacket", "sphere", torso, (s["belly"] * 0.5, 0, th * 0.5), (tx + s["belly"], ty, tz), s["suit"])
    new_part(sc, "chest", "sphere", torso, (0, 0, th * 0.78), (tx * 0.92, ty * 1.02, tz * 0.5), s["suit"])
    # white shirt V and tie on the front (+X)
    front = tx + s["belly"] * 0.6
    new_part(sc, "shirt", "sphere", torso, (front * 0.72, 0, th * 0.86), (0.07, 0.1, 0.14), s["shirt"])
    new_part(sc, "tie_knot", "sphere", torso, (front * 0.86, 0, th * 0.93), (0.035, 0.04, 0.035), s["tie"])
    tl = s["tie_len"]
    new_part(sc, "tie", "box", torso, (front * 0.9 + 0.02, 0, th * 0.93 - tl / 2), (0.02, 0.045, tl / 2), s["tie"], rot=(0, -8, 0))

    # neck + head
    neck = J["head"] = new_empty(sc, "neck", torso, (0.02, 0, th + s["neck"]))
    new_part(sc, "neck_mesh", "cyl", neck, (0, 0, -0.03), (0.08, 0.08, 0.06), s["skin"])
    HEADS[s["name"]](sc, s, neck)

    # arms
    for side, y in (("N", -1), ("F", 1)):
        sh = J["sh" + side] = new_empty(sc, "shoulder" + side, torso, (0, y * s["shoulder_w"], th * 0.86))
        arm = s["suit"].replace("suit", "arm") + "_" + side.lower()
        limb(sc, "upperarm" + side, sh, s["upper_arm"], s["arm_r"], arm)
        el = J["el" + side] = new_empty(sc, "elbow" + side, sh, (0, 0, -s["upper_arm"]))
        limb(sc, "forearm" + side, el, s["forearm"], s["arm_r"] * 0.95, arm, end_cap=False)
        new_part(sc, "cuff" + side, "cyl", el, (0, 0, -s["forearm"] + 0.01), (s["arm_r"] * 0.85,) * 2 + (0.02,), s["shirt"])
        wr = J["wr" + side] = new_empty(sc, "wrist" + side, el, (0, 0, -s["forearm"]))
        r = s["hand_r"]
        new_part(sc, "hand" + side, "sphere", wr, (0, 0, -r * 0.9), (r, r * 0.9, r * 1.1), s["skin"])

    if s["name"] == "trump":
        # the phone used by his Tweet Storm special; hidden unless posed
        ph = new_part(sc, "phone", "box", J["wrN"], (0.04, 0, -0.08), (0.015, 0.035, 0.06), "phone")
        J["phone"] = ph

    setup_render(sc)
    return sc, J


# --------------------------------------------------------------------------
# Camera / render
# --------------------------------------------------------------------------

def setup_render(sc):
    cam_data = bpy.data.cameras.new("PF_cam_" + sc.name)
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FRAME_UNITS
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    target = Vector((0.12, 0, FRAME_UNITS / 2 - 0.04))
    yaw = math.radians(CAM_YAW)
    d = Vector((math.sin(yaw), -math.cos(yaw), 0.0))
    cam.location = target + d * 10
    cam.rotation_euler = (math.radians(90), 0, yaw)

    r = sc.render
    r.engine = "BLENDER_WORKBENCH"
    r.resolution_x = RES
    r.resolution_y = RES
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    sc.display.render_aa = "OFF"
    sh = sc.display.shading
    sh.show_cavity = False
    sh.show_shadows = False
    sh.show_object_outline = False
    sh.show_specular_highlight = False
    try:
        sc.view_settings.view_transform = "Raw"
    except TypeError:
        sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.fps = 12


# --------------------------------------------------------------------------
# Poses
# --------------------------------------------------------------------------
# Angles in degrees. Limbs: positive = swing forward (toward opponent).
# kn = knee bend (positive folds the shin back), el = elbow bend (positive
# folds the forearm forward/up). torso/head/lean: positive = lean forward.
# twist = turn the torso so the near shoulder comes forward (punches).
# spin = turn the whole puppet about the vertical axis (back kick); turn
# overrides the head's own yaw so it can look back over the shoulder.
# ab = arm abduction (raise sideways). x/z = root offset; air = height above
# ground (otherwise the lowest point is snapped to the floor).
# wide = render a 64x64 frame (for horizontal/falling poses). The wider camera
# is centred on the same point, so the engine draws it 16 Mode 0 pixels to
# the left of where a normal 32-wide frame would go.

STANCE = dict(lean=0, torso=6, head=-4,
              shN=35, elN=110, shF=50, elF=105,
              hpN=18, knN=22, hpF=-18, knF=14)


def P(**kw):
    p = dict(STANCE)
    p.update(kw)
    return p


COMMON_MOVES = {
    "idle": [
        P(),
        P(torso=8, knN=26, knF=18, elN=114, elF=110),
        P(torso=10, knN=30, knF=22, elN=118, elF=112, head=-2),
        P(torso=8, knN=26, knF=18, elN=114, elF=110),
    ],
    "walk": [
        P(hpN=30, knN=10, hpF=-25, knF=25, torso=10),
        P(hpN=5, knN=40, hpF=0, knF=15, torso=8),
        P(hpN=-25, knN=25, hpF=30, knF=10, torso=10),
        P(hpN=0, knN=15, hpF=5, knF=40, torso=8),
    ],
    "crouch": [
        P(hpN=35, knN=55, hpF=-5, knF=45, torso=12),
        P(hpN=60, knN=100, hpF=25, knF=95, torso=18),
        P(hpN=80, knN=135, hpF=45, knF=130, torso=22, head=-12),
    ],
    "jump": [
        P(hpN=50, knN=85, hpF=20, knF=80, torso=20, elN=90, elF=90),
        P(hpN=70, knN=110, hpF=55, knF=115, torso=5, shN=80, elN=60, shF=90, elF=70),
        P(hpN=20, knN=30, hpF=-10, knF=25, torso=0, shN=60, elN=80, shF=70, elF=80),
    ],
    "punch": [
        P(torso=0, twist=-20, shN=10, elN=125, shF=40, elF=110),
        P(torso=18, twist=45, shN=88, elN=2, shF=30, elF=120, hpN=28, knN=20, x=0.1),
        P(torso=10, twist=20, shN=70, elN=50, shF=40, elF=110, x=0.04),
    ],
    "kick": [
        P(hpN=85, knN=120, hpF=-5, knF=8, torso=-8, shN=50, elN=100),
        P(hpN=95, knN=5, hpF=-10, knF=5, torso=-22, lean=-6, shN=20, elN=90, shF=70, elF=60),
        P(hpN=60, knN=70, hpF=-8, knF=8, torso=-10),
    ],
    "sweep": [
        P(hpN=60, knN=100, hpF=25, knF=95, torso=18),
        P(hpN=85, knN=5, hpF=40, knF=135, torso=30, shF=-20, elF=40, shN=60, elN=60, x=-0.05),
        P(hpN=70, knN=60, hpF=30, knF=120, torso=24),
    ],
    # anti-air: dip, drive up from the legs, fist past the head
    "uppercut": [
        P(hpN=40, knN=70, hpF=10, knF=60, torso=24, twist=-15, shN=-15, elN=95, x=0.02),
        P(hpN=25, knN=35, hpF=-5, knF=25, torso=10, twist=20, shN=80, elN=100, x=0.06),
        P(hpN=10, knN=5, hpF=-15, knF=5, torso=-12, twist=40, shN=140, elN=20, shF=20, elF=110, head=-25, x=0.08),
        P(hpN=20, knN=25, hpF=-15, knF=15, torso=0, twist=15, shN=110, elN=60, x=0.04),
    ],
    # spinning mule kick: turn away, then drive the near leg straight back
    # into the opponent while looking over the shoulder
    "backkick": [
        P(spin=60, turn=-80, hpN=70, knN=110, torso=10, shN=40, elN=100),
        P(spin=150, turn=-165, hpN=-30, knN=95, torso=30, shN=20, elN=90, shF=30, elF=90),
        P(spin=170, turn=-185, hpN=-95, knN=5, hpF=10, knF=10, torso=50, shN=-20, elN=60, shF=-30, elF=60, x=0.05),
        P(spin=60, turn=-80, hpN=30, knN=60, torso=10, shN=40, elN=100),
    ],
    "block": [
        P(shN=60, elN=125, shF=65, elF=125, head=4),
        P(shN=80, elN=150, shF=85, elF=150, head=10, torso=12),
        P(shN=82, elN=155, shF=88, elF=155, head=12, torso=14, x=-0.04),
    ],
    "hit": [
        P(torso=-12, head=-20, shN=20, elN=80, shF=30, elF=70, x=-0.04),
        P(torso=-22, head=-30, lean=-6, shN=-10, elN=40, shF=-5, elF=40, hpN=30, x=-0.1),
        P(torso=-8, head=-10, shN=20, elN=80, shF=30, elF=80, x=-0.05),
    ],
    "ko": [
        P(torso=-20, head=-30, shN=-20, elN=30, shF=-10, elF=30, hpN=30, knN=10, x=-0.05),
        P(lean=-35, torso=-15, head=-25, shN=60, elN=20, shF=80, elF=20, hpN=50, knN=30, hpF=10, x=-0.15, wide=True),
        P(lean=-70, torso=-10, head=-10, shN=110, elN=20, shF=120, elF=10, hpN=70, knN=40, hpF=40, knF=20, x=-0.25, wide=True),
        P(lean=-90, torso=0, head=0, shN=150, elN=10, shF=165, elF=10, hpN=15, knN=10, hpF=5, knF=5, x=-0.3, wide=True),
    ],
}

TRUMP_MOVES = {
    # Tweet Storm: whips out the phone and fires a tweet (projectile is a
    # separate sprite to be drawn later)
    "special": [
        P(phone=True, shN=-40, elN=120, torso=-10, shF=40, elF=90),
        P(phone=True, shN=-60, elN=150, torso=-18, head=-8, shF=60, elF=60),
        P(phone=True, shN=100, elN=10, torso=20, twist=40, shF=20, elF=100, x=0.1),
        P(phone=True, shN=70, elN=40, torso=12, twist=20, shF=30, elF=100, x=0.04),
    ],
    # "Tremendous!" double thumbs-up shimmy
    "victory": [
        P(shN=40, elN=120, shF=40, elF=120, ab=30, torso=0, head=-10),
        P(shN=70, elN=150, shF=70, elF=150, ab=45, torso=-6, head=-18, knN=10, knF=10),
        P(shN=55, elN=100, shF=55, elF=100, ab=60, torso=-10, head=-14, knN=10, knF=10),
    ],
}

PUTIN_MOVES = {
    # Judo Throw: grab, hip load, throw
    "special": [
        P(shN=80, elN=40, shF=75, elF=50, torso=20, twist=25, hpN=35, knN=40, x=0.1),
        P(shN=100, elN=90, shF=95, elF=100, torso=35, hpN=20, knN=50, hpF=-10, knF=40, x=0.08),
        P(shN=160, elN=60, shF=150, elF=70, torso=-10, head=-15, hpN=10, knN=20, hpF=-20, knF=10),
        P(shN=40, elN=10, shF=30, elF=10, torso=30, head=10, hpN=30, knN=50, hpF=-15, knF=30, x=0.05),
    ],
    # strongman flex
    "victory": [
        P(shN=10, elN=90, shF=10, elF=90, ab=50, torso=0, head=0),
        P(shN=0, elN=140, shF=0, elF=140, ab=80, torso=-4, head=-6),
        P(shN=0, elN=150, shF=0, elF=150, ab=90, torso=-6, head=-10, knN=8, knF=8),
    ],
}

CHAR_MOVES = {"trump": TRUMP_MOVES, "putin": PUTIN_MOVES}

MOVE_ORDER = ["idle", "walk", "crouch", "jump", "punch", "kick", "sweep",
              "uppercut", "backkick", "block", "hit", "ko", "special", "victory"]


def apply_pose(sc, J, p):
    rad = math.radians
    J["root"].rotation_euler = (0, rad(p.get("lean", 0)), rad(p.get("spin", 0)))
    J["torso"].rotation_euler = (0, rad(p.get("torso", 0)), rad(p.get("twist", 0)))
    # the head counters the torso twist so the face keeps looking at the viewer
    turn = p.get("turn", HEAD_TURN) - p.get("twist", 0) * 0.8
    J["head"].rotation_euler = (0, rad(p.get("head", 0)), rad(turn))
    ab = p.get("ab", 0)
    for side, sgn in (("N", -1), ("F", 1)):
        J["sh" + side].rotation_euler = (rad(sgn * ab), rad(-p["sh" + side]), 0)
        J["el" + side].rotation_euler = (0, rad(-p["el" + side]), 0)
        J["hp" + side].rotation_euler = (0, rad(-p["hp" + side]), 0)
        J["kn" + side].rotation_euler = (0, rad(p["kn" + side]), 0)
        # keep feet flat-ish against the shin/thigh rotation
        J["an" + side].rotation_euler = (0, rad(p["hp" + side] - p["kn" + side]) * 0.6, 0)
    if "phone" in J:
        J["phone"].hide_render = not p.get("phone", False)
        J["phone"].hide_viewport = J["phone"].hide_render

    hip_z = J["root"]["hip_z"]
    J["root"].location = (p.get("x", 0), 0, hip_z)
    sc.view_layers[0].update()
    lowest = min((o.matrix_world @ Vector(c)).z
                 for o in sc.collection.all_objects
                 if o.type == "MESH" and not o.hide_render
                 for c in o.bound_box)
    J["root"].location = (p.get("x", 0), 0, hip_z - lowest + p.get("air", 0))


def key_pose(J, frame):
    for name, o in J.items():
        if name == "phone":
            o.keyframe_insert("hide_render", frame=frame)
            o.keyframe_insert("hide_viewport", frame=frame)
            continue
        o.keyframe_insert("rotation_euler", frame=frame)
        if name == "root":
            o.keyframe_insert("location", frame=frame)


def set_constant(sc):
    for o in sc.collection.all_objects:
        ad = o.animation_data
        if not ad or not ad.action:
            continue
        # Blender 5 layered actions: walk every channelbag
        fcurves = []
        if hasattr(ad.action, "layers") and ad.action.layers:
            for layer in ad.action.layers:
                for strip in layer.strips:
                    for bag in strip.channelbags:
                        fcurves.extend(bag.fcurves)
        else:
            fcurves = ad.action.fcurves
        for fc in fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"


def build_and_render(name):
    s = SPECS[name]
    sc, J = build_character(s)
    J["root"]["hip_z"] = J["root"].location.z

    moves = dict(COMMON_MOVES)
    moves.update(CHAR_MOVES[name])

    out_dir = os.path.join(REPO, "art", "render", name)
    os.makedirs(out_dir, exist_ok=True)

    frame = 1
    manifest = {"character": name, "moves": []}
    sc.timeline_markers.clear()
    for move in MOVE_ORDER:
        sc.timeline_markers.new(move, frame=frame)
        entry = {"name": move, "frames": []}
        for i, pose in enumerate(moves[move]):
            apply_pose(sc, J, pose)
            key_pose(J, frame)
            wide = pose.get("wide", False)
            entry["frames"].append({"frame": frame, "file": "%s_%d" % (move, i),
                                    "width": 64 if wide else 32,
                                    "offset_x": -16 if wide else 0})
            frame += 1
        manifest["moves"].append(entry)
    sc.frame_start = 1
    sc.frame_end = frame - 1
    set_constant(sc)

    manifest["materials"] = {m: [round(c * 255) for c in id_colour(i)] for i, m in enumerate(MATERIALS)}
    with open(os.path.join(out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)

    if RENDER:
        render_frames(sc, manifest, out_dir)
    return sc, manifest


def render_frames(sc, manifest, out_dir):
    win = bpy.context.window or bpy.context.window_manager.windows[0]
    prev_scene = win.scene
    win.scene = sc
    try:
        sh = sc.display.shading
        for move in manifest["moves"]:
            for fr in move["frames"]:
                sc.frame_set(fr["frame"])
                wide = fr["width"] == 64
                sc.render.resolution_x = RES * 2 if wide else RES
                sc.camera.data.ortho_scale = FRAME_UNITS * 2 if wide else FRAME_UNITS
                for pass_name in ("id", "lit"):
                    if pass_name == "id":
                        sh.light = "FLAT"
                        sh.color_type = "MATERIAL"
                    else:
                        sh.light = "STUDIO"
                        sh.color_type = "SINGLE"
                        sh.single_color = (1, 1, 1)
                    sc.render.filepath = os.path.join(out_dir, fr["file"] + "_" + pass_name + ".png")
                    with bpy.context.temp_override(window=win, scene=sc):
                        bpy.ops.render.render(write_still=True, scene=sc.name)
        sh.light = "STUDIO"
        sh.color_type = "MATERIAL"
        sc.render.resolution_x = RES
        sc.camera.data.ortho_scale = FRAME_UNITS
    finally:
        win.scene = prev_scene


def save_blend():
    """Write only the puppet scenes to art/blender/puppets.blend, leaving the
    user's open file untouched."""
    scenes = {s for s in bpy.data.scenes if s.name.startswith("PF_")}
    path = os.path.join(REPO, "art", "blender", "puppets.blend")
    bpy.data.libraries.write(path, scenes, fake_user=True)
    return path


results = {}
for _name in CHARACTERS:
    _sc, _man = build_and_render(_name)
    results[_name] = sum(len(m["frames"]) for m in _man["moves"])
results["blend"] = save_blend()
result = results
