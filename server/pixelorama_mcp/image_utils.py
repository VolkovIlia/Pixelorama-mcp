import base64
import io
import os
import shutil
import sys
import tempfile
from typing import Any, Callable, Dict, List

def _log(msg: str) -> None:
    print(f"[pixelorama-mcp] {msg}", file=sys.stderr, flush=True)

try:
    from PIL import Image
except ImportError:
    Image = None  # Pillow optional; handle_to_pixelart will fail gracefully


def handle_to_pixelart(args: Dict[str, Any], bridge_call: Callable) -> Dict[str, Any]:
    """Convert a photo/image to pixel art and import into Pixelorama."""
    if Image is None:
        raise RuntimeError("Pillow is required: pip install Pillow")

    img = load_image(args)
    target_w = args.get("width", 64)
    target_h = args.get("height", 64)
    colors = args.get("colors", 0)
    dither = args.get("dither", False)
    project_name = args.get("project_name", "pixelart")
    keep_aspect = args.get("keep_aspect", True)

    # Calculate final dimensions
    final_w, final_h = fit_dimensions(img, target_w, target_h, keep_aspect)

    # Resize with nearest-neighbor for pixel art look
    img = img.resize((final_w, final_h), Image.NEAREST)

    # Quantize colors if requested
    if colors > 0:
        dither_mode = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
        img = img.quantize(colors=colors, dither=dither_mode).convert("RGBA")

    # Ensure RGBA for PNG export
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    # Encode to base64 PNG
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64_png = base64.b64encode(buf.getvalue()).decode("ascii")

    # Create project and set region in Pixelorama
    bridge_call("project.create", {"name": project_name, "width": final_w, "height": final_h})
    bridge_call("pixel.set_region", {"x": 0, "y": 0, "data": b64_png, "format": "png", "mode": "replace"})

    return {"ok": True, "width": final_w, "height": final_h, "colors": colors, "project": project_name}


def load_image(args: Dict[str, Any]) -> "Image.Image":
    """Load image from base64 data or file path."""
    image_data = args.get("image_data")
    image_path = args.get("image_path")

    if image_data:
        raw = base64.b64decode(image_data)
        return Image.open(io.BytesIO(raw))
    if image_path:
        return Image.open(image_path)

    raise RuntimeError("image_data or image_path is required")


def fit_dimensions(img: "Image.Image", target_w: int, target_h: int, keep_aspect: bool) -> tuple:
    """Calculate final pixel art dimensions, optionally preserving aspect ratio."""
    if not keep_aspect:
        return target_w, target_h

    src_w, src_h = img.size
    ratio = min(target_w / src_w, target_h / src_h)
    final_w = max(1, int(src_w * ratio))
    final_h = max(1, int(src_h * ratio))
    return final_w, final_h


def handle_animated_export(args: Dict[str, Any], bridge_call: Callable) -> Dict[str, Any]:
    """Export animated GIF/APNG by exporting frames individually.

    Each frame is exported as a temp PNG via bridge_call("project.export"),
    then PIL assembles the final GIF/APNG. This avoids the single large
    bridge call that hangs on multi-frame projects.
    """
    if Image is None:
        raise RuntimeError("Pillow is required: pip install Pillow")

    _log(f"handle_animated_export called, args keys: {list(args.keys())}")

    final_path = args["path"]
    fmt = args.get("format", "gif").lower()
    trim = args.get("trim", False)
    scale = args.get("scale", 1)
    interpolation = args.get("interpolation", "nearest")

    # Query project metadata and frame list from bridge
    _log("querying project.info...")
    project_info = bridge_call("project.info", {})
    _log(f"project.info OK: {project_info.get('frames')} frames, fps={project_info.get('fps')}")
    _log("querying frame.list...")
    frame_list = bridge_call("frame.list", {})
    fps = project_info.get("fps", 10)
    all_frames = frame_list.get("frames", [])

    # Determine frame range (tag filtering)
    frame_indices = _resolve_frame_range(args, all_frames, bridge_call)

    # Apply direction (forward / backwards / ping_pong)
    frame_indices = _apply_direction(frame_indices, args.get("direction", "forward"))

    if not frame_indices:
        raise RuntimeError("no frames to export")

    # Export each frame as temp PNG, then assemble
    # Use ~/.cache/ (not /tmp/) because Flatpak sandboxes /tmp/ but shares ~/
    cache_base = os.path.join(os.path.expanduser("~"), ".cache", "pixelorama-mcp")
    os.makedirs(cache_base, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="anim_export_", dir=cache_base)
    try:
        durations_map = {f["index"]: f.get("duration", 1.0) for f in all_frames}
        pil_frames, durations_ms = _export_frames(
            frame_indices, durations_map, fps,
            temp_dir, trim, scale, interpolation, bridge_call,
        )

        _log(f"all frames exported, assembling {fmt} ({len(pil_frames)} frames)...")
        if fmt == "gif":
            _save_gif(pil_frames, durations_ms, final_path)
        else:  # apng
            pil_frames[0].save(
                final_path, format="PNG", save_all=True,
                append_images=pil_frames[1:],
                duration=durations_ms, loop=0,
            )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    return {"path": final_path, "format": fmt, "frames": len(frame_indices)}


