# Problem report with a browser AI (no API needed)

ZDUMP_EXPLAINER can export everything it collects as one Markdown file. You upload that file
into the AI chat you use in the browser (Claude, ChatGPT, Copilot, Gemini, ...) together with the
prompt below, and the AI writes the report.

## 1. Before you start

- **Check your company's AI rules.** Only upload to an AI tool your company allows for internal data.
- **User, system and server names are kept** by default, so the report shows who has the problem and
  where. If you ever need to hide them, tick "Anonymize users and servers": user names then become
  `USER_01`, `USER_02`, ... and server names `SERVER_01`, ... (the same name always gets the same alias,
  also inside message texts).
- **Source code:** "Include source code" adds 7 lines around each failing line. If your company does
  not allow sharing code, switch it off - the report is then less precise for own (Z/Y) programs.

## 2. Create the file

1. SE38 → `ZDUMP_EXPLAINER`.
2. Choose the areas (short dumps, system log, database) and the period.
3. Output: select **AI export file**. Leave "Save to file" empty - a save dialog opens
   (or enter a full path, e.g. `C:\temp\sap_problems.md`).
4. Execute (F8). The program saves `SAP_problems_<SID>_<date>.md`.

Without access to SAP GUI downloads: run the same variant as a background job (F9). The export is
then written to the spool, which you can save from SM37 / SP01.

An example export from a practice system is in [examples/ai_export_example.md](examples/ai_export_example.md).

## 3. Ask the AI

1. Open a **new** chat.
2. Attach the `.md` file.
3. Paste the prompt from section 4 and send it.

If the AI tool cannot take file uploads, paste the prompt first and then the content of the file
below it. If the file is too long for the chat, export a shorter period or one area at a time.

## 4. The prompt

Copy everything between the lines.

---

```text
You are an experienced SAP Basis administrator and ABAP developer who is very good at explaining
technical problems to people without IT background.

The attached file was created by the SAP report ZDUMP_EXPLAINER. It contains facts from one SAP
system for a period:
  1. Short dumps (ST22), already grouped: identical dumps are one problem with a count.
  2. System log (SM21), grouped by message ID, with SAP's own documentation of each message.
  3. Database figures (DB02, SAP ASE): space and log usage per database, largest tables.
The file header tells you the SAP release, the database and the period. Lines marked
"rule-based pre-classification" come from simple rules in the report and may be wrong - check
them against the facts.

TASK
Write a problem report for the people who use and run this system: end users, key users,
developers and the Basis team. Everybody must find what concerns them quickly.

STRUCTURE
1. Title "SAP problem report - system <SID>", the period, and a summary of 3-4 sentences:
   how healthy is the system, what is most urgent.
2. At a glance: one table with ALL findings from all sections, most urgent first. Columns:
   #, Severity, What happened (plain words, max. 8 words), Area (Short dumps / System log /
   Database), How often, Still happening? (yes / no / unknown), Who acts (User / Key user /
   Developer / Basis).
3. Do this first: the 3 most important actions, one sentence each, with the owner.
4. Short dumps - one block per problem:
   - What went wrong: 1-3 plain sentences, no jargon.
   - Why it happens: likely causes, most likely first. Say which facts in the file support each one.
   - What you can do now (end user).
   - How to fix it (developer / Basis): concrete steps with transaction codes. If source code is
     included, point at the line marked ">>" and explain what goes wrong there.
   - Example fix in ABAP - only for own code (Z/Y/namespace) with source code in the file.
     Show before and after. Use only ABAP syntax available in the SAP release from the file
     header (for example release 752 = ABAP 7.52: no newer language features). Keep the
     original logic apart from the fix.
   - Still happening? Use the status and dates in the file.
   - Who is affected and where: users, clients and application servers from the file.
   - SAP Notes: relevant SAP Notes with number, title and link
     (https://me.sap.com/notes/<number>), see the rules below. Always add search terms
     (runtime error, program, exception class) for finding further notes.
   - A short support ticket text, ready to copy, including user, client, server and time.
5. System log:
   - Combine messages that describe the same event into one finding. Examples: the runtime error
     entries (AB0) belong to the short dumps of section 1; many start-up messages at the same
     time mean one system restart - say when it happened.
   - For each finding: what happened, why it matters (or clearly "no action needed"), who acts,
     next steps with transaction codes, and relevant SAP Notes (same rules as above).
6. Database: explain data and log usage in plain words and how urgent it is. Explain the
   findings. For the largest tables say which are normal system tables and which hold old data
   that can be cleaned up, with the usual standard clean-up program or job.
7. Connections: point out where findings in different sections belong together (for example a
   database error in the system log at the same time as a short dump).
8. Open questions: what is missing to be sure about a cause, and where to find it in the
   system (for example "ST22 -> open the dump -> Chosen variables").
9. Glossary: every SAP term you used (short dump, runtime error, work process, profile parameter,
   transaction log, ...), one plain line each.

SEVERITY
High = users are blocked, data can be lost, the system may stop, or it happens often to many
users. Medium = should be fixed soon. Low = rare or harmless. Info = no action needed.

RULES
- Use only the facts in the file and general SAP knowledge. Never invent numbers, dates, user
  names, program names or transaction codes. When you are not sure, write "likely" or
  "to be checked" and say how to check it.
- SAP Notes: name a note only when you are confident that this number exists and fits this exact
  problem (runtime error, program or component, release). Give number, title and the link
  https://me.sap.com/notes/<number>, and mark it "please verify". Never make up a note number
  - if you know no fitting note, write "No specific SAP Note known" and give the search terms.
- Plain language first, technical details after it. Short sentences.
- Name users, clients, systems and servers exactly as in the file, so the readers know who is
  affected and where. If the file uses aliases (USER_nn, SERVER_nn), keep the aliases.
- If a problem was obviously caused by a test (for example a program called ..._TEST that
  divides by zero on purpose), say so and rate it accordingly.
- Write in English.

OUTPUT
One self-contained HTML page (all CSS inline, no external files or scripts) with colour badges
for the severity (High red, Medium orange, Low blue, Info grey), a table of contents with links
to the sections, and each finding in its own box. If you cannot create HTML here, write the
same structure in Markdown.
```

---

## 5. Useful follow-up questions

- "Explain problem 2 in more detail for a junior developer, step by step."
- "Write a short e-mail to the Basis team about the database finding."
- "Translate the support ticket text of problem 1 into German."
- "Which of these findings can I ignore in a test system?"
- With two files attached (last week and this week): "Compare the two exports. What is new,
  what is gone, what got worse?"

## Notes

- The quality of the report depends on the AI model. Check important statements - especially
  fixes for production systems - before you act on them.
- Open every SAP Note link before you rely on it. AI models sometimes give note numbers that do
  not exist or belong to a different problem; that is why the prompt marks them "please verify".
- The example file was exported with "Anonymize users and servers" switched on, so it shows
  aliases. Your own exports show the real names unless you tick that option.
- The program's own HTML report (output "HTML report") needs no AI and stays inside SAP. Use the AI
  export when you want a second opinion or a report written in a different way.
