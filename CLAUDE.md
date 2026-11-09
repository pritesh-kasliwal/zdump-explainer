# Project: ABAP tools for my practice SAP system

## The SAP system
- SAP NetWeaver AS ABAP **7.52 SP04** developer edition (SID **NPL**), BW 7.5x, Sybase ASE, running in a VirtualBox VM (Debian 9) on this laptop.
- Reached from Windows through VirtualBox NAT port forwarding:
  - SAP GUI: `localhost`, instance 00
  - ADT / HTTP: `http://localhost:8000` (ICM HTTP port 8000)
- Client **001**, user **DEVELOPER**. The password is never written into any file in this repo; it is only in the local `.env` used by the MCP server (git-ignored).
- This is a private practice system. **Never connect to or change any company system.**

## How to work on ABAP here
- Source of truth is the files in `src/` (abapGit-style names, e.g. `zdump_explainer.prog.abap`).
- Deploy with the ABAP ADT MCP server configured for this project (see `SETUP_CLAUDE_CODE.md`):
  1. Create the object if it does not exist: package **$TMP** (local, no transport), type executable program.
  2. Write the source from the file in `src/`.
  3. Run the syntax check. On errors: fix in `src/` with minimal changes, write again, re-check.
  4. Activate. Report what was done and any remaining warnings.
- Text elements (selection texts, text symbols) are listed in the header comment of each program. Create them if the MCP server supports it, otherwise list them for me to add in SE38.

## Coding rules
- ABAP language level **7.50**: inline declarations, `VALUE`, `COND`, `SWITCH`, string templates, `xsdbool` are fine. **Not allowed**: `+=` / `-=` (7.54), CDS-only features, `FINAL(...)`, anything newer than 7.50.
- Max line length 255 characters (split long string literals with `&&`).
- Local objects only (`$TMP`), names starting with `Z`.
- Never modify SAP standard objects; read-only access to SAP tables.
- Analysis programs must not change data.
- Run `npx @abaplint/cli` with `abaplint.json` (version v750) before deploying when possible.
