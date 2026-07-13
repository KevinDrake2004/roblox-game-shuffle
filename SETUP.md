# Shuffle Arcade — Dev Setup

Roblox game inspired by [Shuffle.com](https://shuffle.com), reframed as a compliant arcade experience.

## Environment: WSL2 + Windows

| Component | Where it runs |
|-----------|---------------|
| Project files, Git, Rojo, Wally, Selene, StyLua, Moonwave | **WSL2** (`/home/kevin04/roblox/shuffle`) |
| Roblox Studio, Rojo plugin, MCP plugin | **Windows** |

Keep the repo on the **Linux filesystem** (`/home/...`), not `/mnt/c/...`. Rojo live-sync breaks on Windows-mounted paths in WSL.

## First-Time Setup

### 1. WSL toolchain (already done if you cloned this repo)

```bash
# Install Rokit (one-time, in WSL)
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash

# Add Rokit to your shell (add to ~/.bashrc for persistence)
source ~/.rokit/env

# Install pinned tools from rokit.toml
cd /home/kevin04/roblox/shuffle
rokit install --no-trust-check

# Install Wally packages
wally install

# Install Moonwave docs CLI (npm)
npm install
```

### Toolchain (Rokit)

All CLI tools are pinned in [`rokit.toml`](/home/kevin04/roblox/shuffle/rokit.toml):

| Tool | Purpose | Command |
|------|---------|---------|
| **Rojo** | Sync code to Studio | `rojo serve` |
| **Wally** | Package manager | `wally install` |
| **Selene** | Luau linter | `selene src/` |
| **StyLua** | Code formatter | `stylua src/` |
| **Moonwave** | Doc comment extractor | `moonwave-extract extract src/shared -b src` |
| **Moonwave CLI** | Docs website (npm) | `npm run docs` or `./scripts/docs-dev.sh` |

**Convenience scripts:**

```bash
./scripts/check.sh        # Selene + StyLua + Moonwave extract
./scripts/format.sh       # Format all src/ with StyLua
./scripts/wally-install.sh
./scripts/docs-dev.sh     # Local docs at http://localhost:3000
./scripts/install-git-hooks.sh   # Auto-run check.sh before every git commit
./scripts/watch-toolchain.sh     # Optional: format + lint on every file save
```

## Automation (what runs when)

You do **not** need to memorize when to run each tool. Use this split:

| When | What runs automatically |
|------|-------------------------|
| **Every save in Cursor** | StyLua formats the file (`formatOnSave`) |
| **Every save in Cursor** | Selene lints (install `Kampfkarren.selene-vscode` extension) |
| **Every save to disk** | Optional: `./scripts/watch-toolchain.sh` — StyLua + Selene + Moonwave extract |
| **When `wally.toml` changes** | Watch script runs `wally install`; otherwise run `./scripts/wally-install.sh` manually |
| **Before every git commit** | `./scripts/install-git-hooks.sh` once, then pre-commit runs full `./scripts/check.sh` |
| **Rojo sync** | Automatic while `rojo serve` is running — no extra step |
| **Docs website** | Manual: `npm run docs` when you want to preview API docs |

**Recommended dev terminals:**

```bash
# Terminal 1
source ~/.rokit/env && rojo serve

# Terminal 2
./scripts/mcp-serve.sh

# Terminal 3 (optional — hands-off lint/format/docs validation)
./scripts/watch-toolchain.sh
```

**Still manual (by design):**
- `rojo sourcemap` — only after you change `default.project.json` structure
- `npm run docs` — when previewing documentation site
- `wally install` — only when adding/updating dependencies in `wally.toml` (watch script handles this if running)

### 2. Roblox Studio (Windows)

1. Install [Roblox Studio](https://create.roblox.com/) on Windows
2. Install the **Rojo** plugin from the Creator Store / Toolbox
3. Create or open a place (save as `shuffle.rbxl` locally if you prefer)
4. In **Game Settings → Security**, enable **Allow HTTP Requests** (required for MCP)

### 3. Cursor

Open the project from WSL:

```bash
cursor /home/kevin04/roblox/shuffle
```

**Recommended extensions** (see `.vscode/extensions.json`):

- Luau Language Server (`JohnnyMorganz.luau-lsp`)
- StyLua (`JohnnyMorganz.stylua`)
- Rojo (`evaera.vscode-rojo`) — optional

### 4. Roblox Studio MCP (Chrrxs)

This project uses [@chrrxs/robloxstudio-mcp](https://github.com/Chrrxs/robloxstudio-mcp) — no Assistant panel required.

**One-time setup:**

1. In Studio: **Game Settings → Security** → enable **Allow HTTP Requests**
2. Install the Studio plugin (from WSL, targets your Windows Plugins folder):

```bash
MCP_PLUGINS_DIR="/mnt/c/Users/<WindowsUser>/AppData/Local/Roblox/Plugins" \
  npx -y @chrrxs/robloxstudio-mcp@latest --install-plugin
```

3. **Fully close and reopen Roblox Studio**
4. In Studio **Plugins** toolbar, find the MCP plugin — it should show **Connected**
5. **Start the MCP server** (pick one):
   - **Cursor:** reload window → enable `robloxstudio-mcp` in **Settings → MCP**
   - **Manual (recommended for WSL):** run `./scripts/mcp-serve.sh` in a second WSL terminal and leave it open
6. Studio plugin connects to `http://localhost:58741` — the server must be running **before** Studio tries to connect

### WSL + Windows: fix `ConnectFail` on `/ready`

Roblox Studio runs on **Windows**, but the MCP server runs in **WSL**. By default they use different `localhost` networks.

**Fix (recommended):** enable WSL mirrored networking on Windows.

1. Create `C:\Users\<You>\.wslconfig` with:

```ini
[wsl2]
networkingMode=mirrored
```

(A copy is in [`tools/wslconfig.example`](/home/kevin04/roblox/shuffle/tools/wslconfig.example))

2. In **PowerShell (Admin):** `wsl --shutdown`
3. Reopen WSL, start MCP (`./scripts/mcp-serve.sh`), then open Studio

**Alternative:** install [Node.js on Windows](https://nodejs.org/) and change `.cursor/mcp.json` to run MCP via Windows:

```json
{
  "mcpServers": {
    "robloxstudio-mcp": {
      "command": "cmd.exe",
      "args": ["/c", "npx", "-y", "@chrrxs/robloxstudio-mcp@latest"]
    }
  }
}
```

Project [`.cursor/mcp.json`](/home/kevin04/roblox/shuffle/.cursor/mcp.json) is already configured:

```json
{
  "mcpServers": {
    "robloxstudio-mcp": {
      "command": "npx",
      "args": ["-y", "@chrrxs/robloxstudio-mcp@latest"]
    }
  }
}
```

## Daily Workflow

```bash
# Terminal 1 — start Rojo sync server (WSL)
cd /home/kevin04/roblox/shuffle

# Option A: use the project script (works even if PATH isn't set yet)
./scripts/serve.sh

# Option B: load Rokit into your current shell, then run rojo directly
source ~/.rokit/env
rojo serve
```

If `rojo` is not found, your terminal was opened before Rokit was installed. Run `source ~/.rokit/env` once, or open a new terminal tab.

1. `rojo serve` in WSL (listens on `localhost:34872`)
2. In **Roblox Studio** → Rojo plugin → **Connect**
3. Edit `.luau` files in **Cursor** — changes sync to Studio within seconds
4. Use Cursor Agent + Studio MCP for scene inspection and playtesting

**Optional — regenerate types after structure changes:**

```bash
rojo sourcemap default.project.json --output sourcemap.json
```

**Lint and format:**

```bash
selene src/
stylua src/
```

## Verification Checklist

- [ ] `rojo serve` running in WSL; Studio Rojo plugin shows **Connected**
- [ ] Press Play in Studio — Output shows `[Shuffle] Server synced via Rojo` and `[Shuffle] Client synced via Rojo`
- [ ] Edit `src/server/init.server.luau` in Cursor — change appears in Studio after sync
- [ ] MCP plugin in Studio shows **Connected** (Plugins toolbar)
- [ ] Cursor **Settings → MCP** shows `robloxstudio-mcp` enabled
- [ ] Ask Cursor agent: "What's in ServerScriptService?" — gets a real Studio response
- [ ] `selene src/` passes with 0 errors

## Project Layout

```
shuffle/
├── default.project.json   # Rojo mount tree
├── rokit.toml             # Pinned CLI tool versions
├── wally.toml             # Package dependencies
├── GAMEPLAN.md            # Roadmap + current vs future economy
├── docs/
│   └── ROCKET_RUN.md      # Rocket Run play flow + wager settlement
├── src/
│   ├── client/            # StarterPlayerScripts
│   ├── server/            # ServerScriptService
│   ├── shared/            # ReplicatedStorage
│   └── map/               # Workspace lobby / arena models
└── Packages/              # Wally output (gitignored)
```

Gameplay notes for Rocket Run: [`docs/ROCKET_RUN.md`](docs/ROCKET_RUN.md).
## Troubleshooting

| Problem | Fix |
|---------|-----|
| `protocolVersion` / protocol mismatch on Connect | CLI and Studio plugin versions must match (both **7.7.0**). Disable any extra Rojo plugins, then run `tools\install-rojo-plugin.bat` from Windows if needed. |
| Live sync not updating | Confirm project is on `/home/...` not `/mnt/c/...` |
| Rojo won't connect | Ensure `rojo serve` is running in WSL; try `localhost:34872` |
| MCP `ConnectFail` on `/ready` | MCP server not running, or WSL/Windows localhost split — run `./scripts/mcp-serve.sh` and enable WSL mirrored networking (see above) |
| MCP won't connect | Enable **Allow HTTP Requests** in Game Settings; restart Studio after plugin install; reload Cursor window |
| `rokit` / `rojo` not found | Run `source ~/.rokit/env` or add `~/.rokit/bin` to PATH |
