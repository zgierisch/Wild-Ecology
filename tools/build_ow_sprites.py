"""Build-time tool: converts the sourced "Gen 1-7 OV SPrites" 256x256 4x4
walk-cycle sheets (rows: down, left, right, up; columns: 4-frame walk cycle)
into Gen1Recomp's native NPC walker sprite format -- a 16x96 vertical strip
of 6 stacked 16x16 frames in the verified order:
  STAND: down=0, up=1, left=2 (right is drawn by the engine mirroring left)
  WALK:  down=3, up=4, left=5 (right mirrors left)

Run once (offline, not at mod load) to (re)generate assets/ow_sprites/.
Source row order (down, left, right, up) and per-frame vertical bob were
confirmed by visually inspecting 016.png (Pidgey) and 019.png (Rattata).
"""
import os
import re
import sys

from PIL import Image

SOURCE_DIR = os.path.join(os.path.dirname(__file__), "..", "Gen 1-7 OV SPrites")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "ow_sprites")

CELL_SIZE = 64
GRID_COLS = 4
ROW_DOWN, ROW_LEFT, ROW_RIGHT, ROW_UP = 0, 1, 2, 3
STAND_COL = 0
WALK_COL = 1
FRAME_SIZE = 16

DEX_FILENAME_RE = re.compile(r"^(\d{3})\.png$")


def crop_cell(sheet, row, col):
    x0 = col * CELL_SIZE
    y0 = row * CELL_SIZE
    return sheet.crop((x0, y0, x0 + CELL_SIZE, y0 + CELL_SIZE))


def union_bbox(cells):
    boxes = [c.getbbox() for c in cells if c.getbbox()]
    if not boxes:
        return None
    return (
        min(b[0] for b in boxes),
        min(b[1] for b in boxes),
        max(b[2] for b in boxes),
        max(b[3] for b in boxes),
    )


def fit_pair_to_frames(standCell, walkCell):
    """Crop BOTH the stand and walk cell to the SAME shared bounding box
    (their union), then scale/paste identically. Cropping+anchoring each
    frame independently to its OWN bbox erases the only real difference
    between the two poses -- a small relative vertical shift (the walk
    bob) -- because bottom-anchoring recenters away any offset. Using one
    shared crop window preserves that relative offset so the walk frame
    actually looks different from the stand frame once rendered."""
    box = union_bbox([standCell, walkCell])
    if not box:
        empty = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        return empty, empty

    standContent = standCell.crop(box)
    walkContent = walkCell.crop(box)
    w, h = standContent.size
    if w == 0 or h == 0:
        empty = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        return empty, empty

    scale = min(FRAME_SIZE / w, FRAME_SIZE / h, 1.0)
    newW = max(1, round(w * scale))
    newH = max(1, round(h * scale))
    pasteX = (FRAME_SIZE - newW) // 2
    pasteY = FRAME_SIZE - newH  # bottom-anchored, shared by both frames

    def place(content):
        resized = content.resize((newW, newH), Image.NEAREST)
        canvas = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
        canvas.paste(resized, (pasteX, pasteY), resized)
        return canvas

    return place(standContent), place(walkContent)


def build_walker_sheet(sourcePath):
    sheet = Image.open(sourcePath).convert("RGBA")

    downStand, downWalk = fit_pair_to_frames(crop_cell(sheet, ROW_DOWN, STAND_COL), crop_cell(sheet, ROW_DOWN, WALK_COL))
    upStand, upWalk = fit_pair_to_frames(crop_cell(sheet, ROW_UP, STAND_COL), crop_cell(sheet, ROW_UP, WALK_COL))
    leftStand, leftWalk = fit_pair_to_frames(crop_cell(sheet, ROW_LEFT, STAND_COL), crop_cell(sheet, ROW_LEFT, WALK_COL))

    frames = [downStand, upStand, leftStand, downWalk, upWalk, leftWalk]

    output = Image.new("RGBA", (FRAME_SIZE, FRAME_SIZE * len(frames)), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        output.paste(frame, (0, index * FRAME_SIZE), frame)
    return output


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    built, skipped = 0, 0

    for name in sorted(os.listdir(SOURCE_DIR)):
        match = DEX_FILENAME_RE.match(name)
        if not match:
            continue

        sourcePath = os.path.join(SOURCE_DIR, name)
        try:
            sheet = build_walker_sheet(sourcePath)
        except Exception as err:  # noqa: BLE001 -- report and continue
            print(f"SKIP {name}: {err}", file=sys.stderr)
            skipped += 1
            continue

        sheet.save(os.path.join(OUTPUT_DIR, name))
        built += 1

    print(f"Built {built} walker sheets into {OUTPUT_DIR} ({skipped} skipped)")


if __name__ == "__main__":
    main()
