# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Godot 4.6+ editor plugin development project containing three independent addons under `addons/`. Each addon is a self-contained `@tool` EditorPlugin registered via `plugin.cfg`. The project uses GDScript exclusively (no C# in addons) and requires Godot 4.6+.

## Addon Architecture

### Sketchfab (`addons/sketchfab/`)
Browser and importer for Sketchfab 3D models. Main-screen editor plugin.
- **Main.gd** — Root control, search UI, login/logout flow, category/filter state management. Uses `ConfigFile` at `user://sketchfab.ini` for token persistence.
- **Api.gd** — Sketchfab REST API wrapper (OAuth2 login, model search, download requests). Stores token in `Engine.set_meta("__sketchfab_token")`.
- **Requestor.gd** — Low-level async HTTP client using `HTTPClient` (not `HTTPRequest`). Signal-based completion pattern: `completed` emits `Result` objects. Supports cancel, download-to-file, JSON/form encoding.
- **ModelDialog.gd** — Modal detail/download dialog for a single model.
- **Paginator.gd** — Paginated results list. Emits `item_selected` with model data.
- **ResultItem.gd** — Single result row with thumbnail and metadata.
- **SafeData.gd** — Safe type coercion helpers for untrusted API responses.
- **Utils.gd** — Shared utility functions.

### Poly Haven Importer (`addons/PolyHavenImport/`)
Browser and importer for Poly Haven assets (HDRIs, textures, models). Lazy-instantiated main-screen plugin.
- **plugin.gd** — Lazy scene instantiation on tab switch. Registers project settings for output paths (`poly_haven_import/{hdris,textures,models}_path`).
- **api.gd** — Poly Haven REST API wrapper using `HTTPRequest` nodes (different pattern from Sketchfab).
- **browse.gd** — Main browse page (extends `Page`). Grid layout with type/category filters and pagination.
- **entry.tscn** — Individual asset entry widget.
- **previews.gd** / **download.gd** / **page.gd** — Preview display, asset download, and pagination base class.

### Godot MCP Native (`addons/godot_mcp/`)
AI assistant integration via Model Context Protocol. Largest addon (~50 GDScript files, 154 tools).
- **mcp_server_native.gd** — `EditorPlugin` entry point. Registers tools, resources, UI panel, debugger bridge. Supports `--mcp-server` CLI flag and auto-start.
- **native_mcp/mcp_server_core.gd** — `MCPServerCore` class. JSON-RPC 2.0 protocol handling, tool/resource registries, rate limiting, threading. Two transport modes: stdio and HTTP.
- **native_mcp/mcp_types.gd** — `MCPTypes` class with enums (`LogLevel`, `SecurityLevel`), inner classes (`MCPTool`, `MCPResource`), JSON-RPC error codes.
- **native_mcp/mcp_transport_base.gd** — Abstract transport base. Concrete: `mcp_http_server.gd`, `mcp_stdio_server.gd`.
- **tools/** — Tool modules registered by the plugin via `TOOL_SCRIPT_PATHS` dict. Each module has `initialize(editor_interface)` and `register_tools(server)` methods.
  - `node_tools_native.gd` — Scene node CRUD, signals, groups, batch ops.
  - `script_tools_native.gd` — Script read/write/create, symbol indexing, search.
  - `scene_tools_native.gd` — Scene open/save/create/list.
  - `editor_tools_native.gd` — Editor state, screenshots, filesystem, exports.
  - `debug_tools_native.gd` — Logs, debugger bridge, breakpoints, runtime probes.
  - `project_tools_native.gd` — Project settings, resources, input maps, health audit.
- **ui/** — `mcp_panel_native.tscn/.gd` main-screen panel with server controls and log.
- **utils/** — `node_utils.gd`, `path_validator.gd`, `resource_utils.gd`, `script_utils.gd`, `vibe_coding_policy.gd`.
- **runtime/** — `mcp_runtime_probe.gd` for live runtime inspection.

## Key Patterns

- All addons use `@tool` annotation — they run in the editor, not at runtime.
- EditorPlugins register as main-screen tabs via `_has_main_screen()` returning `true`.
- Sketchfab uses raw `HTTPClient` with manual polling and signal completion; PolyHaven uses `HTTPRequest` nodes with `await request_completed`.
- MCP plugin architecture: plugin.gd registers tool modules by path → each module calls `register_tools(server)` → `MCPServerCore` dispatches JSON-RPC `tools/call` to registered handlers.
- Comments in the MCP addon are primarily in Chinese (中文).
- Config persistence: Sketchfab uses `user://sketchfab.ini` (ConfigFile), PolyHaven uses `ProjectSettings`, MCP uses `EditorSettings` + internal state files.

## Development Workflow

No build system or CLI tests — this is a pure Godot editor plugin project. Testing is done within the Godot editor:
1. Open the project in Godot 4.6+.
2. Enable/disable plugins in **Project > Project Settings > Plugins**.
3. Test addons by switching to their main-screen tabs.
4. For MCP: start the server via the panel or `--mcp-server` flag, then connect an AI client.

## MCP Server Configuration

The Godot MCP addon exposes an HTTP server (default port 9080) for AI assistant integration. Connection configs for various clients are documented in `addons/godot_mcp/README.md`. The plugin supports `vibe_coding_mode` which restricts certain tool operations when enabled (UI focus, window control).

## Git Conventions

- Commit messages in Chinese or English.
- `.gitignore` excludes `.godot/`, `.idea/`, `assets/`, `sketchfab/` (downloaded models), `.omc/`, `.claude/`.