def _resolve_frame_range(
    args: Dict[str, Any],
    all_frames: List[Dict[str, Any]],
    bridge_call: Callable,
) -> List[int]:
    """Determine which frame indices to export based on tag filters."""
    tag_name = args.get("tag")
    tag_index = args.get("tag_index")

    if tag_name is None and tag_index is None:
        return [f["index"] for f in all_frames]

    # Fetch animation tags (1-indexed, inclusive ranges)
    tags_result = bridge_call("animation.tags.list", {})
    tags = tags_result.get("tags", [])

    tag = None
    if tag_name is not None:
        for t in tags:
            if t.get("name") == tag_name:
                tag = t
                break
        if tag is None:
            raise RuntimeError(f"animation tag not found: {tag_name}")
    else:
        if tag_index < 0 or tag_index >= len(tags):
            raise RuntimeError(f"tag index out of range: {tag_index}")
        tag = tags[tag_index]

    # Pixelorama tags use 1-indexed inclusive ranges
    start = tag["from"] - 1  # convert to 0-indexed
    end = tag["to"]          # "to" is inclusive, so 0-indexed exclusive = to
    return list(range(start, end))


def _apply_direction(indices: List[int], direction: str) -> List[int]:
    """Reorder frame indices based on playback direction."""
    if direction == "backwards":
        return list(reversed(indices))

    if direction == "ping_pong" and len(indices) > 1:
        # Forward + reversed without duplicating endpoints
        return indices + list(reversed(indices[1:-1]))

    # Default: forward
    return indices


def _export_frames(
    frame_indices: List[int],
    durations_map: Dict[int, float],
    fps: float,
    temp_dir: str,
    trim: bool,
    scale: int,
    interpolation: str,
    bridge_call: Callable,
) -> tuple:
    """Export individual frames as temp PNGs, return PIL images and durations."""
    pil_frames = []
    durations_ms = []

    for i, frame_idx in enumerate(frame_indices):
        temp_path = os.path.join(temp_dir, f"{i:04d}.png")
        _log(f"exporting frame {i+1}/{len(frame_indices)} (idx={frame_idx}) -> {temp_path}")
        bridge_call("project.export", {
            "path": temp_path,
            "frame": frame_idx,
            "trim": trim,
            "scale": scale,
            "interpolation": interpolation,
        })
        _log(f"frame {i+1} exported, loading PIL image...")

        img = Image.open(temp_path).convert("RGBA")
        pil_frames.append(img)

        # Duration: multiplier / fps * 1000 = milliseconds
        multiplier = durations_map.get(frame_idx, 1.0)
        ms = max(10, int(round(multiplier / fps * 1000)))
        durations_ms.append(ms)

    return pil_frames, durations_ms


def _save_gif(
    frames_rgba: list, durations_ms: list, path: str
) -> None:
    """Save animated GIF from RGBA PIL frames with transparency support."""
    gif_frames = []
    for f in frames_rgba:
        alpha = f.split()[3]
        rgb = f.convert("RGB")
        # Quantize to 255 colors, reserve palette index 255 for transparency
        quantized = rgb.quantize(colors=255)
        # Mark transparent pixels (alpha < 128) with reserved index
        mask = alpha.point(lambda a: 255 if a < 128 else 0, mode="1")
        quantized.paste(255, mask=mask)
        gif_frames.append(quantized)

    gif_frames[0].save(
        path,
        format="GIF",
        save_all=True,
        append_images=gif_frames[1:],
        duration=durations_ms,
        loop=0,
        transparency=255,
        disposal=2,
    )
