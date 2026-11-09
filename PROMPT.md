# Prompt for Claude Code

Paste this into Claude Code (in VS Code, with this folder open and the ABAP MCP server connected):

---

Read CLAUDE.md first.

Deploy the program in src/zdump_explainer.prog.abap to the SAP system as executable program
ZDUMP_EXPLAINER in package $TMP:

1. Run abaplint (npx @abaplint/cli) and fix real syntax problems only - keep ABAP 7.50 syntax and do not
   change the logic.
2. Create the program if it does not exist, write the source, run the syntax check in SAP.
3. If SAP reports errors, fix them in src/ with minimal changes, write again and re-check until it is clean.
4. Create the selection texts and text symbols listed in the header comment if the MCP server can do it;
   otherwise give me the list to enter in SE38.
5. Activate the program.
6. Tell me what you changed (with a short diff summary) and how to run it.

Notes:
- Dumps are read from view SNAP_BEG (SEQNO = '000'); FLIST is parsed as ID(2) + length(3) + value
  with FC = runtime error, AP = program, AI = include, AL = line.
- SAP's error texts come from table SNAPT (TTYPE = 'K' short text). If field names differ in this release,
  check the table in the system and adapt.
- Afterwards, if there are no dumps in the system yet, write a tiny test program ZDUMP_TEST in $TMP that
  divides by zero, run it twice to create two identical dumps, and run ZDUMP_EXPLAINER to show they are
  grouped into one problem counted 2 times.
