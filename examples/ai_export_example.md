# SAP problem data for AI analysis
- Created by program ZDUMP_EXPLAINER on 2026-11-13 09:00:45
- System: NPL, SAP release 752, database SYBASE, operating system Linux
- Period analysed: 2026-11-06 to 2026-11-13
- Anonymized: yes - user names are USER_nn, server names SERVER_nn
- Content: facts only. Everything marked "rule-based pre-classification" comes from simple rules in the program and may be wrong.

## 1. Short dumps (ST22)
3 short dumps, grouped into 2 problems. Identical dumps (same runtime error, program, include and line) are one problem with a count. Problems are sorted by the program's own rule-based rating, worst first.

### Problem 1: COMPUTE_INT_ZERODIVIDE
- Runtime error: COMPUTE_INT_ZERODIVIDE
- SAP short text: Division by 0 (type I or INT8)
- Exception class: CX_SY_ZERODIVIDE (System Exception Involving Division by Zero)
- Program / include / line: ZDUMP_TEST / ZDUMP_TEST / 14
- Own code (Z/Y/namespace): yes
- Include last changed: 2026-11-06 by USER_01
- Occurrences: 2, by 1 user(s): USER_01
- Client(s): 001; application server(s): SERVER_02
- First / last occurrence: 06.11.2026 22:03:18 / 06.11.2026 22:03:19; per day: 06.11.2026: 2x
- Status: Not seen for 7 days - it may be solved, or the situation has not come up again.
- Rule-based pre-classification by the program (may be wrong): Calculation error, severity Low
- SAP's explanation ("What happened?"): In the current program ZDUMP_TEST, a division ('DIVIDE', '/', 'DIV' or 'MOD') attempted to use operands of type I or INT8 to divide by 0. by 0.
- Source code around the failing line (">>" marks the line where it stopped):
```abap
    10    DATA gv_zero   TYPE i.
    11    DATA gv_result TYPE i.
    12
    13    START-OF-SELECTION.
    14 >>   gv_result = 1 / gv_zero.
    15      WRITE / gv_result.
```

### Problem 2: CALL_FUNCTION_CONFLICT_TYPE
- Runtime error: CALL_FUNCTION_CONFLICT_TYPE
- SAP short text: Type conflict during a function module call
- Exception class: CX_SY_DYN_CALL_ILLEGAL_TYPE (System Exception for All Types of Dynamic Method Calls)
- Program / include / line: ZDUMP_PROBE / ZDUMP_PROBE / 13
- Own code (Z/Y/namespace): yes
- Occurrences: 1, by 1 user(s): USER_01
- Client(s): 001; application server(s): SERVER_02
- First / last occurrence: 06.11.2026 23:00:29 / 06.11.2026 23:00:29; per day: 06.11.2026: 1x
- Status: Not seen for 7 days - it may be solved, or the situation has not come up again.
- Rule-based pre-classification by the program (may be wrong): Call with wrong parameters, severity Low
- SAP's explanation ("What happened?"): The call to function module (?) is incorrect:\n \n The function module interface was defined in such a way that only fields of a particular type can be specified under (?). Field (?) specified here has a different f

## 2. System log (SM21)
39 entries of 18 message types, grouped by message ID. Information messages (SM21 priority W) were left out. Follow-up lines ('> ...') are listed as details of the entry they belong to.

### Message AB0 (3 time(s))
- SM21 priority: very high (red)
- Message text: Runtime error "COMPUTE_INT_ZERODIVIDE" occurred.
- Message text: Runtime error "CALL_FUNCTION_CONFLICT_TYPE" occurred.
- Detail line: Short dump "261106 220318 SERVER_02 USER_01" created.
- Detail line: Short dump "261106 220319 SERVER_02 USER_01" created.
- Detail line: Short dump "261106 230029 SERVER_02 USER_01" created.
- First / last: 06.11.2026 22:03:18 / 06.11.2026 23:00:29
- User(s): USER_01
- Program(s): ZDUMP_TEST, ZDUMP_PROBE
- Client(s): 001
- Rule-based pre-classification by the program (may be wrong): Program crash (short dump), severity High

- SAP documentation of this message:
  > The specified runtime error has occurred in the system.

