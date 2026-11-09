# Connect Claude Code (VS Code) to the SAP VM

Goal: Claude Code can create, check and activate ABAP programs in the NPL system directly.
It talks to SAP through **ADT** (the same HTTP interface Eclipse ADT uses) via an **ABAP MCP server**.

## 1. Open the HTTP port of the VM (once)

SAP GUI already works through port forwarding. ADT needs the HTTP port too.

VirtualBox Manager → select the VM → **Settings → Network → Adapter 1 (NAT) → Advanced → Port Forwarding** → add:

| Name | Protocol | Host Port | Guest Port |
|---|---|---|---|
| sap-http | TCP | 8000 | 8000 |

(Rules can be added while the VM runs.)

Test in a browser on the laptop: `http://localhost:8000/sap/bc/adt/discovery`
→ a login prompt appears (client 001, DEVELOPER) and then an XML page = ADT works.

If it does not answer: in SAP run **SMICM → Goto → Services** and check the HTTP port
(it may be 50000 instead of 8000 - then forward that port), and **SICF** → service `/sap/bc/adt` must be active.

## 2. Add an ABAP MCP server to Claude Code

Recommended: **mcp-abap-adt** (github.com/fr0ster/mcp-abap-adt) - supports create/update/activate for classic ABAP on-premise.
Alternative: **ARC-1** (github.com/marianfoo/arc-1, npm package `arc-1`).

Easiest: let Claude Code install it. In VS Code open this folder, start Claude Code and paste:

> Install and configure the ABAP MCP server from https://github.com/fr0ster/mcp-abap-adt for this project,
> following its README exactly (Node.js required). Connection: URL http://localhost:8000, client 001,
> user DEVELOPER, on-premise system with basic authentication. Ask me for the password and store it only
> in a local .env file that is added to .gitignore. Register it as a project MCP server, then test the
> connection by reading the source of program RSPARAM.

Check with `/mcp` in Claude Code that the server shows as connected.

## 3. Deploy the dump report

Paste the prompt from `PROMPT.md`.

## Safety
- Only ever point this at the practice VM. Never at a company system.
- Objects go to `$TMP` (local) - nothing can be transported anywhere.
- Review each change Claude Code proposes before approving it.
