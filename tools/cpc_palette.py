"""Amstrad CPC palette definitions shared by the sprite pipeline.

The CPC has 27 hardware colours (each RGB channel is 0%, 50% or 100%).
Mode 0 shows 16 of them at once via pens 0-15. Both fighters are on screen
together, so every character shares one game palette.
"""

# Firmware colour number -> (name, RGB, hardware ink number for the Gate Array)
HW_COLOURS = {
    0: ("Black", (0x00, 0x00, 0x00), 0x54),
    1: ("Blue", (0x00, 0x00, 0x80), 0x44),
    2: ("Bright Blue", (0x00, 0x00, 0xFF), 0x55),
    3: ("Red", (0x80, 0x00, 0x00), 0x5C),
    4: ("Magenta", (0x80, 0x00, 0x80), 0x58),
    5: ("Mauve", (0x80, 0x00, 0xFF), 0x5D),
    6: ("Bright Red", (0xFF, 0x00, 0x00), 0x4C),
    7: ("Purple", (0xFF, 0x00, 0x80), 0x45),
    8: ("Bright Magenta", (0xFF, 0x00, 0xFF), 0x4D),
    9: ("Green", (0x00, 0x80, 0x00), 0x56),
    10: ("Cyan", (0x00, 0x80, 0x80), 0x46),
    11: ("Sky Blue", (0x00, 0x80, 0xFF), 0x57),
    12: ("Yellow", (0x80, 0x80, 0x00), 0x5E),
    13: ("White", (0x80, 0x80, 0x80), 0x40),
    14: ("Pastel Blue", (0x80, 0x80, 0xFF), 0x5F),
    15: ("Orange", (0xFF, 0x80, 0x00), 0x4E),
    16: ("Pink", (0xFF, 0x80, 0x80), 0x47),
    17: ("Pastel Magenta", (0xFF, 0x80, 0xFF), 0x4F),
    18: ("Bright Green", (0x00, 0xFF, 0x00), 0x52),
    19: ("Sea Green", (0x00, 0xFF, 0x80), 0x42),
    20: ("Bright Cyan", (0x00, 0xFF, 0xFF), 0x53),
    21: ("Lime", (0x80, 0xFF, 0x00), 0x5A),
    22: ("Pastel Green", (0x80, 0xFF, 0x80), 0x59),
    23: ("Pastel Cyan", (0x80, 0xFF, 0xFF), 0x5B),
    24: ("Bright Yellow", (0xFF, 0xFF, 0x00), 0x4A),
    25: ("Pastel Yellow", (0xFF, 0xFF, 0x80), 0x43),
    26: ("Bright White", (0xFF, 0xFF, 0xFF), 0x4B),
}

# Game palette: pen -> firmware colour. Pen 0 is the transparent/background
# pen; pen 15 is also black so sprites can carry a solid outline that is not
# treated as transparent. Pens 13-14 are left for backgrounds.
GAME_PALETTE = [
    0,   # 0  transparent / background black
    1,   # 1  navy        (Trump suit, shading)
    2,   # 2  bright blue (suit highlight, Putin tie)
    3,   # 3  dark red    (skin shadow, mouths)
    6,   # 4  bright red  (Trump tie)
    15,  # 5  orange      (Trump skin)
    16,  # 6  pink        (Putin skin)
    25,  # 7  pastel yellow (hair highlight)
    12,  # 8  olive       (hair shadow)
    13,  # 9  grey        (Putin suit, Putin hair)
    26,  # 10 white       (shirts, eyes)
    14,  # 11 pastel blue (grey-suit highlight)
    24,  # 12 bright yellow (Trump hair)
    10,  # 13 cyan        (background)
    9,   # 14 green       (background)
    0,   # 15 black       (sprite outline, opaque)
]

TRANSPARENT = 0
OUTLINE = 15


def pen_rgb(pen):
    return HW_COLOURS[GAME_PALETTE[pen]][1]


def palette_hex():
    return ["#%02X%02X%02X" % pen_rgb(p) for p in range(16)]