### Message BY2 (2 time(s))
- SM21 priority: very high (red)
- Message text: Database error 281 at OPC
- Detail line: [ASE Error SQL281][SAP][ASE ODBC Driver][Adaptive Server
- Detail line: Enterprise]120 is not a valid style number when converting
- Detail line: from DATETIME to a character string.
- First / last: 06.11.2026 22:39:01 / 06.11.2026 22:39:01
- User(s): USER_01
- Program(s): ZDUMP_PROBE
- Client(s): 001
- Rule-based pre-classification by the program (may be wrong): Database error, severity High

- SAP documentation of this message:
  > After the attempt to call a database operation, the database system has returned the error code specified in the message, which indicates that the operation concerned could not be executed successfully.

### Message EB9 (2 time(s))
- SM21 priority: very high (red)
- Message text: Batch scheduler: Unable to perform job SAP_DBA_DBH_SETUP_UPDATE_CHECK
- Detail line: Cause: Planned start date too far in the past
- Detail line: Action: De-allocate batch job
- First / last: 06.11.2026 21:09:36 / 06.11.2026 21:09:36
- User(s): USER_02
- Program(s): SAPMSSY2
- Client(s): 000
- Rule-based pre-classification by the program (may be wrong):Background job problem, severity High

- SAP documentation of this message:
  > This message is output by the batch scheduler. It tells you that a batch job could not be executed. The causes of this may be as follows:
  > - One of the central batch control tables cannot be locked. A subsequent message tries to give you a more precise diagnosis. Note that the job in question cannot be executed at this time.
  > - The planned start date of the job to be executedis too long ago in the past (e.g. more than 1 year). There is a general system error for jobs of this kind, which makes this type of job scheduling impossible. To avoid further incorrect behavior, job

### Message Q0I (2 time(s))
- SM21 priority: very high (red)
- Message text: Operating system call bind failed (error no. 98 )
- Operating system error: 98 EADDRINUSE
- First / last: 06.11.2026 21:09:09 / 13.11.2026 08:43:22
- Rule-based pre-classification by the program (may be wrong): Operating system error, severity High

- SAP documentation of this message:
  > The specified operating system call was returned with an error.
  > For communication calls (receive, send, etc) often the cause of errors are network problems.
  > It could also be a configuration problem at operating system level. (file cannot be opened, no space in the file system etc.).

### Message D01 (1 time(s))
- SM21 priority: very high (red)
- Message text: Transaction canceled 00 179 ( )
- Text of the cancel message: Message 00 179: Logon not possible (error in license check)
- First / last: 06.11.2026 21:09:29 / 06.11.2026 21:09:29
- User(s): USER_02
- Program(s): RS_SSI_SERVER_STARTUP
- Client(s): 000
- Rule-based pre-classification by the program (may be wrong): Transaction stopped with an error message, severity High

- SAP documentation of this message:
  > The transaction has been terminated. This may be caused by a termination message from the application (MESSAGE Axxx) or by an error detected by the SAP System due to which it makes no sense to proceed with the transaction. The actual reason for the te

### Message GC3 (2 time(s))
- SM21 priority: high (yellow)
- Message text: The active profile was modified
- Detail line: Profile name = /usr/sap/NPL/SYS/profile/NPL_D00_SERVER_01
- First / last: 06.11.2026 21:14:39 / 13.11.2026 08:48:47
- User(s): USER_02
- Program(s): RSDSOSCO
- Client(s): 000
- Rule-based pre-classification by the program (may be wrong): System profile changed, severity Medium

