# ZDUMP_EXPLAINER - SAP problems explained for everyone

One readable report with three sections (each can be switched on/off):

1. **Short dumps (ST22)**
2. **System log (SM21)**: entries grouped by message ID, follow-up lines (`> ...`) attached to their entry,
   plain-language explanation for common kinds (database errors, cancelled transactions, background jobs,
   invalid profile parameters, ICM/ports, OS errors, work process restarts, RFC, logon, buffers, start-up events),
   SAP's own documentation for the message and the text of cancel messages. Information messages are hidden
   unless "Include information messages" is set.
3. **Database (DB02)**, SAP ASE (Sybase) only: data space and transaction log per database (same calculation as
   DBA Cockpit), offline databases, log backups / automatic log truncation, log and data on one device, and the
   10 largest tables with clean-up hints (e.g. SNAP → RSSNAPDL, TST03 → RSPO1041, BALDAT → SLG2).
   Table sizes come from the database statistics (systabstats) and are approximate.

Short dumps in detail:

- **Duplicates grouped**: same runtime error + program + include + line = one problem.
  It is explained once, with how many times it happened, first/last time and which users.
- **Plain language** for each problem: what went wrong, typical causes, who should act, what to do next.
  Built-in explanations for ~20 common error families (TIME_OUT, memory, MESSAGE_TYPE_X, null references,
  conversion and calculation errors, duplicates, database, RFC, syntax errors, ...), plus SAP's own short text.
- **Own code vs. SAP code**: tells whether your team can fix it or you should search SAP Notes.
- **Code at the failing line** (with the line highlighted) and who last changed it.
- **Severity** (High / Medium / Low) from error type, frequency and number of users; worst first.

Read-only: it changes nothing in the system.

**No AI API? Use the AI export.** Output "AI export file" saves all collected facts as one Markdown file
(with user, system and server names; optional anonymization) that you upload into a browser AI together with the prompt in
[AI_REPORT_PROMPT.md](AI_REPORT_PROMPT.md). Example file: [examples/ai_export_example.md](examples/ai_export_example.md).

## Run
SE38 → `ZDUMP_EXPLAINER`

| Field | Meaning |
|---|---|
| Short dumps / System log / Database | which sections to analyse (default: all) |
| Include information messages | also show SM21 information messages (work process start/stop etc.) |
| Date | default: last 7 days; used for short dumps and the system log |
| User, Client | optional filters (short dumps and system log) |
| Runtime error, App server | optional filters (short dumps) |
| Only own code | only dumps in Z/Y/namespace programs |
| HTML report / ALV overview / AI export file | how to show the result (ALV covers short dumps only) |
| Save to file | HTML report: e.g. `C:\temp\dumps.html` to share by e-mail. AI export: empty = save dialog |
| Anonymize users and servers | AI export: replace names by USER_nn / SERVER_nn (default off) |
| Include source code | AI export: 7 source lines around each failing line (default on) |
| Text language | for SAP's error texts |

**Daily job:** save a variant (e.g. date = yesterday via dynamic date selection) and schedule it in SM36.
In background it writes a plain list to the spool - or, with "AI export file", the export text.

## Files
| File | Purpose |
|---|---|
| `src/zdump_explainer.prog.abap` | the program |
| `CLAUDE.md` | instructions for Claude Code (system facts and coding rules) |
| `SETUP_CLAUDE_CODE.md` | connect Claude Code to the SAP VM via ADT |
| `PROMPT.md` | ready-made prompt to deploy and test the program |
| `AI_REPORT_PROMPT.md` | how to use the AI export, and the prompt for the browser AI |
| `examples/ai_export_example.md` | an AI export from the practice system (anonymized) |
| `abaplint.json` | syntax check config for ABAP 7.50 |

## Notes
- Deployed and tested on the NPL practice system (7.52, SAP ASE); the background list was verified via a test job.
- Structure: `lcl_report` (selection screen, output) uses the sections `lcl_dump_section`, `lcl_syslog` and
  `lcl_dbcheck` through the interface `lif_section`; `lcl_util` holds shared helpers.
- `lcl_anonymizer` replaces user and server names in the AI export, also inside free texts.
- ABAP Unit tests are at the end of the program (26 tests, risk level harmless, no database access):
  SE38/SE80 → Program → Test → Unit Test, or Ctrl+Shift+F10 in Eclipse.
- Up to 5000 dumps per run (newest first).
- The system log is read from the local application server instance only.
- Needs authorization S_ADMI_FCD = SM21 for the system log section.
