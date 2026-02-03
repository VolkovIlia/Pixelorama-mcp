#!/usr/bin/env python3
import json
import os
import sys
from typing import Any, Dict, Optional

from .bridge_client import BridgeClient

PROTOCOL_VERSION = "2024-11-05"  # conservative MCP-style version string

TOOLS = [
    {
        "name": "bridge.ping",
        "description": "Ping Pixelorama bridge extension.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "bridge.version",
        "description": "Get Pixelorama version from bridge extension.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "bridge.info",
        "description": "Get bridge protocol and extension info.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "project.create",
        "description": "Create a new project and make it current.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "width": {"type": "integer", "minimum": 1},
                "height": {"type": "integer", "minimum": 1},
                "fill_color": {
                    "description": "RGBA array [r,g,b,a] (0-1 or 0-255) or hex string.",
                    "type": ["array", "string", "object", "null"],
                },
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "project.open",
        "description": "Open a .pxo project file.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "replace_empty": {"type": "boolean"}},
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.save",
        "description": "Save current project to .pxo.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "include_blended": {"type": "boolean"}},
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.export",
        "description": "Export current project frame to PNG.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
                "split_layers": {"type": "boolean"},
                "trim": {"type": "boolean"},
                "scale": {"type": "integer"},
                "interpolation": {"type": "string"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.info",
        "description": "Get current project info.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "project.set_active",
        "description": "Set current frame/layer.",
        "inputSchema": {
            "type": "object",
            "properties": {"frame": {"type": "integer"}, "layer": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "project.set_indexed_mode",
        "description": "Enable/disable indexed color mode.",
        "inputSchema": {
            "type": "object",
            "properties": {"enabled": {"type": "boolean"}},
            "required": ["enabled"],
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.list",
        "description": "List layers.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "layer.add",
        "description": "Add a layer above a given index.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "above": {"type": "integer"},
                "name": {"type": "string"},
                "type": {"type": ["string", "integer"]},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.remove",
        "description": "Remove a layer by index.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}},
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.rename",
        "description": "Rename a layer by index.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}, "name": {"type": "string"}},
            "required": ["index", "name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.move",
        "description": "Move a layer from one index to another.",
        "inputSchema": {
            "type": "object",
            "properties": {"from": {"type": "integer"}, "to": {"type": "integer"}},
            "required": ["from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "frame.list",
        "description": "List frames.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "frame.add",
        "description": "Add a new frame after index.",
        "inputSchema": {
            "type": "object",
            "properties": {"after": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "frame.remove",
        "description": "Remove a frame by index.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}},
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "frame.duplicate",
        "description": "Duplicate a frame by index.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "frame.move",
        "description": "Move a frame from one index to another.",
        "inputSchema": {
            "type": "object",
            "properties": {"from": {"type": "integer"}, "to": {"type": "integer"}},
            "required": ["from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.get",
        "description": "Get a pixel color from a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.set",
        "description": "Set a pixel color on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y", "color"],
            "additionalProperties": False,
        },
    },
    {
        "name": "canvas.fill",
        "description": "Fill a Pixel layer with a color.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "color": {"type": ["array", "string", "object", "null"]},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["color"],
            "additionalProperties": False,
        },
    },
    {
        "name": "canvas.clear",
        "description": "Clear a Pixel layer (transparent).",
        "inputSchema": {
            "type": "object",
            "properties": {"frame": {"type": "integer"}, "layer": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "canvas.resize",
        "description": "Resize canvas with offset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "offset_x": {"type": "integer"},
                "offset_y": {"type": "integer"},
            },
            "required": ["width", "height"],
            "additionalProperties": False,
        },
    },
    {
        "name": "canvas.crop",
        "description": "Crop to rectangle (x,y,width,height).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
            },
            "required": ["x", "y", "width", "height"],
            "additionalProperties": False,
        },
    },
    {
        "name": "palette.list",
        "description": "List palettes.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "palette.select",
        "description": "Select palette by name.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "palette.create",
        "description": "Create a palette.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "global": {"type": "boolean"},
            },
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "palette.delete",
        "description": "Delete a palette by name.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.line",
        "description": "Draw a line on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x1": {"type": "integer"},
                "y1": {"type": "integer"},
                "x2": {"type": "integer"},
                "y2": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "thickness": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x1", "y1", "x2", "y2", "color"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.rect",
        "description": "Draw rectangle on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "fill": {"type": "boolean"},
                "thickness": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y", "width", "height", "color"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.ellipse",
        "description": "Draw ellipse on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "fill": {"type": "boolean"},
                "thickness": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y", "width", "height", "color"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.erase_line",
        "description": "Erase (transparent) line on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x1": {"type": "integer"},
                "y1": {"type": "integer"},
                "x2": {"type": "integer"},
                "y2": {"type": "integer"},
                "thickness": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x1", "y1", "x2", "y2"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.replace_color",
        "description": "Replace a color on a Pixel layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "from": {"type": ["array", "string", "object", "null"]},
                "to": {"type": ["array", "string", "object", "null"]},
                "tolerance": {"type": "number"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selection.clear",
        "description": "Clear selection.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "selection.invert",
        "description": "Invert selection.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "selection.rect",
        "description": "Rectangle selection.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "mode": {"type": "string"},
            },
            "required": ["x", "y", "width", "height"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selection.ellipse",
        "description": "Ellipse selection.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "mode": {"type": "string"},
            },
            "required": ["x", "y", "width", "height"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selection.lasso",
        "description": "Lasso selection using polygon points.",
        "inputSchema": {
            "type": "object",
            "properties": {"points": {"type": "array"}, "mode": {"type": "string"}},
            "required": ["points"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selection.move",
        "description": "Move selection mask by dx/dy.",
        "inputSchema": {
            "type": "object",
            "properties": {"dx": {"type": "integer"}, "dy": {"type": "integer"}},
            "required": ["dx", "dy"],
            "additionalProperties": False,
        },
    },
    {
        "name": "selection.export_mask",
        "description": "Export selection mask PNG.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "symmetry.set",
        "description": "Set symmetry guides and visibility.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "show_x": {"type": "boolean"},
                "show_y": {"type": "boolean"},
                "show_xy": {"type": "boolean"},
                "show_x_minus_y": {"type": "boolean"},
                "x": {"type": "number"},
                "y": {"type": "number"},
                "xy": {"type": "array"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "batch.exec",
        "description": "Execute multiple bridge calls in a single request.",
        "inputSchema": {
            "type": "object",
            "properties": {"calls": {"type": "array"}},
            "required": ["calls"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.import.sequence",
        "description": "Import an image sequence as frames.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "paths": {"type": "array"},
                "mode": {"type": "string"},
                "layer": {"type": "integer"},
                "fps": {"type": "number"},
                "durations_ms": {"type": "array"},
            },
            "required": ["paths"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.import.spritesheet",
        "description": "Import a spritesheet as new project or new layer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "horizontal": {"type": "integer"},
                "vertical": {"type": "integer"},
                "mode": {"type": "string"},
                "name": {"type": "string"},
                "start_frame": {"type": "integer"},
                "detect_empty": {"type": "boolean"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.set_many",
        "description": "Set multiple pixels in one call.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "points": {"type": "array"},
                "color": {"type": ["array", "string", "object", "null"]},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["points"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.get_region",
        "description": "Get a region as PNG or raw base64.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "format": {"type": "string"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y", "width", "height"],
            "additionalProperties": False,
        },
    },
    {
        "name": "pixel.set_region",
        "description": "Blit a PNG/raw base64 image into a cel.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "data": {"type": "string"},
                "format": {"type": "string"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "mode": {"type": "string"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["data"],
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.tags.list",
        "description": "List animation tags.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "animation.tags.add",
        "description": "Add an animation tag.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "from": {"type": "integer"},
                "to": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "user_data": {"type": "string"},
            },
            "required": ["name", "from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.tags.update",
        "description": "Update an animation tag by index or name.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "index": {"type": "integer"},
                "name": {"type": "string"},
                "new_name": {"type": "string"},
                "from": {"type": "integer"},
                "to": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "user_data": {"type": "string"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.tags.remove",
        "description": "Remove an animation tag by index or name.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}, "name": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.playback.set",
        "description": "Enable/disable play-only-tags and optionally jump to tag.",
        "inputSchema": {
            "type": "object",
            "properties": {"play_only_tags": {"type": "boolean"}, "tag": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.tileset.list",
        "description": "List tilesets.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "tilemap.tileset.create",
        "description": "Create a tileset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tile_size": {"type": "array"},
                "name": {"type": "string"},
                "tile_shape": {"type": ["string", "integer"]},
                "add_empty_tile": {"type": "boolean"},
            },
            "required": ["tile_size"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.tileset.add_tile",
        "description": "Add a tile image to a tileset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tileset_index": {"type": "integer"},
                "path": {"type": "string"},
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "times_used": {"type": "integer"},
            },
            "required": ["tileset_index", "path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.tileset.remove_tile",
        "description": "Remove a tile from a tileset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tileset_index": {"type": "integer"},
                "tile_index": {"type": "integer"},
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
            },
            "required": ["tileset_index", "tile_index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.tileset.replace_tile",
        "description": "Replace a tile image in a tileset.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "tileset_index": {"type": "integer"},
                "tile_index": {"type": "integer"},
                "path": {"type": "string"},
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
            },
            "required": ["tileset_index", "tile_index", "path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.layer.set_tileset",
        "description": "Assign a tileset to a tilemap layer.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}, "tileset_index": {"type": "integer"}},
            "required": ["tileset_index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.layer.set_params",
        "description": "Set tilemap layer parameters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "place_only_mode": {"type": "boolean"},
                "tile_size": {"type": "array"},
                "tile_shape": {"type": ["string", "integer"]},
                "tile_layout": {"type": ["string", "integer"]},
                "tile_offset_axis": {"type": ["string", "integer"]},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.offset.set",
        "description": "Set tilemap offset for a cel.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "x": {"type": "integer"},
                "y": {"type": "integer"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.cell.get",
        "description": "Get tilemap cell data.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "cell_x": {"type": "integer"},
                "cell_y": {"type": "integer"},
            },
            "required": ["cell_x", "cell_y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.cell.set",
        "description": "Set tilemap cell data.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "cell_x": {"type": "integer"},
                "cell_y": {"type": "integer"},
                "index": {"type": "integer"},
                "flip_h": {"type": "boolean"},
                "flip_v": {"type": "boolean"},
                "transpose": {"type": "boolean"},
            },
            "required": ["cell_x", "cell_y", "index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.cell.clear",
        "description": "Clear tilemap cell.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "cell_x": {"type": "integer"},
                "cell_y": {"type": "integer"},
            },
            "required": ["cell_x", "cell_y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.list",
        "description": "List layer effects.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.add",
        "description": "Add a layer effect (shader).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "shader_path": {"type": "string"},
                "name": {"type": "string"},
                "category": {"type": "string"},
                "params": {"type": "object"},
                "enabled": {"type": "boolean"},
                "validate": {"type": "boolean"},
            },
            "required": ["shader_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.remove",
        "description": "Remove a layer effect.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}, "index": {"type": "integer"}},
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.move",
        "description": "Reorder layer effects.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "from": {"type": "integer"},
                "to": {"type": "integer"},
            },
            "required": ["from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.set_enabled",
        "description": "Enable/disable a layer effect.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "index": {"type": "integer"},
                "enabled": {"type": "boolean"},
            },
            "required": ["index", "enabled"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.set_params",
        "description": "Update layer effect parameters.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "index": {"type": "integer"},
                "params": {"type": "object"},
                "validate": {"type": "boolean"},
            },
            "required": ["index", "params"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.layer.apply",
        "description": "Apply a layer effect to a cel (bake).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "index": {"type": "integer"},
                "remove_after": {"type": "boolean"},
            },
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.shader.apply",
        "description": "Apply a shader directly to a cel.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "shader_path": {"type": "string"},
                "params": {"type": "object"},
                "validate": {"type": "boolean"},
            },
            "required": ["shader_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "history.undo",
        "description": "Undo last action.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "history.redo",
        "description": "Redo last action.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "three_d.object.list",
        "description": "List 3D objects in a cel.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}, "frame": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "three_d.object.add",
        "description": "Add a 3D object.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "type": {"type": ["string", "integer"]},
                "position": {"type": "array"},
                "rotation": {"type": "array"},
                "rotation_degrees": {"type": "array"},
                "scale": {"type": "array"},
                "visible": {"type": "boolean"},
                "file_path": {"type": "string"},
            },
            "required": ["type"],
            "additionalProperties": False,
        },
    },
    {
        "name": "three_d.object.remove",
        "description": "Remove a 3D object.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}, "frame": {"type": "integer"}, "id": {"type": "integer"}},
            "required": ["id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "three_d.object.update",
        "description": "Update a 3D object.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "id": {"type": "integer"},
                "type": {"type": ["string", "integer"]},
                "position": {"type": "array"},
                "rotation": {"type": "array"},
                "rotation_degrees": {"type": "array"},
                "scale": {"type": "array"},
                "visible": {"type": "boolean"},
                "file_path": {"type": "string"},
            },
            "required": ["id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.export.animated",
        "description": "Export animation as GIF/APNG.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "format": {"type": "string"},
                "tag": {"type": "string"},
                "tag_index": {"type": "integer"},
                "direction": {"type": "string"},
                "trim": {"type": "boolean"},
                "scale": {"type": "integer"},
                "interpolation": {"type": "string"},
                "split_layers": {"type": "boolean"},
                "erase_unselected_area": {"type": "boolean"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "project.export.spritesheet",
        "description": "Export spritesheet PNG.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "orientation": {"type": "string"},
                "lines": {"type": "integer"},
                "tag": {"type": "string"},
                "trim": {"type": "boolean"},
                "scale": {"type": "integer"},
                "interpolation": {"type": "string"},
            },
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.get_props",
        "description": "Get layer properties.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.set_props",
        "description": "Set layer properties (visible/locked/opacity/blend/clipping/name).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "index": {"type": "integer"},
                "name": {"type": "string"},
                "visible": {"type": "boolean"},
                "locked": {"type": "boolean"},
                "opacity": {"type": "number"},
                "blend_mode": {"type": ["string", "integer"]},
                "clipping_mask": {"type": "boolean"},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.group.create",
        "description": "Create a group layer.",
        "inputSchema": {
            "type": "object",
            "properties": {"above": {"type": "integer"}, "name": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "layer.parent.set",
        "description": "Set layer parent (group).",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}, "parent": {"type": "integer"}},
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.text",
        "description": "Draw text onto a cel.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "font_name": {"type": "string"},
                "size": {"type": "integer"},
                "align": {"type": "string"},
                "antialias": {"type": "boolean"},
                "color": {"type": ["array", "string", "object", "null"]},
                "width": {"type": "integer"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["text", "x", "y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "draw.gradient",
        "description": "Draw a linear gradient fill.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "from": {"type": ["array", "string", "object", "null"]},
                "to": {"type": ["array", "string", "object", "null"]},
                "direction": {"type": "string"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y", "width", "height", "from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.fps.get",
        "description": "Get animation FPS.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "animation.fps.set",
        "description": "Set animation FPS.",
        "inputSchema": {
            "type": "object",
            "properties": {"fps": {"type": "number"}},
            "required": ["fps"],
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.frame_duration.set",
        "description": "Set frame duration (ms) for one or many frames.",
        "inputSchema": {
            "type": "object",
            "properties": {"frame": {"type": "integer"}, "duration_ms": {"type": "number"}, "durations_ms": {"type": "array"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "animation.loop.set",
        "description": "Set animation loop mode.",
        "inputSchema": {
            "type": "object",
            "properties": {"mode": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.fill_rect",
        "description": "Fill tilemap cells in a rect.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "cell_x": {"type": "integer"},
                "cell_y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "index": {"type": "integer"},
                "flip_h": {"type": "boolean"},
                "flip_v": {"type": "boolean"},
                "transpose": {"type": "boolean"},
            },
            "required": ["cell_x", "cell_y", "width", "height", "index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.replace_index",
        "description": "Replace tile index in tilemap.",
        "inputSchema": {
            "type": "object",
            "properties": {"layer": {"type": "integer"}, "frame": {"type": "integer"}, "from": {"type": "integer"}, "to": {"type": "integer"}},
            "required": ["from", "to"],
            "additionalProperties": False,
        },
    },
    {
        "name": "tilemap.random_fill",
        "description": "Random fill tilemap cells with weights.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": "integer"},
                "frame": {"type": "integer"},
                "cell_x": {"type": "integer"},
                "cell_y": {"type": "integer"},
                "width": {"type": "integer"},
                "height": {"type": "integer"},
                "indices": {"type": "array"},
                "weights": {"type": "array"},
            },
            "required": ["cell_x", "cell_y", "width", "height", "indices"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.shader.list",
        "description": "List built-in effect shaders.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "effect.shader.inspect",
        "description": "Inspect shader uniforms.",
        "inputSchema": {
            "type": "object",
            "properties": {"shader_path": {"type": "string"}},
            "required": ["shader_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "effect.shader.schema",
        "description": "Get standardized shader parameter schema.",
        "inputSchema": {
            "type": "object",
            "properties": {"shader_path": {"type": "string"}},
            "required": ["shader_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "brush.list",
        "description": "List project brushes.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "brush.add",
        "description": "Add a project brush from path or base64 PNG.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "data": {"type": "string"}},
            "additionalProperties": False,
        },
    },
    {
        "name": "brush.remove",
        "description": "Remove a project brush by index.",
        "inputSchema": {
            "type": "object",
            "properties": {"index": {"type": "integer"}},
            "required": ["index"],
            "additionalProperties": False,
        },
    },
    {
        "name": "brush.clear",
        "description": "Clear all project brushes.",
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "brush.stamp",
        "description": "Stamp a brush at a position.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "brush_index": {"type": "integer"},
                "brush_type": {"type": "string"},
                "brush_path": {"type": "string"},
                "brush_data": {"type": "string"},
                "size": {"type": "integer"},
                "scale": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "opacity": {"type": "number"},
                "mode": {"type": "string"},
                "jitter": {"type": "number"},
                "spray": {"type": "integer"},
                "spray_radius": {"type": "number"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["x", "y"],
            "additionalProperties": False,
        },
    },
    {
        "name": "brush.stroke",
        "description": "Draw a brush stroke along points.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "points": {"type": "array"},
                "brush_index": {"type": "integer"},
                "brush_type": {"type": "string"},
                "brush_path": {"type": "string"},
                "brush_data": {"type": "string"},
                "size": {"type": "integer"},
                "scale": {"type": "integer"},
                "color": {"type": ["array", "string", "object", "null"]},
                "opacity": {"type": "number"},
                "spacing": {"type": "number"},
                "spacing_curve": {"type": ["array", "string"]},
                "mode": {"type": "string"},
                "jitter": {"type": "number"},
                "spray": {"type": "integer"},
                "spray_radius": {"type": "number"},
                "frame": {"type": "integer"},
                "layer": {"type": "integer"},
            },
            "required": ["points"],
            "additionalProperties": False,
        },
    },
    {
        "name": "palette.import",
        "description": "Import a palette from file.",
        "inputSchema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "palette.export",
        "description": "Export a palette to file.",
        "inputSchema": {
            "type": "object",
            "properties": {"name": {"type": "string"}, "path": {"type": "string"}},
            "additionalProperties": False,
        },
    },
]


class StdioTransport:
    def __init__(self):
        self._stdin = sys.stdin.buffer
        self._stdout = sys.stdout.buffer
        self._mode = None  # "lsp" or "line"

    def read_message(self) -> Optional[Dict[str, Any]]:
        if self._mode == "line":
            line = self._stdin.readline()
            if not line:
                return None
            line = line.strip()
            if not line:
                return None
            return json.loads(line.decode("utf-8"))

        if self._mode == "lsp":
            return self._read_lsp_message()

        # Auto-detect framing based on the first line.
        line = self._stdin.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            return None
        stripped = line.lstrip()
        if stripped.startswith(b"{"):
            self._mode = "line"
            return json.loads(stripped.decode("utf-8"))

        self._mode = "lsp"
        return self._read_lsp_message(first_line=line)

    def _read_lsp_message(self, first_line: Optional[bytes] = None) -> Optional[Dict[str, Any]]:
        headers = {}
        if first_line is not None:
            key, _, value = first_line.decode("utf-8", errors="replace").partition(":")
            headers[key.strip().lower()] = value.strip()
        while True:
            line = self._stdin.readline()
            if not line:
                return None
            if line in (b"\r\n", b"\n"):
                break
            key, _, value = line.decode("utf-8", errors="replace").partition(":")
            headers[key.strip().lower()] = value.strip()
        length = int(headers.get("content-length", "0"))
        if length <= 0:
            return None
        body = self._stdin.read(length)
        if not body:
            return None
        return json.loads(body.decode("utf-8"))

    def send_message(self, payload: Dict[str, Any]) -> None:
        if self._mode == "line":
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"
            self._stdout.write(body)
            self._stdout.flush()
            return
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("utf-8")
        self._stdout.write(header + body)
        self._stdout.flush()


class MCPServer:
    def __init__(self):
        self._transport = StdioTransport()
        host = os.environ.get("PIXELORAMA_BRIDGE_HOST", "127.0.0.1")
        port = int(os.environ.get("PIXELORAMA_BRIDGE_PORT", "8123"))
        self._bridge = BridgeClient(host=host, port=port)
        self._bridge_protocol_checked = False

    def run(self) -> None:
        while True:
            msg = self._transport.read_message()
            if msg is None:
                break
            response = self._handle_message(msg)
            if response is not None:
                self._transport.send_message(response)

    def _handle_message(self, msg: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        msg_id = msg.get("id")
        method = msg.get("method")
        params = msg.get("params", {})

        try:
            if method == "initialize":
                result = {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "pixelorama-mcp", "version": "0.1.0"},
                }
                return self._ok(msg_id, result) if msg_id is not None else None
            if method == "tools/list":
                return self._ok(msg_id, {"tools": TOOLS}) if msg_id is not None else None
            if method == "tools/call":
                if msg_id is None:
                    return None
                tool_result = self._call_tool(params)
                wrapped = {
                    "content": [
                        {"type": "text", "text": json.dumps(tool_result, ensure_ascii=False)}
                    ]
                }
                return self._ok(msg_id, wrapped)
            if method in ("shutdown", "exit"):
                return self._ok(msg_id, {"ok": True}) if msg_id is not None else None
            if msg_id is None:
                return None
            return self._err(msg_id, "method_not_found", f"unknown method: {method}")
        except Exception as exc:  # guardrail to avoid crashing the server
            if msg_id is None:
                return None
            return self._err(msg_id, "internal_error", str(exc))

    def _call_tool(self, params: Dict[str, Any]) -> Dict[str, Any]:
        name = params.get("name")
        args = params.get("arguments", {})
        if name == "bridge.ping":
            return self._bridge.call("ping", args)
        if name == "bridge.version":
            return self._bridge.call("version", args)
        if name == "bridge.info":
            return self._bridge.call("bridge.info", args)
        if name not in ("bridge.ping", "bridge.version", "bridge.info"):
            self._ensure_bridge_protocol()
        if name == "project.create":
            return self._bridge.call("project.create", args)
        if name == "project.open":
            return self._bridge.call("project.open", args)
        if name == "project.save":
            return self._bridge.call("project.save", args)
        if name == "project.export":
            return self._bridge.call("project.export", args)
        if name == "project.info":
            return self._bridge.call("project.info", args)
        if name == "project.set_active":
            return self._bridge.call("project.set_active", args)
        if name == "project.set_indexed_mode":
            return self._bridge.call("project.set_indexed_mode", args)
        if name == "layer.list":
            return self._bridge.call("layer.list", args)
        if name == "layer.add":
            return self._bridge.call("layer.add", args)
        if name == "layer.remove":
            return self._bridge.call("layer.remove", args)
        if name == "layer.rename":
            return self._bridge.call("layer.rename", args)
        if name == "layer.move":
            return self._bridge.call("layer.move", args)
        if name == "frame.list":
            return self._bridge.call("frame.list", args)
        if name == "frame.add":
            return self._bridge.call("frame.add", args)
        if name == "frame.remove":
            return self._bridge.call("frame.remove", args)
        if name == "frame.duplicate":
            return self._bridge.call("frame.duplicate", args)
        if name == "frame.move":
            return self._bridge.call("frame.move", args)
        if name == "pixel.get":
            return self._bridge.call("pixel.get", args)
        if name == "pixel.set":
            return self._bridge.call("pixel.set", args)
        if name == "canvas.fill":
            return self._bridge.call("canvas.fill", args)
        if name == "canvas.clear":
            return self._bridge.call("canvas.clear", args)
        if name == "canvas.resize":
            return self._bridge.call("canvas.resize", args)
        if name == "canvas.crop":
            return self._bridge.call("canvas.crop", args)
        if name == "palette.list":
            return self._bridge.call("palette.list", args)
        if name == "palette.select":
            return self._bridge.call("palette.select", args)
        if name == "palette.create":
            return self._bridge.call("palette.create", args)
        if name == "palette.delete":
            return self._bridge.call("palette.delete", args)
        if name == "draw.line":
            return self._bridge.call("draw.line", args)
        if name == "draw.rect":
            return self._bridge.call("draw.rect", args)
        if name == "draw.ellipse":
            return self._bridge.call("draw.ellipse", args)
        if name == "draw.erase_line":
            return self._bridge.call("draw.erase_line", args)
        if name == "pixel.replace_color":
            return self._bridge.call("pixel.replace_color", args)
        if name == "selection.clear":
            return self._bridge.call("selection.clear", args)
        if name == "selection.invert":
            return self._bridge.call("selection.invert", args)
        if name == "selection.rect":
            return self._bridge.call("selection.rect", args)
        if name == "selection.ellipse":
            return self._bridge.call("selection.ellipse", args)
        if name == "selection.lasso":
            return self._bridge.call("selection.lasso", args)
        if name == "selection.move":
            return self._bridge.call("selection.move", args)
        if name == "selection.export_mask":
            return self._bridge.call("selection.export_mask", args)
        if name == "symmetry.set":
            return self._bridge.call("symmetry.set", args)
        if name == "batch.exec":
            return self._bridge.call("batch.exec", args)
        if name == "project.import.sequence":
            return self._bridge.call("project.import.sequence", args)
        if name == "project.import.spritesheet":
            return self._bridge.call("project.import.spritesheet", args)
        if name == "pixel.set_many":
            return self._bridge.call("pixel.set_many", args)
        if name == "pixel.get_region":
            return self._bridge.call("pixel.get_region", args)
        if name == "pixel.set_region":
            return self._bridge.call("pixel.set_region", args)
        if name == "animation.tags.list":
            return self._bridge.call("animation.tags.list", args)
        if name == "animation.tags.add":
            return self._bridge.call("animation.tags.add", args)
        if name == "animation.tags.update":
            return self._bridge.call("animation.tags.update", args)
        if name == "animation.tags.remove":
            return self._bridge.call("animation.tags.remove", args)
        if name == "animation.playback.set":
            return self._bridge.call("animation.playback.set", args)
        if name == "tilemap.tileset.list":
            return self._bridge.call("tilemap.tileset.list", args)
        if name == "tilemap.tileset.create":
            return self._bridge.call("tilemap.tileset.create", args)
        if name == "tilemap.tileset.add_tile":
            return self._bridge.call("tilemap.tileset.add_tile", args)
        if name == "tilemap.tileset.remove_tile":
            return self._bridge.call("tilemap.tileset.remove_tile", args)
        if name == "tilemap.tileset.replace_tile":
            return self._bridge.call("tilemap.tileset.replace_tile", args)
        if name == "tilemap.layer.set_tileset":
            return self._bridge.call("tilemap.layer.set_tileset", args)
        if name == "tilemap.layer.set_params":
            return self._bridge.call("tilemap.layer.set_params", args)
        if name == "tilemap.offset.set":
            return self._bridge.call("tilemap.offset.set", args)
        if name == "tilemap.cell.get":
            return self._bridge.call("tilemap.cell.get", args)
        if name == "tilemap.cell.set":
            return self._bridge.call("tilemap.cell.set", args)
        if name == "tilemap.cell.clear":
            return self._bridge.call("tilemap.cell.clear", args)
        if name == "effect.layer.list":
            return self._bridge.call("effect.layer.list", args)
        if name == "effect.layer.add":
            return self._bridge.call("effect.layer.add", args)
        if name == "effect.layer.remove":
            return self._bridge.call("effect.layer.remove", args)
        if name == "effect.layer.move":
            return self._bridge.call("effect.layer.move", args)
        if name == "effect.layer.set_enabled":
            return self._bridge.call("effect.layer.set_enabled", args)
        if name == "effect.layer.set_params":
            return self._bridge.call("effect.layer.set_params", args)
        if name == "effect.layer.apply":
            return self._bridge.call("effect.layer.apply", args)
        if name == "effect.shader.apply":
            return self._bridge.call("effect.shader.apply", args)
        if name == "effect.shader.list":
            return self._bridge.call("effect.shader.list", args)
        if name == "effect.shader.inspect":
            return self._bridge.call("effect.shader.inspect", args)
        if name == "effect.shader.schema":
            return self._bridge.call("effect.shader.schema", args)
        if name == "history.undo":
            return self._bridge.call("history.undo", args)
        if name == "history.redo":
            return self._bridge.call("history.redo", args)
        if name == "project.export.animated":
            return self._bridge.call("project.export.animated", args)
        if name == "project.export.spritesheet":
            return self._bridge.call("project.export.spritesheet", args)
        if name == "layer.get_props":
            return self._bridge.call("layer.get_props", args)
        if name == "layer.set_props":
            return self._bridge.call("layer.set_props", args)
        if name == "layer.group.create":
            return self._bridge.call("layer.group.create", args)
        if name == "layer.parent.set":
            return self._bridge.call("layer.parent.set", args)
        if name == "draw.text":
            return self._bridge.call("draw.text", args)
        if name == "draw.gradient":
            return self._bridge.call("draw.gradient", args)
        if name == "animation.fps.get":
            return self._bridge.call("animation.fps.get", args)
        if name == "animation.fps.set":
            return self._bridge.call("animation.fps.set", args)
        if name == "animation.frame_duration.set":
            return self._bridge.call("animation.frame_duration.set", args)
        if name == "animation.loop.set":
            return self._bridge.call("animation.loop.set", args)
        if name == "tilemap.fill_rect":
            return self._bridge.call("tilemap.fill_rect", args)
        if name == "tilemap.replace_index":
            return self._bridge.call("tilemap.replace_index", args)
        if name == "tilemap.random_fill":
            return self._bridge.call("tilemap.random_fill", args)
        if name == "brush.list":
            return self._bridge.call("brush.list", args)
        if name == "brush.add":
            return self._bridge.call("brush.add", args)
        if name == "brush.remove":
            return self._bridge.call("brush.remove", args)
        if name == "brush.clear":
            return self._bridge.call("brush.clear", args)
        if name == "brush.stamp":
            return self._bridge.call("brush.stamp", args)
        if name == "brush.stroke":
            return self._bridge.call("brush.stroke", args)
        if name == "palette.import":
            return self._bridge.call("palette.import", args)
        if name == "palette.export":
            return self._bridge.call("palette.export", args)
        if name == "three_d.object.list":
            return self._bridge.call("three_d.object.list", args)
        if name == "three_d.object.add":
            return self._bridge.call("three_d.object.add", args)
        if name == "three_d.object.remove":
            return self._bridge.call("three_d.object.remove", args)
        if name == "three_d.object.update":
            return self._bridge.call("three_d.object.update", args)
        raise RuntimeError(f"unknown tool: {name}")

    def _ensure_bridge_protocol(self) -> None:
        if self._bridge_protocol_checked:
            return
        info = self._bridge.call("bridge.info", {})
        protocol = info.get("protocol_version") if isinstance(info, dict) else None
        if protocol != PROTOCOL_VERSION:
            raise RuntimeError(
                f"protocol_mismatch: expected {PROTOCOL_VERSION}, got {protocol}"
            )
        self._bridge_protocol_checked = True

    def _ok(self, msg_id: Any, result: Any) -> Dict[str, Any]:
        return {"jsonrpc": "2.0", "id": msg_id, "result": result}

    def _err(self, msg_id: Any, code: str, message: str) -> Dict[str, Any]:
        return {
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {"code": code, "message": message},
        }


def main():
    MCPServer().run()


if __name__ == "__main__":
    main()