- SAP documentation of this message:
  > The active profile was modified.
  > The profile in the database does not match the active profile in the operating system. After the profile was activated with the profile maintenance transaction, the profile was changed outside of the profile maintenance transaction (for example with a

### Message IM4 (2 time(s))
- SM21 priority: high (yellow)
- Message text: Port 8101 could not be started for protocol HTTP
- First / last: 06.11.2026 21:09:09 / 13.11.2026 08:43:22
- Rule-based pre-classification by the program (may be wrong): Web server (ICM) problem, severity Medium

- SAP documentation of this message:
  > The configured port could not be opened.
  > Possible reason: The port is occupied by another application.
  > You can find notes about the reasons in the trace file of the ICM (dev_icm) or Web Dispatcher (dev_webdisp).
  > Configure a different port, or stop the application that is blocking the port.
  > On UNIX ports < 1024 can only be bound at the root by the user.
  > You can use the external binding program icmbnd. For more information, see SAP Note 421359.

### Message Q30 (2 time(s))
- SM21 priority: high (yellow)
- Message text: Error in value for profile parameter: abap/test_generation
- Detail line: Value: ON
- Detail line: Cause: Invalid enumeration value (valid values: default on off)
- First / last: 06.11.2026 21:09:05 / 13.11.2026 08:43:13
- Rule-based pre-classification by the program (may be wrong): Configuration error (profile parameter), severity Medium

### Message Q41 (1 time(s))
- SM21 priority: high (yellow)
- Message text: Snapshot 1 created; reason: Hard Shutdown
- First / last: 06.11.2026 23:45:48 / 06.11.2026 23:45:48
- Rule-based pre-classification by the program (may be wrong): System message, severity Medium

- SAP documentation of this message:
  > Snapshots are created
  > - in special situations (such as a "hard" shutdown or if all resources have been exhausted
  > - You do this in transaction SM51.
  > The server writes its status information to the developer traces and then creates an SAP MC snapshot.
  > All available snapshots of an ABAP system can be displaed in transaction SNAPSHOTS, and saved for analysis (using SAP MC) on a local computer. There in the documentation for the "Description" column you can find a short description of the possible rea

### Message IM2 (1 time(s))
- SM21 priority: warning (green)
- Message text: ICM terminated on host SERVER_01 (PID: 1093)
- First / last: 06.11.2026 23:45:50 / 06.11.2026 23:45:50
- Rule-based pre-classification by the program (may be wrong): Web server (ICM) problem, severity Low

- SAP documentation of this message:
  > The Internet Communication Manager (or SAP Web Dispatcher) has been terminated.
  > The Internet Communication Manager (ICM) and SAP Web Dispatcher can be terminated in various ways.
  > - ICM
  > - In transaction SMICM
  > - With the Management Console (MMC)
  > - With a SIGINT signal
  > - By shutting down the entire application server
  > - SAP Web Dispatcher
  > - With the Management Console (MMC)
  > - With a SIGINT signal

### Message R47 (1 time(s))
- SM21 priority: warning (green)
- Message text: Delete session T1_U294_M0 after error: Execution was canceled (Softcancel) [Warning/Session]
- First / last: 13.11.2026 08:58:45 / 13.11.2026 08:58:45
- User(s): USER_01
- Program(s): SAPMHTTP
- Client(s): 001
- Rule-based pre-classification by the program (may be wrong): Connection / RFC problem, severity Low

- SAP documentation of this message:
  > The session has been deleted after an internal error. The sytem log or system trace contains more information on the cause of the error. Contact SAP Support to analyze the error.

### Message S30 (1 time(s))
- SM21 priority: warning (green)
- Message text: SAP gateway was closed
- First / last: 06.11.2026 23:45:50 / 06.11.2026 23:45:50
- Rule-based pre-classification by the program (may be wrong): Connection / RFC problem, severity Low

- SAP documentation of this message:
  > The SAP gateway was terminated. It is therefore not possible to establish CPIC connections.

### Message E10 (6 time(s))
- SM21 priority: warning (green)
- Message text: Buffer SCSA was created with length 4096
- Message text: Buffer RSCPCCC was created with length 6000000
- First / last: 06.11.2026 21:09:03 / 13.11.2026 08:43:43
- User(s): USER_03
- Program(s): sapmscsa
- Client(s): 000
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

- SAP documentation of this message:
  > A storage area or buffer was created with the name you entered.
  > In most cases, the syslog detail information also shows the length (in bytes).
  > Information concerning buffers

### Message BB0 (4 time(s))
- SM21 priority: warning (green)
- Message text: Buffer TBI64 started with 182452224 bytes
- Message text: Buffer CALE started with 600000 bytes
- First / last: 06.11.2026 21:09:15 / 13.11.2026 08:43:38
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

- SAP documentation of this message:
  > This message appears when the system is started and the buffersin Shared Memory are set up.
  > TABL stands for the 100% table buffer,
  > TABLP for the partial table buffer (single-record buffer),
  > CUA for the CUA buffer,
  > EIBUF for the export/import buffer and
  > CALE for the calendar buffer.
  > The size of the buffers (in bytes) can be set in the Netweaver profile.

### Message A10 (3 time(s))
- SM21 priority: warning (green)
- Message text: Initialization complete
- First / last: 06.11.2026 21:09:29 / 13.11.2026 08:43:56
- User(s): USER_02, USER_04
- Program(s): RS_SSI_SERVER_STARTUP
- Client(s): 000
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

- SAP documentation of this message:
  > The ABAP/4 processor has been initialized.

### Message IM1 (2 time(s))
- SM21 priority: warning (green)
- Message text: ICM started on host SERVER_01 (PID: 1093)
- Message text: ICM startedon host SERVER_01 (PID: 19082)
- First / last: 06.11.2026 21:09:07 / 13.11.2026 08:43:20
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

- SAP documentation of this message:
  > The Internet Communication Manager or the SAP Web Dispatcher process has been started, but initialization is not yet completed.

### Message IM3 (2 time(s))
- SM21 priority: warning (green)
- Message text: ICM is ready for operation (PID: 1093)
- Message text: ICM is ready for operation (PID: 19082)
- First /last: 06.11.2026 21:09:26 / 13.11.2026 08:43:51
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

### Message S00 (2 time(s))
- SM21 priority: warning (green)
-Message text: SAP gateway started (PID: 1092)
- Message text: SAP gateway started (PID: 19081)
- First / last: 06.11.2026 21:09:07 / 13.11.2026 08:43:16
- Rule-based pre-classification by the program (may be wrong): Normal system event (start-up), severity Info

- SAP documentation of this message:
  > The SAP gateway has been started.
  > When an SAP instance is started, the gateway process is started by the dispatcher. If the gateway is shutdown in productive operation, the dispatcher restarts it automatically.

## 3. Database (SAP ASE / Sybase)
SAP database: NPL. Sizes in MB; "used" = share of the space that is in use. "Log: shared" = the transaction log is on the same device as the data.

| Database | Data MB | Data used | Log MB | Log used | Last log backup |
| --- | ---: | ---: | ---: | ---: | --- |
| NPL | 25228 | 92% | 2048 | 0% | cleared automatically (trunc log on chkpt) |
| master | 300 | 15% | shared | shared | 2019-05-25 |
| model | 24 | 58% | shared | shared | 2019-05-25 |
| saptempdb | 5120 | 1% | shared | shared | cleared automatically (trunc log on chkpt) |
| saptools | 1024 | 21% | 200 | 1% | cleared automatically (trunc log on chkpt) |
| sybmgmtdb | 148 | 30% | shared | shared | cleared automatically (trunc log on chkpt) |
| sybsecurity | 204 | 25% | 20 | 5% | cleared automatically (trunc log on chkpt) |
| sybsystemdb | 72 | 21% | shared | shared | cleared automatically (trunc log on chkpt) |
| sybsystemprocs | 300 | 52% | shared | shared | cleared automatically (trunc log on chkpt) |
| tempdb | 3072 | 0% | shared | shared | cleared automatically (trunc log on chkpt) |

Findings of the program's rules (thresholds: data 85%/95%, log 70%/90%):
- [Medium] Database NPL: data space 92% used
- [Low] Database NPL: transaction log is cleared automatically (no log backups)

Largest tables in NPL (from database statistics, approximate):

| Table | Rows | Size MB with indexes |
| --- | ---: | ---: |
| REPOSRC | 1768164 | 1800 |
| SMIMCONT1 | 448816 | 1067 |
| WBCROSSGT | 5950431 | 1008 |
| DOKTL | 6247728 | 775 |
| E071 | 7166867 | 729 |
| E071K | 2326793 | 416 |
| BALDAT | 683576 | 373 |
| DD03L | 1351547 | 322 |
| /SLOAP/CLU_STORT | 96372 | 276 |
| LTR2_ROBJ_ROX | 2050627 | 256 |
