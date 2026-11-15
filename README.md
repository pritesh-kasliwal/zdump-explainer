# ZDUMP_EXPLAINER - SAP problems explained for everyone

One readable report with three sections (each can be switched on/off). Sections 1 and 2 work on every
database (they read SAP's own tables with Open SQL); section 3 is for SAP HANA.

1. **Short dumps (ST22)**
2. **System log (SM21)**: entries grouped by message ID, follow-up lines (`> ...`) attached to their entry,
   plain-language explanation for common kinds (database errors, cancelled transactions, background jobs,
   invalid profile parameters, ICM/ports, OS errors, work process restarts, RFC, logon, buffers, start-up events),
   SAP's own documentation for the message and the text of cancel messages. Information messages are hidden
   unless "Also SM21 information messages" is set.
3. **Database (DB02), SAP HANA**: services that do not run, memory use against the allocation limit (now and
   peak), table unloads because of low memory, disks of the data / log / trace / backup areas, backups (last
   full and log backup, failed backups, log mode), HANA's own current alerts, the largest tables in memory
   with clean-up hints (e.g. SNAP → RSSNAPDL, TST03 → RSPO1041, BALDAT → SLG2) and table partitions close
   to HANA's limit of 2 billion rows. On other databases the section says so; the others work as usual.

Short dumps in detail:

- **Duplicates grouped**: same runtime error + program + include + line = one problem.
  It is explained once, with how many times it happened, first/last time and which users.
- **Plain language** for each problem: what went wrong, typical causes, who should act, what to do next.
  Built-in explanations for ~20 common error families (TIME_OUT, memory, MESSAGE_TYPE_X, null references,
  conversion and calculation errors, duplicates, database, RFC, syntax errors, ...), plus SAP's own short text.
- **Own code vs. SAP code**: tells whether your team can fix it or you should search SAP Notes.
- **Code at the failing line** (with the line highlighted) and who last changed it.
- **Severity** (High / Medium / Low) from error type, frequency and number of users; worst first.
- **Responsible owner** for every problem (see below), with full name and e-mail from SU01.
- **Exclusion list**: known dumps you do not want to see are left out (table `ZDUMP_EXCL`).
- **E-mail** (e.g. nightly job): a ZIP with the AI export and the HTML report to one or more addresses.

Read-only: it changes nothing in the system (except the outgoing mail, if e-mail addresses are given).

## Who is responsible?
For every short dump problem the report names one owner:

| Situation | Responsible |
|---|---|
| Database or connection (RFC) error | support team - Basis checks first |
| BW transformation (dump in a generated program `GP...`) | the person who changed the transformation last |
| Own code (Z/Y/namespace) | the person who changed the include / program last |
| SAP standard code | support team |
| That person is not in SU01, is locked, expired, not a dialog user, or a technical user (DDIC, SAP*) | support team, with the reason |

The support team's name is entered on the screen ("Support team (default owner)"). SU01 data is read in the
client where the report runs - run it in the client where the developers have their users.

## Exclusion list (ZDUMP_EXCL)
Dumps you know about and do not want in the report (e.g. a known SAP bug waiting for a note, test programs):

| Field | Meaning |
|---|---|
| Runtime error | e.g. `TIME_OUT`, or a pattern like `CONVT_*`; `*` = all |
| Program | e.g. `ZSALES_REPORT`, or a pattern like `ZTEST*`; `*` = all. Compared with program and include |
| Valid to | last day the entry applies; empty = always |
| Reason, Created by, Created on | for documentation |

The report says how many dumps were left out; tick "Show excluded dumps too" to see them anyway.

**No AI API? Use the AI export.** Output "AI export file" saves all collected facts as one Markdown file
(with user, system and server names; optional anonymization) that you upload into a browser AI together with the prompt in
[AI_REPORT_PROMPT.md](AI_REPORT_PROMPT.md).

## Install
1. **Table `ZDUMP_EXCL`** (SE11, or in Eclipse ADT paste [ddic/zdump_excl.tabl.ddl](ddic/zdump_excl.tabl.ddl)):
   transparent table, delivery class C, display/maintenance allowed, client-independent (no MANDT):

   | Field | Key | Data element |
   |---|---|---|
   | ERRID | X | S380ERRID |
   | PROGNAME | X | PROGNAME |
   | VALID_TO | | DATBI |
   | REASON | | TEXT80 |
   | CREATED_BY | | ERNAM |
   | CREATED_ON | | ERDAT |

   For SM30: SE11 → Utilities → Table Maintenance Generator (authorization group `&NC&`, own function group,
   one step, overview screen 1). Without it, maintain the entries with SE16N.
2. SE38: create the executable program `ZDUMP_EXPLAINER` (e.g. local in `$TMP`).
3. Paste the content of `src/zdump_explainer.prog.abap`, save and activate.

The selection screen texts are set in the code, so no text elements need to be maintained.
Requires SAP NetWeaver 7.50 or higher.

## Run
SE38 → `ZDUMP_EXPLAINER`

| Field on the screen | Meaning |
|---|---|
| Short dumps / System log / Database | which areas to analyse (default: all) |
| Also SM21 information messages | also show SM21 information messages (work process start/stop etc.) |
| Period (date) | default: last 7 days; used for short dumps and the system log |
| User, Client | optional filters (short dumps and system log) |
| Runtime error, Application server | optional filters (short dumps) |
| Only own code (Z/Y) dumps | only dumps in Z/Y/namespace programs |
| Support team (default owner) | name shown as responsible when no developer is (default "SAP support team") |
| Show excluded dumps too | ignore the exclusion list `ZDUMP_EXCL` |
| HTML report / ALV list / AI export file | how to show the result (ALV covers short dumps only) |
| Save to file (full path) | HTML report: e.g. `C:\temp\dumps.html` to share by e-mail. AI export: empty = save dialog |
| Language of SAP texts | for SAP's error texts and documentation |
| Send to e-mail address(es) | empty = no mail. Several addresses: arrow button next to the field |
| Sender (empty = own SU01 mail) | sender address; empty = e-mail of the user running the report (the job's step user) |

Two AI export options are hidden (not on the screen; set them with `SUBMIT ... WITH`, or remove `NO-DISPLAY`):
`P_AISRC` include source code lines (default on), `P_ANON` replace names by USER_nn / SERVER_nn (default off).
F4 on "Save to file" opens the Windows save dialog.

## Nightly job with e-mail
With e-mail addresses on the screen the report sends **one mail** with a ZIP file `SAP_problems_<SID>_<date>.zip`:

- `.md` - the AI export: upload it into your AI tool together with the prompt from
  [AI_REPORT_PROMPT.md](AI_REPORT_PROMPT.md)
- `.html` - the full report for people, opens in any web browser

The mail text shows the "at a glance" lines, so you see at once whether something is wrong.

Set-up:
1. SE38 → `ZDUMP_EXPLAINER` → fill the screen: e-mail addresses, date **Period** with dynamic date
   selection (Goto → Variants → Save as Variant → Period: "Selection variable" D, "Current date - xxx"
   e.g. `Current date - 1` to `Current date`) → save as variant, e.g. `NIGHTLY`.
2. SM36: job `ZDUMP_EXPLAINER_NIGHTLY`, step = ABAP program `ZDUMP_EXPLAINER` with variant `NIGHTLY`,
   start condition: date/time e.g. 02:00, **periodic job** → daily.
3. The step user needs an e-mail address in SU01 (or fill "Sender") and authorization for
   ST22 / SM21 data. The output choice does not matter for the mail.

The mail is sent through SAPconnect: Basis must have set up SCOT (SMTP node) and the send job (`RSCONN01`).
SOST shows whether a mail left the system. The job's spool list starts with "E-mail ... sent to ..." or
"E-mail NOT sent: <reason>".

Without e-mail the job writes a plain list to the spool - or, with "AI export file", the export text.

## Database section (SAP HANA)
Read-only native SQL (ADBC, default connection) on the HANA monitoring views - the same sources DB02 /
DBACOCKPIT use:

| Check | View | Rule |
|---|---|---|
| Services running | `M_SERVICES` | not running → High |
| Restart in the period | `M_DATABASE` | Low (explains system log entries and dumps at that time) |
| Memory | `M_HOST_RESOURCE_UTILIZATION` | used ≥ 80% of the allocation limit → Medium, ≥ 90% → High; peak ≥ 95% → Medium |
| Low-memory unloads | `M_CS_UNLOADS` | any in the period → Medium |
| Disks | `M_DISKS` | ≥ 85% → Medium, ≥ 95% → High (one finding per file system) |
| Full backup | `M_BACKUP_CATALOG` | never → High; older than 7 days → Medium, 14 days → High |
| Log backup | `M_BACKUP_CATALOG`, `M_INIFILE_CONTENTS` | log mode normal: older than 2 h → Medium, 24 h → High; log mode overwrite → Low |
| Failed backups | `M_BACKUP_CATALOG` | any in the period → Medium |
| HANA alerts | `_SYS_STATISTICS.STATISTICS_CURRENT_ALERTS` | rating 4/5 → High |
| Largest tables | `M_CS_TABLES` (SAP schema) | clean-up table ≥ 1 GB in memory → Low |
| Partition row limit | `M_CS_TABLES` | > 1.5 billion rows → Medium, > 1.9 billion → High |

Each view is read on its own. If one cannot be read (missing authorization of the database user, older
HANA revision), the report lists it under "Not checked" and the other checks still run.
**Not yet tested on a real HANA system** - first check the "Not checked" box and the figures against DB02.

## Files
| File | Purpose |
|---|---|
| `src/zdump_explainer.prog.abap` | the program |
| `src/zdump_excl.tabl.xml` | table `ZDUMP_EXCL` in abapGit format (also used by abaplint) |
| `ddic/zdump_excl.tabl.ddl` | table `ZDUMP_EXCL` as DDL source, to paste in Eclipse ADT |
| `AI_REPORT_PROMPT.md` | how to use the AI export, and the prompt for the browser AI |
| `abaplint.json` | syntax check config for ABAP 7.50 |

## Notes
- Structure: `lcl_report` (selection screen, output) uses the sections `lcl_dump_section`, `lcl_syslog`
  and `lcl_hana_check` through the interface `lif_section`; `lcl_util` holds shared helpers.
- `lcl_anonymizer` replaces user and server names in the AI export, also inside free texts.
- E-mail: `lcl_mail` packs the ZIP (CL_ABAP_ZIP) and sends it with BCS (CL_BCS). Sending needs a
  `COMMIT WORK` - the only database change of the program (the mail in SOST).
- ABAP Unit tests are at the end of the program (38 tests, risk level harmless, no database access):
  SE38/SE80 → Program → Test → Unit Test, or Ctrl+Shift+F10 in Eclipse.
- Up to 5000 dumps per run (newest first).
- The system log is read from the local application server instance only.
- Needs authorization S_ADMI_FCD = SM21 for the system log section.
- Owner lookup reads TRDIR (last change of programs), RSTRAN (BW transformations; part of every NetWeaver
  ABAP system) and USR02 / USR21 / ADRP / ADR6 (SU01 user, name, e-mail).
