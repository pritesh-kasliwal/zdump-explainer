*&---------------------------------------------------------------------*
*& Report ZDUMP_EXPLAINER
*&---------------------------------------------------------------------*
*& Explains SAP system problems in plain language, in three sections:
*&   1. Short dumps (ST22)   2. System log (SM21)   3. Database (DB02)
*&
*& Short dumps:
*& - Reads dump headers from SNAP_BEG (SEQNO = '000')
*& - Groups duplicates (same error + program + include + line): each
*&   problem is explained ONCE, with how often it happened, when, and
*&   by how many users
*& - For every problem: what went wrong (plain language), SAP's own
*&   explanation (SNAPT), likely causes, what the user can do now, how a
*&   developer/Basis fixes it (with a code example), whether it is still
*&   happening, the source code around the failing line, search terms
*&   for SAP Notes and a ready-to-copy text for a support ticket
*& System log:
*& - Reads SM21 entries of the local instance via CL_SYSLOG, groups them
*&   by message ID, attaches continuation lines ('> ...') to their entry
*& - Explains each kind of message, adds SAP's documentation (DOCU_GET,
*&   class SL) and the text of cancel messages (T100)
*& Database (SAP ASE / Sybase only):
*& - Data space and transaction log per database, log backups, offline
*&   databases, largest tables with clean-up hints. Native SQL SELECTs on
*&   the ASE catalog (master..sysdatabases / sysusages), like DB02 does
*&
*& - Output: HTML report (foreground) and/or download, ALV overview
*&   (short dumps only), or a simple list when running in background
*&
*& ABAP 7.50. Read-only: the program changes nothing in the system.
*&
*& Selection texts (SE38 -> Goto -> Text elements -> Selection texts):
*&   P_DUMP  Short dumps (ST22)  P_SLOG  System log (SM21)
*&   P_SLINF Include information messages        P_DB    Database (DB02)
*&   S_DATUM Date        S_UNAME User         S_ERRID Runtime error
*&   S_MANDT Client      S_AHOST App server   P_CUST  Only own code (Z/Y)
*&   P_HTML  HTML report P_ALV   ALV overview (short dumps)
*&   P_FILE  Save HTML to file   P_LANG  Text language for SAP texts
*& Text symbols: B01 'Period and filters', B02 'Output',
*&               B03 'What to analyse'
*&---------------------------------------------------------------------*
REPORT zdump_explainer.

TABLES snap_beg.

DATA gv_errid TYPE c LENGTH 40.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-b03.
PARAMETERS: p_dump  AS CHECKBOX DEFAULT 'X',
            p_slog  AS CHECKBOX DEFAULT 'X',
            p_slinf AS CHECKBOX,
            p_db    AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-b01.
SELECT-OPTIONS: s_datum FOR snap_beg-datum,
                s_uname FOR snap_beg-uname,
                s_errid FOR gv_errid,
                s_mandt FOR snap_beg-mandt,
                s_ahost FOR snap_beg-ahost.
PARAMETERS p_cust AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-b02.
PARAMETERS: p_html RADIOBUTTON GROUP out DEFAULT 'X',
            p_alv  RADIOBUTTON GROUP out,
            p_file TYPE string LOWER CASE,
            p_lang TYPE sylangu DEFAULT sy-langu.
SELECTION-SCREEN END OF BLOCK b2.

INITIALIZATION.
  s_datum-sign   = 'I'.
  s_datum-option = 'BT'.
  s_datum-low    = sy-datum - 7.
  s_datum-high   = sy-datum.
  APPEND s_datum.

*----------------------------------------------------------------------*
* lcl_util - stateless helpers shared by all sections
*   HTML escaping, date/time formatting, "is it still happening?" text,
*   small usage bars and SAP documentation (DOCU_GET) as HTML.
*----------------------------------------------------------------------*
CLASS lcl_util DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    "! Escape text for HTML output (&lt; &gt; &amp; ...)
    CLASS-METHODS h
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.
    "! Escape every line of a list and join them with a separator
    CLASS-METHODS join_h
      IMPORTING it_list        TYPE tt_string
                iv_sep         TYPE string DEFAULT `, `
      RETURNING VALUE(rv_html) TYPE string.
    "! Date and time in the user's format, e.g. '06.11.2026 22:03:19'
    CLASS-METHODS fmt_ts
      IMPORTING iv_date        TYPE d
                iv_time        TYPE t
      RETURNING VALUE(rv_text) TYPE string.
    "! Plain-language status from the date a problem was last seen.
    "! ev_class is the CSS class: 'act' (today/yesterday) or 'old'
    CLASS-METHODS age_status
      IMPORTING iv_date  TYPE d
      EXPORTING ev_text  TYPE string
                ev_class TYPE string.
    "! Append a value to a list if it is not empty, not yet in the list
    "! and the list has fewer than iv_max entries (keeps lists short)
    CLASS-METHODS add_unique
      IMPORTING iv_value TYPE csequence
                iv_max   TYPE i DEFAULT 1000
      CHANGING  ct_list  TYPE tt_string.
    "! Small HTML usage bar, green / orange (>= iv_warn) / red (>= iv_crit)
    CLASS-METHODS bar
      IMPORTING iv_pct         TYPE i
                iv_warn        TYPE i
                iv_crit        TYPE i
      RETURNING VALUE(rv_html) TYPE string.
    "! SAP documentation (DOCU_GET) as simple HTML, falls back to English
    CLASS-METHODS docu_html
      IMPORTING iv_id          TYPE csequence
                iv_object      TYPE csequence
                iv_langu       TYPE sylangu
      RETURNING VALUE(rv_html) TYPE string.
ENDCLASS.

CLASS lcl_util IMPLEMENTATION.

  METHOD h.
    rv_text = escape( val = iv_text format = cl_abap_format=>e_html_text ).
  ENDMETHOD.

  METHOD join_h.
    DATA lt_html TYPE tt_string.
    LOOP AT it_list INTO DATA(lv_line).
      APPEND h( lv_line ) TO lt_html.
    ENDLOOP.
    rv_html = concat_lines_of( table = lt_html sep = iv_sep ).
  ENDMETHOD.

  METHOD fmt_ts.
    rv_text = |{ iv_date DATE = USER } { iv_time TIME = USER }|.
  ENDMETHOD.

  METHOD age_status.
    " today or yesterday = still a current problem; older = maybe solved
    DATA lv_days TYPE i.
    CLEAR: ev_text, ev_class.
    IF iv_date IS INITIAL.
      RETURN.
    ENDIF.
    lv_days = sy-datum - iv_date.
    IF lv_days <= 0.
      ev_text  = `Still happening: last seen today.`.
      ev_class = `act`.
    ELSEIF lv_days = 1.
      ev_text  = `Last seen yesterday - most likely still a problem.`.
      ev_class = `act`.
    ELSE.
      ev_text  = |Not seen for { lv_days } days - it may be solved, or the situation has not come up again.|.
      ev_class = `old`.
    ENDIF.
  ENDMETHOD.

  METHOD add_unique.
    DATA lv_value TYPE string.
    lv_value = iv_value.
    CONDENSE lv_value.
    IF lv_value IS INITIAL OR lines( ct_list ) >= iv_max OR line_exists( ct_list[ table_line = lv_value ] ).
      RETURN.
    ENDIF.
    APPEND lv_value TO ct_list.
  ENDMETHOD.

  METHOD bar.
    " small usage bar: green / orange (>= warn) / red (>= crit)
    DATA(lv_width) = nmax( val1 = 0 val2 = nmin( val1 = 100 val2 = iv_pct ) ).
    DATA(lv_level) = COND string( WHEN iv_pct >= iv_crit THEN `crit`
                                  WHEN iv_pct >= iv_warn THEN `warn`
                                  ELSE `good` ).
    rv_html = |<span class="bar"><span class="fill { lv_level }" style="width:{ lv_width }%"></span></span> { iv_pct }%|.
  ENDMETHOD.

  METHOD docu_html.
    " SAP documentation (DOCU_GET) as simple HTML: headings bold, paragraphs on own lines
    DATA lt_lines TYPE STANDARD TABLE OF tline.
    DATA lv_id TYPE dokhl-id.
    DATA lv_object TYPE dokhl-object.
    DATA lv_para TYPE string.
    DATA lv_text TYPE string.
    DATA lt_html TYPE tt_string.

    lv_id = iv_id.
    lv_object = iv_object.
    CALL FUNCTION 'DOCU_GET'
      EXPORTING
        id     = lv_id
        langu  = iv_langu
        object = lv_object
      TABLES
        line   = lt_lines
      EXCEPTIONS
        OTHERS = 1.
    IF ( sy-subrc <> 0 OR lt_lines IS INITIAL ) AND iv_langu <> 'E'.
      CALL FUNCTION 'DOCU_GET'
        EXPORTING
          id     = lv_id
          langu  = 'E'
          object = lv_object
        TABLES
          line   = lt_lines
        EXCEPTIONS
          OTHERS = 1.
    ENDIF.

    LOOP AT lt_lines INTO DATA(ls_line) TO 40.
      IF ls_line-tdformat = '/*' OR ls_line-tdformat = '/:'.
        CONTINUE.     " SAPscript comments and commands
      ENDIF.
      lv_text = ls_line-tdline.
      " remove SAPscript formatting tags like <ZH> ... </>, keep escaped < and >
      REPLACE ALL OCCURRENCES OF REGEX `<[^<>()]{1,40}>` IN lv_text WITH ``.
      REPLACE ALL OCCURRENCES OF `<(>` IN lv_text WITH `<`.
      REPLACE ALL OCCURRENCES OF `<)>` IN lv_text WITH `>`.
      IF ls_line-tdformat = '='.
        lv_para = lv_para && lv_text.
      ELSEIF ls_line-tdformat IS INITIAL.
        lv_para = |{ lv_para } { lv_text }|.
      ELSE.
        IF lv_para IS NOT INITIAL.
          APPEND h( condense( lv_para ) ) TO lt_html.
        ENDIF.
        CLEAR lv_para.
        IF ls_line-tdformat CP 'U*'.
          APPEND |<b>{ h( condense( lv_text ) ) }</b>| TO lt_html.
        ELSEIF ls_line-tdformat CP 'B*' OR ls_line-tdformat CP 'N*'.
          lv_para = |- { lv_text }|.
        ELSE.
          lv_para = lv_text.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF lv_para IS NOT INITIAL.
      APPEND h( condense( lv_para ) ) TO lt_html.
    ENDIF.
    rv_html = concat_lines_of( table = lt_html sep = `<br>` ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lif_section - one analysed area of the report (system log, database).
*   The report only talks to sections through this interface, so a new
*   area (e.g. SM37 job errors) can be added without changing the report.
*----------------------------------------------------------------------*
INTERFACE lif_section.
  "! Read and evaluate the data of this area
  METHODS analyze.
  "! Complete HTML of the section (heading, explanation, findings)
  METHODS get_html
    RETURNING VALUE(rt_html) TYPE lcl_util=>tt_string.
  "! One line for the 'At a glance' box at the top of the report
  METHODS summary_html
    RETURNING VALUE(rv_html) TYPE string.
  "! Plain list for background runs (spool)
  METHODS write_list.
ENDINTERFACE.

" ABAP Unit test classes (end of the program) may look into the private parts
CLASS ltc_syslog DEFINITION DEFERRED.
CLASS ltc_dbcheck DEFINITION DEFERRED.
CLASS ltc_dump_section DEFINITION DEFERRED.

*----------------------------------------------------------------------*
* lcl_syslog - section 2: system log (SM21)
*   Reads the SM21 entries of the local instance (CL_SYSLOG), groups
*   them by message ID and explains each kind in plain language.
*----------------------------------------------------------------------*
CLASS lcl_syslog DEFINITION FINAL FRIENDS ltc_syslog.
  PUBLIC SECTION.
    INTERFACES lif_section.

    TYPES:
      tt_user_range   TYPE RANGE OF syuname,
      tt_client_range TYPE RANGE OF symandt,

      "! Plain-language explanation of one kind of system log message
      BEGIN OF ty_advice,
        category TYPE string,
        meaning  TYPE string,
        causes   TYPE string,
        user_do  TYPE string,
        steps    TYPE string,
        look_at  TYPE string,     " transactions to check
        normal   TYPE abap_bool,  " normal operation, no problem -> severity Info
      END OF ty_advice,

      "! All entries of one message ID in the period, aggregated
      BEGIN OF ty_group,
        rank       TYPE i,
        msgid      TYPE rslgno,
        prio       TYPE c LENGTH 1,   " SM21 priority: R very high, Y high, G warning, W info
        severity   TYPE string,
        count      TYPE i,
        first_ts   TYPE string,       " YYYYMMDDHHMMSS, for comparing
        last_ts    TYPE string,
        first_seen TYPE string,       " formatted for output
        last_seen  TYPE string,
        last_datum TYPE d,
        users      TYPE lcl_util=>tt_string,
        tcodes     TYPE lcl_util=>tt_string,
        programs   TYPE lcl_util=>tt_string,
        clients    TYPE lcl_util=>tt_string,
        examples   TYPE lcl_util=>tt_string,   " up to 3 different message texts
        details    TYPE lcl_util=>tt_string,   " continuation lines ('> ...')
        os_errors  TYPE lcl_util=>tt_string,
        advice     TYPE ty_advice,             " determined once in analyze
        sort_key   TYPE i,
      END OF ty_group,
      "! Secondary hashed key: find the group of a message ID in constant time
      tt_group TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY
               WITH UNIQUE HASHED KEY by_msgid COMPONENTS msgid.

    "! @parameter iv_from | first day of the period
    "! @parameter iv_to | last day of the period
    "! @parameter iv_include_info | also show information messages (priority W)
    "! @parameter it_users | only entries of these users (empty = all)
    "! @parameter it_clients | only entries of these clients (empty = all)
    "! @parameter iv_langu | language for SAP texts (documentation, T100)
    METHODS constructor
      IMPORTING iv_from         TYPE d
                iv_to           TYPE d
                iv_include_info TYPE abap_bool
                it_users        TYPE tt_user_range OPTIONAL
                it_clients      TYPE tt_client_range OPTIONAL
                iv_langu        TYPE sylangu.

  PRIVATE SECTION.
    DATA mv_from TYPE d.
    DATA mv_to TYPE d.
    DATA mv_include_info TYPE abap_bool.
    DATA mt_users TYPE tt_user_range.
    DATA mt_clients TYPE tt_client_range.
    DATA mv_langu TYPE sylangu.

    DATA mv_error TYPE string.
    DATA mv_entries TYPE i.
    DATA mt_groups TYPE tt_group.

    "! Filter and group the entries, attach continuation lines, rate the groups
    METHODS process_entries
      IMPORTING it_entries TYPE rslgentr_tab.
    "! Add one (main) log entry to the group of its message ID
    METHODS add_entry
      IMPORTING is_entry TYPE rslgentry.
    "! Severity from SM21 priority and frequency, then sort and rank
    METHODS rate_groups.
    METHODS count_high
      RETURNING VALUE(rv_count) TYPE i.
    "! Knowledge base: explanation by message ID and typical words in the text
    METHODS get_advice
      IMPORTING is_group         TYPE ty_group
      RETURNING VALUE(rs_advice) TYPE ty_advice.
    "! Text of the message behind 'Transaction canceled' + message class and number
    METHODS cancel_message
      IMPORTING is_group       TYPE ty_group
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_syslog IMPLEMENTATION.

  METHOD constructor.
    mv_from         = iv_from.
    mv_to           = iv_to.
    mv_include_info = iv_include_info.
    mt_users        = it_users.
    mt_clients      = it_clients.
    mv_langu        = iv_langu.
  ENDMETHOD.

  METHOD lif_section~analyze.
    " read the SM21 entries of the period (local instance), then evaluate them
    DATA lt_entries TYPE rslgentr_tab.
    DATA lv_from TYPE rslgtime.
    DATA lv_to TYPE rslgtime.

    " CL_SYSLOG compares the first 14 characters: YYYYMMDDHHMMSS
    lv_from = |{ mv_from }000000|.
    lv_to   = |{ mv_to }235959|.
    TRY.
        DATA(lo_filter) = NEW cl_syslog_filter( ).
        lo_filter->set_filter_datetime( im_datetime_from = lv_from im_datetime_to = lv_to ).
        lt_entries = cl_syslog=>get_instance_by_filter( lo_filter )->get_entries( ).
      CATCH cx_syslog_read_authorization.
        mv_error = `You are not authorized to read the system log (authorization object S_ADMI_FCD, value SM21).`.
        RETURN.
      CATCH cx_root INTO DATA(lx_error).
        mv_error = |The system log could not be read: { lx_error->get_text( ) }|.
        RETURN.
    ENDTRY.

    process_entries( lt_entries ).
  ENDMETHOD.

  METHOD process_entries.
    " Continuation lines ('> ...') carry details of the entry before them. They are written by
    " the same work process, so we remember per work process which message ID it wrote last.
    TYPES: BEGIN OF ty_parent,
             instance  TYPE instancex,
             processid TYPE rslgselnum,
             msgid     TYPE rslgno,       " initial = last entry was filtered out
           END OF ty_parent.
    DATA lt_parent TYPE HASHED TABLE OF ty_parent WITH UNIQUE KEY instance processid.
    DATA lv_msgid TYPE rslgno.
    DATA lv_text TYPE string.

    LOOP AT it_entries INTO DATA(ls_entry).
      lv_text = condense( ls_entry-text ).

      " continuation line: attach it to the entry before it (same work process)
      IF lv_text CP '>*'.
        READ TABLE lt_parent INTO DATA(ls_parent)
             WITH TABLE KEY instance = ls_entry-instance processid = ls_entry-processid.
        IF sy-subrc = 0 AND ls_parent-msgid IS NOT INITIAL.
          READ TABLE mt_groups ASSIGNING FIELD-SYMBOL(<ls_group>)
               WITH TABLE KEY by_msgid COMPONENTS msgid = ls_parent-msgid.
          IF sy-subrc = 0.
            SHIFT lv_text LEFT DELETING LEADING '> '.
            lcl_util=>add_unique( EXPORTING iv_value = lv_text iv_max = 6 CHANGING ct_list = <ls_group>-details ).
          ENDIF.
        ENDIF.
        CONTINUE.
      ENDIF.

      " main entry: information messages only on request, user / client filter
      CLEAR lv_msgid.
      IF ( mv_include_info = abap_true OR ( ls_entry-monbew(1) <> 'W' AND ls_entry-monbew IS NOT INITIAL ) )
         AND ( mt_users IS INITIAL OR ls_entry-zuser IN mt_users )
         AND ( mt_clients IS INITIAL OR ls_entry-client IN mt_clients ).
        add_entry( ls_entry ).
        mv_entries = mv_entries + 1.
        lv_msgid = ls_entry-messageid.
      ENDIF.
      " remember the last entry of this work process (initial if it was filtered out,
      " so its continuation lines are dropped as well)
      READ TABLE lt_parent ASSIGNING FIELD-SYMBOL(<ls_parent>)
           WITH TABLE KEY instance = ls_entry-instance processid = ls_entry-processid.
      IF sy-subrc = 0.
        <ls_parent>-msgid = lv_msgid.
      ELSE.
        INSERT VALUE #( instance = ls_entry-instance processid = ls_entry-processid msgid = lv_msgid )
               INTO TABLE lt_parent.
      ENDIF.
    ENDLOOP.

    rate_groups( ).
  ENDMETHOD.

  METHOD rate_groups.
    LOOP AT mt_groups ASSIGNING FIELD-SYMBOL(<ls_group>).
      " explanation is needed for the rating and for every output - determine it only once
      <ls_group>-advice = get_advice( <ls_group> ).

      " severity: SM21 priority, +1 if frequent; normal events are only information
      DATA(lv_weight) = SWITCH i( <ls_group>-prio WHEN 'R' THEN 3 WHEN 'Y' THEN 2 WHEN 'G' THEN 1 ELSE 0 ).
      IF <ls_group>-advice-normal = abap_true.
        lv_weight = 0.
      ENDIF.
      IF <ls_group>-count >= 10 AND lv_weight > 0.
        lv_weight = lv_weight + 1.
      ENDIF.
      <ls_group>-severity = COND #( WHEN lv_weight >= 3 THEN `High`
                                    WHEN lv_weight = 2  THEN `Medium`
                                    WHEN lv_weight = 1  THEN `Low`
                                    ELSE `Info` ).
      <ls_group>-sort_key = lv_weight * 100000 + <ls_group>-count.
    ENDLOOP.

    " worst first; rank = position, used as anchor in the HTML
    SORT mt_groups BY sort_key DESCENDING msgid ASCENDING.
    LOOP AT mt_groups ASSIGNING <ls_group>.
      <ls_group>-rank = sy-tabix.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_entry.
    DATA(lv_ts) = |{ is_entry-zdate }{ is_entry-ztime }|.
    READ TABLE mt_groups ASSIGNING FIELD-SYMBOL(<ls_group>)
         WITH TABLE KEY by_msgid COMPONENTS msgid = is_entry-messageid.
    IF sy-subrc <> 0.
      APPEND VALUE #( msgid = is_entry-messageid prio = is_entry-monbew(1) ) TO mt_groups ASSIGNING <ls_group>.
    ENDIF.

    <ls_group>-count = <ls_group>-count + 1.
    IF <ls_group>-first_ts IS INITIAL OR lv_ts < <ls_group>-first_ts.
      <ls_group>-first_ts   = lv_ts.
      <ls_group>-first_seen = lcl_util=>fmt_ts( iv_date = is_entry-zdate iv_time = is_entry-ztime ).
    ENDIF.
    IF lv_ts > <ls_group>-last_ts.
      <ls_group>-last_ts    = lv_ts.
      <ls_group>-last_seen  = lcl_util=>fmt_ts( iv_date = is_entry-zdate iv_time = is_entry-ztime ).
      <ls_group>-last_datum = is_entry-zdate.
    ENDIF.
    lcl_util=>add_unique( EXPORTING iv_value = is_entry-zuser  iv_max = 10 CHANGING ct_list = <ls_group>-users ).
    lcl_util=>add_unique( EXPORTING iv_value = is_entry-tcode  iv_max = 10 CHANGING ct_list = <ls_group>-tcodes ).
    lcl_util=>add_unique( EXPORTING iv_value = is_entry-repna  iv_max = 10 CHANGING ct_list = <ls_group>-programs ).
    lcl_util=>add_unique( EXPORTING iv_value = is_entry-client iv_max = 10 CHANGING ct_list = <ls_group>-clients ).
    lcl_util=>add_unique( EXPORTING iv_value = is_entry-text   iv_max = 3  CHANGING ct_list = <ls_group>-examples ).
    IF is_entry-errno IS NOT INITIAL.
      lcl_util=>add_unique( EXPORTING iv_value = |{ is_entry-errno } { is_entry-errorname }| iv_max = 3
                            CHANGING  ct_list  = <ls_group>-os_errors ).
    ENDIF.
  ENDMETHOD.

  METHOD count_high.
    LOOP AT mt_groups TRANSPORTING NO FIELDS WHERE severity = `High`.
      rv_count = rv_count + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD cancel_message.
    " 'Transaction canceled 00 179 ( )' -> text of message 00 179 from T100
    DATA lv_class TYPE t100-arbgb.
    DATA lv_number TYPE t100-msgnr.
    LOOP AT is_group-examples INTO DATA(lv_text).
      FIND FIRST OCCURRENCE OF REGEX `canceled\s+(\S+)\s+(\d{3})` IN lv_text IGNORING CASE
           SUBMATCHES lv_class lv_number.
      IF sy-subrc = 0.
        SELECT SINGLE text FROM t100
          WHERE sprsl = @mv_langu AND arbgb = @lv_class AND msgnr = @lv_number
          INTO @DATA(lv_message).
        IF sy-subrc <> 0.
          SELECT SINGLE text FROM t100
            WHERE sprsl = 'E' AND arbgb = @lv_class AND msgnr = @lv_number
            INTO @lv_message.
        ENDIF.
        rv_text = |Message { lv_class } { lv_number }: { lv_message }|.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_advice.
    " plain-language knowledge base: by message ID and by typical words in the message text
    DATA(lv_text) = concat_lines_of( table = is_group-examples sep = ` ` ) && ` ` &&
                    concat_lines_of( table = is_group-details sep = ` ` ).

    IF is_group-msgid CP 'AB*'.
      rs_advice = VALUE #(
        category = `Program crash (short dump)`
        meaning  = `A program was stopped by a runtime error and a short dump was written. Each crash creates one ` &&
                   `entry here (runtime error) with a second line that names the short dump.`
        causes   = `See the explanation of the runtime error in section 1 'Short dumps' of this report.`
        user_do  = `Look at section 1 'Short dumps' - it explains the error in plain words and what you can do.`
        steps    = `Analyse the dump in ST22 (or section 1 of this report).`
        look_at  = `ST22` ).
    ELSEIF is_group-msgid CP 'BY*' OR lv_text CP '*database error*'.
      rs_advice = VALUE #(
        category = `Database error`
        meaning  = `The SAP system received an error from the database while a program was reading or writing ` &&
                   `data. The program usually stopped, often with a short dump DBIF_...`
        causes   = `Database or transaction log full; lost connection to the database (database restarted); a lock ` &&
                   `problem (deadlock); an invalid SQL statement in a program (often own native SQL).`
        user_do  = `If your transaction failed at that time, try it again in a few minutes. If it keeps failing, ` &&
                   `report it immediately - many users may be affected.`
        steps    = `Basis: read the database error number in the messages below. Check space and log in section 3 ` &&
                   `of this report and the database error log (DBACOCKPIT > Diagnostics). Developer: if the error ` &&
                   `always comes from the same program, check its SQL statement (dump in ST22).`
        look_at  = `DBACOCKPIT, DB02, ST22` ).
    ELSEIF ( lv_text CP '*started*' OR lv_text CP '*ready for operation*' OR lv_text CP '*initialization complete*'
             OR lv_text CP '*was created with*' OR lv_text CP '*established*' )
       AND NOT ( lv_text CP '*not*' OR lv_text CP '*fail*' OR lv_text CP '*error*' ).
      rs_advice = VALUE #(
        category = `Normal system event (start-up)`
        meaning  = `A part of the SAP system (e.g. a buffer, the web server, the gateway) started normally. ` &&
                   `This is written to the log every time the system is started.`
        causes   = `The system or one of its parts was started.`
        user_do  = `Nothing.`
        steps    = `Nothing to fix. Only check why the system was restarted if nobody planned it.`
        look_at  = `SM21`
        normal   = abap_true ).
    ELSEIF is_group-msgid = 'D01' OR lv_text CP '*transaction canceled*'.
      rs_advice = VALUE #(
        category = `Transaction stopped with an error message`
        meaning  = `A program stopped a transaction with a termination message (message type A). The user saw ` &&
                   `the message and the transaction was cancelled; data entered in it was not saved.`
        causes   = `Missing or wrong data or customizing for the transaction; a missing authorization; a ` &&
                   `program error.`
        user_do  = `Read the message shown below (message class and number). It usually says what is missing - ` &&
                   `correct the data or ask your key user, then enter the data again.`
        steps    = `Look up the message in SE91 and use its where-used list to find the program that sends it; ` &&
                   `check the data and customizing it complains about.`
        look_at  = `SE91, SM21` ).
    ELSEIF is_group-msgid CP 'EB*' OR is_group-msgid CP 'EC*' OR lv_text CP '*batch*' OR lv_text CP '* job *'.
      rs_advice = VALUE #(
        category = `Background job problem`
        meaning  = `The job scheduler could not start or run a background job, so the work of that job was not done.`
        causes   = `The planned start time was too far in the past (e.g. the system was down at that time); the ` &&
                   `program, variant or user of the job does not exist or is locked; no free background work process.`
        user_do  = `If it is one of your jobs, check it in SM37 and schedule it again if needed.`
        steps    = `Basis: check the job and its log in SM37. For SAP standard jobs (names SAP_...) check SM36 > ` &&
                   `Standard Jobs. Make sure enough background work processes exist (SM50).`
        look_at  = `SM37, SM36` ).
    ELSEIF lv_text CP '*profile parameter*'.
      rs_advice = VALUE #(
        category = `Configuration error (profile parameter)`
        meaning  = `A setting in the SAP system profile has a value that is not allowed. The system ignores it ` &&
                   `and uses the default value, so the setting that was intended is NOT active.`
        causes   = `A typo or a value in the wrong format in the profile (e.g. 'ON' instead of 'on'), often after ` &&
                   `a manual profile change.`
        user_do  = `Nothing - this is for the Basis team.`
        steps    = `Basis: correct the parameter in the profile (RZ10, or the profile file on the server). The valid ` &&
                   `values are shown in the messages below; RZ11 shows the documentation of the parameter. Restart ` &&
                   `the instance if the parameter cannot be changed while the system is running.`
        look_at  = `RZ10, RZ11` ).
    ELSEIF is_group-msgid CP 'GC*' OR lv_text CP '*profile*modified*'.
      rs_advice = VALUE #(
        category = `System profile changed`
        meaning  = `The system noticed that its profile (its configuration file) was changed.`
        causes   = `A Basis administrator changed system settings.`
        user_do  = `Nothing.`
        steps    = `Basis: confirm that the change was intended and documented.`
        look_at  = `RZ10` ).
    ELSEIF is_group-msgid CP 'IM*'.
      rs_advice = VALUE #(
        category = `Web server (ICM) problem`
        meaning  = `The Internet Communication Manager - the built-in web server used by Fiori, Web GUI, web ` &&
                   `services and Eclipse ADT - reported a problem, e.g. a network port could not be opened.`
        causes   = `Another program already uses the port; the same port is configured twice; missing permission ` &&
                   `on the server.`
        user_do  = `If web applications (browser, Fiori, Eclipse) work normally, this does not affect you.`
        steps    = `Basis: open SMICM > Goto > Services to see which ports are active. Check the icm/server_port_* ` &&
                   `parameters (RZ11) and which process uses the port on the server (netstat).`
        look_at  = `SMICM, RZ11` ).
    ELSEIF lv_text CP '*bind failed*' OR is_group-os_errors IS NOT INITIAL.
      rs_advice = VALUE #(
        category = `Operating system error`
        meaning  = `A call to the operating system failed, for example opening a network port or a file.`
        causes   = `Port already in use (error 98 / EADDRINUSE), missing file or permission, resource limits.`
        user_do  = `Nothing - this is for the Basis team.`
        steps    = `Basis: use the operating system error below to find the cause; check the developer traces ` &&
                   `(ST11) of the process at that time.`
        look_at  = `ST11, SM21` ).
    ELSEIF lv_text CP '*Workp*'.
      rs_advice = VALUE #(
        category = `Work process restarted`
        meaning  = `An SAP work process (one of the worker programs that run user requests) was stopped and ` &&
                   `started again.`
        causes   = `Normal housekeeping (e.g. after reaching a memory limit) or a serious error in a program. ` &&
                   `Frequent restarts point to a problem.`
        user_do  = `Nothing, unless your transaction broke off at that time - then repeat it.`
        steps    = `Basis: occasional restarts are normal. If they are frequent, check the developer traces (ST11, ` &&
                   `files dev_w*) and short dumps at the same time.`
        look_at  = `SM50, ST11` ).
    ELSEIF is_group-msgid CP 'R4*' OR lv_text CP '*communication*' OR lv_text CP '*RFC*' OR lv_text CP '*gateway*'.
      rs_advice = VALUE #(
        category = `Connection / RFC problem`
        meaning  = `A connection to another program or system (RFC, gateway) failed or was interrupted.`
        causes   = `The other system is down or unreachable; wrong RFC destination; network problem; timeout.`
        user_do  = `If a function that talks to another system failed, try again later and report it if it keeps ` &&
                   `failing.`
        steps    = `Basis: test the RFC destinations in SM59, check the gateway (SMGW) and the target system.`
        look_at  = `SM59, SMGW` ).
    ELSEIF lv_text CP '*logon*' OR lv_text CP '*password*' OR lv_text CP '*locked*'.
      rs_advice = VALUE #(
        category = `Logon / user problem`
        meaning  = `A logon failed or a user was locked.`
        causes   = `Wrong or expired password, locked user, or an interface that still uses an old password.`
        user_do  = `If it was you: check your password or ask for an unlock / reset.`
        steps    = `Security / Basis: check the user in SU01 and the security audit log (SM20). Many failed logons ` &&
                   `of one user can mean an interface with an old password - or an attack.`
        look_at  = `SU01, SM20` ).
    ELSEIF lv_text CP '*buffer*' AND ( lv_text CP '*full*' OR lv_text CP '*displac*' OR lv_text CP '*overflow*' ).
      rs_advice = VALUE #(
        category = `Memory buffer too small`
        meaning  = `A table or program buffer in memory is full. Data is pushed out and must be read again from ` &&
                   `the database, which makes the system slower.`
        causes   = `Buffer size too small for the current use of the system.`
        user_do  = `Nothing - you may notice slower response times.`
        steps    = `Basis: check the buffer quality and swaps in ST02 and increase the buffer size parameter if needed.`
        look_at  = `ST02` ).
    ELSEIF lv_text CP '*timeout*'.
      rs_advice = VALUE #(
        category = `Session timeout`
        meaning  = `A user, HTTP or RFC session was closed because it was not used for too long.`
        causes   = `A session was left open; normal behaviour.`
        user_do  = `Log on again if your session was closed.`
        steps    = `Nothing, unless it often hits users who are working - then check the timeout parameters in RZ11.`
        look_at  = `RZ11` ).
    ELSE.
      rs_advice = VALUE #(
        category = `System message`
        meaning  = `The system wrote this message to its log. SAP's explanation is shown below where available.`
        causes   = `See SAP's explanation and the messages below.`
        user_do  = `Usually nothing - this is mainly for the Basis team. If your work was affected at that time, ` &&
                   `report it with the exact time.`
        steps    = `Basis: double-click the entry in SM21 for all details; search SAP Notes for the message ID and ` &&
                   `the message text.`
        look_at  = `SM21` ).
    ENDIF.
  ENDMETHOD.

  METHOD lif_section~summary_html.
    IF mv_error IS NOT INITIAL.
      rv_html = `<a href="#slog">2. System log</a>: could not be read - see below.`.
    ELSE.
      rv_html = |<a href="#slog">2. System log</a>: <b>{ lines( mt_groups ) }</b> kind(s) of messages, | &&
                |<b>{ count_high( ) }</b> rated high.|.
    ENDIF.
  ENDMETHOD.

  METHOD lif_section~get_html.
    " section heading, overview table (one row per message ID), then one card per message ID
    DATA lv_status TYPE string.
    DATA lv_scls TYPE string.

    APPEND `<h2 class="sec" id="slog">2. System log (SM21)</h2>` TO rt_html.
    APPEND `<div class="box help">The <i>system log</i> records important technical events of the SAP system: ` &&
           `errors, program crashes, restarts and configuration problems. Entries of the same kind are grouped ` &&
           `and explained once; follow-up lines that belong to an entry are shown with it.</div>` TO rt_html.
    IF mv_error IS NOT INITIAL.
      APPEND |<div class="box warnbox">{ lcl_util=>h( mv_error ) }</div>| TO rt_html.
      RETURN.
    ENDIF.
    IF mt_groups IS INITIAL.
      APPEND `<div class="box ok">No warnings or errors in the system log for this period.</div>` TO rt_html.
      RETURN.
    ENDIF.

    APPEND |<p><b>{ mv_entries }</b> log entries of <b>{ lines( mt_groups ) }</b> different kinds | &&
           |(<b>{ count_high( ) }</b> rated high).| &&
           |{ COND string( WHEN mv_include_info = abap_false THEN ` Information messages are hidden.` ) }</p>| TO rt_html.

    APPEND `<table><tr><th>#</th><th>Severity</th><th>What happened</th><th>Message ID</th><th>Times</th>` &&
           `<th>Last seen</th><th>Example</th></tr>` TO rt_html.
    LOOP AT mt_groups INTO DATA(ls_group).
      DATA(ls_adv) = ls_group-advice.
      DATA(lv_example) = VALUE string( ls_group-examples[ 1 ] OPTIONAL ).
      APPEND |<tr><td><a href="#s{ ls_group-rank }">{ ls_group-rank }</a></td>| &&
             |<td><span class="badge { ls_group-severity }">{ ls_group-severity }</span></td>| &&
             |<td>{ lcl_util=>h( ls_adv-category ) }</td><td>{ ls_group-msgid }</td><td>{ ls_group-count }</td>| &&
             |<td>{ lcl_util=>h( ls_group-last_seen ) }</td><td>{ lcl_util=>h( lv_example ) }</td></tr>| TO rt_html.
    ENDLOOP.
    APPEND `</table>` TO rt_html.

    LOOP AT mt_groups INTO ls_group.
      ls_adv = ls_group-advice.
      " SAP's own documentation of the message (document class SL = system log)
      DATA(lv_doc) = lcl_util=>docu_html( iv_id = 'SL' iv_object = ls_group-msgid iv_langu = mv_langu ).
      DATA(lv_cancel) = cancel_message( ls_group ).
      lcl_util=>age_status( EXPORTING iv_date = ls_group-last_datum IMPORTING ev_text = lv_status ev_class = lv_scls ).
      DATA(lv_meaning) = lcl_util=>h( ls_adv-meaning ).
      IF lv_cancel IS NOT INITIAL.
        lv_meaning = |{ lv_meaning }<br><b>{ lcl_util=>h( lv_cancel ) }</b>|.
      ENDIF.

      APPEND |<div class="card" id="s{ ls_group-rank }">| TO rt_html.
      APPEND |<h2>{ ls_group-rank }. { lcl_util=>h( ls_adv-category ) } <span class="badge { ls_group-severity }">{ ls_group-severity }</span></h2>| TO rt_html.
      APPEND |<div class="status { lv_scls }">{ lcl_util=>h( lv_status ) }</div>| TO rt_html.
      APPEND `<table>` TO rt_html.
      APPEND |<tr><td class="k">What it means</td><td>{ lv_meaning }</td></tr>| TO rt_html.
      IF lv_doc IS NOT INITIAL.
        APPEND |<tr><td class="k">SAP's explanation</td><td>{ lv_doc }</td></tr>| TO rt_html.
      ENDIF.
      APPEND |<tr><td class="k">Message(s)</td><td>{ lcl_util=>join_h( it_list = ls_group-examples iv_sep = `<br>` ) }</td></tr>| TO rt_html.
      IF ls_group-details IS NOT INITIAL.
        APPEND |<tr><td class="k">Details</td><td>{ lcl_util=>join_h( it_list = ls_group-details iv_sep = `<br>` ) }</td></tr>| TO rt_html.
      ENDIF.
      IF ls_group-os_errors IS NOT INITIAL.
        APPEND |<tr><td class="k">Operating system error</td><td>{ lcl_util=>join_h( ls_group-os_errors ) }</td></tr>| TO rt_html.
      ENDIF.
      APPEND |<tr><td class="k">How often</td><td><b>{ ls_group-count } time(s)</b>, | &&
             |first { lcl_util=>h( ls_group-first_seen ) }, last { lcl_util=>h( ls_group-last_seen ) }</td></tr>| TO rt_html.
      DATA(lv_where) = VALUE string( ).
      IF ls_group-users IS NOT INITIAL.
        lv_where = |User(s): { lcl_util=>join_h( ls_group-users ) }<br>|.
      ENDIF.
      IF ls_group-tcodes IS NOT INITIAL.
        lv_where = |{ lv_where }Transaction(s): { lcl_util=>join_h( ls_group-tcodes ) }<br>|.
      ENDIF.
      IF ls_group-programs IS NOT INITIAL.
        lv_where = |{ lv_where }Program(s): { lcl_util=>join_h( ls_group-programs ) }<br>|.
      ENDIF.
      IF ls_group-clients IS NOT INITIAL.
        lv_where = |{ lv_where }Client(s): { lcl_util=>join_h( ls_group-clients ) }|.
      ENDIF.
      IF lv_where IS NOT INITIAL.
        APPEND |<tr><td class="k">Who / where</td><td>{ lv_where }</td></tr>| TO rt_html.
      ENDIF.
      APPEND |<tr><td class="k">Typical causes</td><td>{ lcl_util=>h( ls_adv-causes ) }</td></tr>| TO rt_html.
      DATA(lv_prio) = SWITCH string( ls_group-prio WHEN 'R' THEN `very high` WHEN 'Y' THEN `high`
                                                   WHEN 'G' THEN `warning` ELSE `information` ).
      APPEND |<tr><td class="k">Technical details</td><td>Message ID { ls_group-msgid } &middot; SM21 priority { lv_prio }</td></tr>| TO rt_html.
      APPEND `</table>` TO rt_html.
      APPEND |<div class="box user"><b>What you can do now</b><br>{ lcl_util=>h( ls_adv-user_do ) }</div>| TO rt_html.
      APPEND |<div class="box tip"><b>How to fix it (Basis / developer)</b><br>{ lcl_util=>h( ls_adv-steps ) }</div>| TO rt_html.
      APPEND |<div class="sub">Where to look: { lcl_util=>h( ls_adv-look_at ) } &middot; in SM21 filter | &&
             |on message ID { ls_group-msgid }, last { lcl_util=>h( ls_group-last_seen ) }.</div></div>| TO rt_html.
    ENDLOOP.
  ENDMETHOD.

  METHOD lif_section~write_list.
    DATA lv_text TYPE string.
    WRITE / `System log (SM21)`.
    ULINE.
    IF mv_error IS NOT INITIAL.
      WRITE / mv_error.
      RETURN.
    ENDIF.
    lv_text = |{ mv_entries } entries, { lines( mt_groups ) } different kinds|.
    WRITE / lv_text.
    LOOP AT mt_groups INTO DATA(ls_group).
      DATA(ls_adv) = ls_group-advice.
      lv_text = |{ ls_group-rank }. [{ ls_group-severity }] { ls_adv-category } - message { ls_group-msgid }, | &&
                |{ ls_group-count } time(s), last { ls_group-last_seen }|.
      WRITE / lv_text.
      lv_text = |   Message: { VALUE string( ls_group-examples[ 1 ] OPTIONAL ) }|.
      WRITE / lv_text.
      lv_text = |   User can: { ls_adv-user_do }|.
      WRITE / lv_text.
      lv_text = |   Fix: { ls_adv-steps }|.
      WRITE / lv_text.
      SKIP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_dbcheck - section 3: database (DB02), SAP ASE (Sybase) only
*   Reads space and log usage of every database and the largest tables
*   with read-only native SQL on the ASE catalog, then turns the numbers
*   into findings (full data space, full log, no log backups, ...).
*----------------------------------------------------------------------*
CLASS lcl_dbcheck DEFINITION FINAL FRIENDS ltc_dbcheck.
  PUBLIC SECTION.
    INTERFACES lif_section.

    TYPES:
      "! Space of one database (columns in the order of the SELECT in read_space)
      BEGIN OF ty_db,
        name      TYPE c LENGTH 30,
        data_mb   TYPE i,
        data_free TYPE i,
        log_mb    TYPE i,
        log_free  TYPE i,
        mixed     TYPE i,     " 1 = log and data on the same device
        offline   TYPE i,
        trunc     TYPE i,     " 1 = 'trunc log on chkpt' (no log backups)
        dump_date TYPE c LENGTH 8,
        dump_time TYPE c LENGTH 8,
      END OF ty_db,
      tt_db TYPE STANDARD TABLE OF ty_db WITH EMPTY KEY,

      "! One of the largest tables (columns in the order of the SELECT in read_tables)
      BEGIN OF ty_table,
        name     TYPE c LENGTH 30,
        rows     TYPE p LENGTH 10 DECIMALS 0,
        data_mb  TYPE i,
        total_mb TYPE i,     " data + indexes
      END OF ty_table,
      tt_table TYPE STANDARD TABLE OF ty_table WITH EMPTY KEY,

      "! One problem found in the database figures, explained in plain language
      BEGIN OF ty_finding,
        severity TYPE string,
        weight   TYPE i,     " 3 = High, 2 = Medium, 1 = Low (for sorting)
        title    TYPE string,
        meaning  TYPE string,
        causes   TYPE string,
        user_do  TYPE string,
        steps    TYPE string,
        look_at  TYPE string,
      END OF ty_finding,
      tt_finding TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

  PRIVATE SECTION.
    " ASE pages -> MB, and SAP's 'database is online' check (same as DBA Cockpit)
    CONSTANTS c_mb TYPE string VALUE `convert(float, @@maxpagesize) / 1048576`.
    CONSTANTS c_online TYPE string
      VALUE `((d.status & 32) + (d.status & 64) + (d.status & 256) + (d.status2 & 16) + (d.status2 & 32) + (d.status3 & 8) + (d.status3 & 4096))`.

    DATA mv_error TYPE string.
    DATA mt_findings TYPE tt_finding.
    DATA mt_db TYPE tt_db.
    DATA mt_tables TYPE tt_table.
    DATA mv_sapdb TYPE string.     " name of the SAP database (db_name() of our connection)

    "! Run a native SQL SELECT on the default connection into an internal table
    METHODS query
      IMPORTING iv_sql    TYPE string
                ir_result TYPE REF TO data
      RAISING   cx_sql_exception cx_parameter_invalid.
    "! Data and log space of every database (same calculation as DB02)
    METHODS read_space
      RAISING cx_sql_exception cx_parameter_invalid.
    "! The 10 largest tables of the SAP database
    METHODS read_tables
      RAISING cx_sql_exception cx_parameter_invalid.
    "! Turn the figures into findings, worst first
    METHODS evaluate.
    METHODS count_high
      RETURNING VALUE(rv_count) TYPE i.
    METHODS add_finding
      IMPORTING iv_weight  TYPE i
                iv_title   TYPE string
                iv_meaning TYPE string
                iv_causes  TYPE string
                iv_user_do TYPE string
                iv_steps   TYPE string
                iv_look_at TYPE string.
    "! What is this table, and can old data be cleaned up (ev_cleanup = X)?
    METHODS table_hint
      IMPORTING iv_name    TYPE csequence
      EXPORTING ev_text    TYPE string
                ev_cleanup TYPE abap_bool.
    "! Used space in percent
    METHODS pct
      IMPORTING iv_total      TYPE i
                iv_free       TYPE i
      RETURNING VALUE(rv_pct) TYPE i.
ENDCLASS.

CLASS lcl_dbcheck IMPLEMENTATION.

  METHOD lif_section~analyze.
    " the SQL uses ASE catalog tables and functions - other databases are not supported
    IF sy-dbsys(3) <> 'SYB'.
      mv_error = |The database checks are built for SAP ASE (Sybase). This system runs { sy-dbsys } - | &&
                 |please use transaction DB02 instead.|.
      RETURN.
    ENDIF.
    TRY.
        read_space( ).
        read_tables( ).
      CATCH cx_sql_exception INTO DATA(lx_sql).
        mv_error = |The database information could not be read: { lx_sql->get_text( ) } { lx_sql->sql_message }|.
        RETURN.
      CATCH cx_root INTO DATA(lx_root).
        mv_error = |The database information could not be read: { lx_root->get_text( ) }|.
        RETURN.
    ENDTRY.
    evaluate( ).
  ENDMETHOD.

  METHOD query.
    " read-only native SQL on the default connection
    DATA(lo_result) = cl_sql_connection=>get_connection( )->create_statement( )->execute_query( iv_sql ).
    lo_result->set_param_table( ir_result ).
    lo_result->next_package( ).
    lo_result->close( ).
  ENDMETHOD.

  METHOD read_space.
    TYPES: BEGIN OF ty_name,
             name TYPE c LENGTH 30,
           END OF ty_name.
    DATA lt_name TYPE STANDARD TABLE OF ty_name WITH EMPTY KEY.

    query( iv_sql = `select convert(varchar(30), db_name())` ir_result = REF #( lt_name ) ).
    READ TABLE lt_name INTO DATA(ls_name) INDEX 1.
    IF sy-subrc = 0.
      mv_sapdb = ls_name-name.
    ENDIF.

    " data and log space per database - same calculation as the DBA Cockpit (DB02)
    DATA(lv_sql) =
      `select convert(varchar(30), d.name), ` &&
      `convert(int, isnull((select sum(convert(numeric(20,0), u.size)) from master..sysusages u ` &&
      `where u.dbid = d.dbid and u.segmap not in (4,0)), 0) * ` && c_mb && `), ` &&
      `convert(int, isnull((select sum(convert(numeric(20,0), curunreservedpgs(u.dbid, u.lstart, u.unreservedpgs))) ` &&
      `from master..sysusages u where u.dbid = d.dbid and u.segmap not in (4,0)), 0) * ` && c_mb && `), ` &&
      `convert(int, (case when ` && c_online && ` = 0 then (case when d.status2 & -32768 != 0 ` &&
      `then lct_admin('num_logpages', d.dbid) + lct_admin('logsegment_freepages', d.dbid) ` &&
      `+ lct_admin('reserved_for_rollbacks', d.dbid) ` &&
      `else isnull((select sum(convert(numeric(20,0), u.size)) from master..sysusages u ` &&
      `where u.segmap & 4 = 4 and u.location not in (9,10) and u.dbid = d.dbid), 0) end) ` &&
      `else 0 end) * ` && c_mb && `), ` &&
      `convert(int, (case when ` && c_online && ` = 0 then lct_admin('logsegment_freepages', d.dbid) ` &&
      `- lct_admin('reserved_for_rollbacks', d.dbid) else 0 end) * ` && c_mb && `), ` &&
      `case when d.status2 & -32768 != 0 then 1 else 0 end, ` &&
      `case when ` && c_online && ` = 0 then 0 else 1 end, ` &&
      `case when d.status & 8 = 8 then 1 else 0 end, ` &&
      `isnull(convert(char(8), d.dumptrdate, 112), ''), ` &&
      `isnull(convert(char(8), d.dumptrdate, 108), '') ` &&
      `from master..sysdatabases d order by d.name`.
    query( iv_sql = lv_sql ir_result = REF #( mt_db ) ).
  ENDMETHOD.

  METHOD read_tables.
    " 10 largest tables of the SAP database (data + indexes), from the table statistics (systabstats):
    " takes seconds, while measuring every table with reserved_pages( ) takes about a minute
    DATA(lv_sql) =
      `select top 10 convert(varchar(30), o.name), ` &&
      `convert(numeric(20,0), max(case when s.indid in (0,1) then s.rowcnt else 0 end)), ` &&
      `convert(int, sum(case when s.indid in (0,1) then s.pagecnt else 0 end) * ` && c_mb && `), ` &&
      `convert(int, sum(convert(numeric(20,0), s.pagecnt) + s.leafcnt) * ` && c_mb && `) ` &&
      `from sysobjects o, systabstats s where o.type = 'U' and s.id = o.id ` &&
      `group by o.name order by sum(convert(numeric(20,0), s.pagecnt) + s.leafcnt) desc`.
    query( iv_sql = lv_sql ir_result = REF #( mt_tables ) ).
  ENDMETHOD.

  METHOD pct.
    IF iv_total > 0.
      rv_pct = ( iv_total - iv_free ) * 100 / iv_total.
    ENDIF.
  ENDMETHOD.

  METHOD add_finding.
    APPEND VALUE #( weight   = iv_weight
                    severity = COND #( WHEN iv_weight >= 3 THEN `High` WHEN iv_weight = 2 THEN `Medium` ELSE `Low` )
                    title    = iv_title
                    meaning  = iv_meaning
                    causes   = iv_causes
                    user_do  = iv_user_do
                    steps    = iv_steps
                    look_at  = iv_look_at ) TO mt_findings.
  ENDMETHOD.

  METHOD evaluate.
    DATA lv_name TYPE string.
    DATA lv_date TYPE d.
    DATA lv_days TYPE i.
    DATA lv_hint TYPE string.
    DATA lv_cleanup TYPE abap_bool.

    LOOP AT mt_db INTO DATA(ls_db).
      lv_name = ls_db-name.
      " only the SAP database, the SAP tools database and the temporary databases are judged
      DATA(lv_temp) = xsdbool( lv_name CP '*temp*' ).
      IF lv_name <> mv_sapdb AND lv_name <> `saptools` AND lv_temp = abap_false.
        CONTINUE.
      ENDIF.

      IF ls_db-offline = 1.
        add_finding(
          iv_weight  = 3
          iv_title   = |Database { lv_name } is not available|
          iv_meaning = `The database is offline, being recovered or marked as damaged. Programs that need it fail.`
          iv_causes  = `Database shutdown or recovery in progress; a damaged (suspect) database; a full log during ` &&
                       `recovery.`
          iv_user_do = `Report it immediately.`
          iv_steps   = `Basis: check the database status and the ASE error log (DBACOCKPIT > Diagnostics).`
          iv_look_at = `DBACOCKPIT` ).
        CONTINUE.
      ENDIF.

      DATA(lv_data_pct) = pct( iv_total = ls_db-data_mb iv_free = ls_db-data_free ).
      IF lv_data_pct >= 85.
        DATA(lv_weight) = COND i( WHEN lv_data_pct >= 95 THEN 3 ELSE 2 ).
        IF lv_temp = abap_true.
          add_finding(
            iv_weight  = lv_weight
            iv_title   = |Temporary database { lv_name }: { lv_data_pct }% used|
            iv_meaning = `This database holds temporary data, e.g. for sorting large results. If it runs full, ` &&
                         `big queries and reports fail.`
            iv_causes  = `A very large query or report running right now; temporary database too small.`
            iv_user_do = `If a big report fails, try it with a smaller selection.`
            iv_steps   = `Basis: find the long-running statement (DBACOCKPIT > Performance) and increase the ` &&
                         `temporary database if this happens regularly.`
            iv_look_at = `DBACOCKPIT, DB02` ).
        ELSE.
          add_finding(
            iv_weight  = lv_weight
            iv_title   = |Database { lv_name }: data space { lv_data_pct }% used|
            iv_meaning = |Only { ls_db-data_free NUMBER = USER } MB of { ls_db-data_mb NUMBER = USER } MB are free. | &&
                         |When the data space is full, every program that saves data fails (short dumps | &&
                         |DBIF_RSQL_SQL_ERROR, database errors in the system log) and the system can stop.|
            iv_causes  = `Normal growth, large data loads, or old data that is never deleted (see the largest ` &&
                         `tables below).`
            iv_user_do = `Nothing to do yourself - make sure the Basis team knows.`
            iv_steps   = `Basis: add space (DBACOCKPIT > Space: extend a device, add a device, or switch on ` &&
                         `automatic expansion). Clean up tables with old data (see 'Largest tables'). Watch the ` &&
                         `growth over time in DB02.`
            iv_look_at = `DB02, DBACOCKPIT` ).
        ENDIF.
      ENDIF.

      IF ls_db-mixed = 0 AND ls_db-log_mb > 0.
        DATA(lv_log_pct) = pct( iv_total = ls_db-log_mb iv_free = ls_db-log_free ).
        IF lv_log_pct >= 70.
          lv_weight = COND i( WHEN lv_log_pct >= 90 THEN 3 ELSE 2 ).
          add_finding(
            iv_weight  = lv_weight
            iv_title   = |Database { lv_name }: transaction log { lv_log_pct }% used|
            iv_meaning = `The transaction log records every change. If it becomes full, nobody can save anything ` &&
                         `any more - the system stands still until space is freed.`
            iv_causes  = `No transaction log backups (the log is only freed by a backup or truncation); a long ` &&
                         `running open transaction that holds the log; a very large mass change.`
            iv_user_do = `If saving fails for everyone, report it immediately.`
            iv_steps   = `Basis: back up (dump) the transaction log, or find the oldest open transaction ` &&
                         `(master..syslogshold, DBACOCKPIT) and end it; extend the log device if it is regularly ` &&
                         `too small.`
            iv_look_at = `DBACOCKPIT, DB02` ).
        ENDIF.
      ENDIF.

      IF lv_name = mv_sapdb.
        IF ls_db-mixed = 1.
          add_finding(
            iv_weight  = 1
            iv_title   = |Database { lv_name }: log and data share the same device|
            iv_meaning = `The transaction log is not on a device of its own. Data and log then compete for the ` &&
                         `same space, and a restore to a point in time is limited.`
            iv_causes  = `Installation default or a later extension of the log onto a data device.`
            iv_user_do = `Nothing.`
            iv_steps   = `Basis: SAP recommends a separate log device for the SAP database (ALTER DATABASE ... ` &&
                         `LOG ON ...). Plan this change carefully.`
            iv_look_at = `DBACOCKPIT > Space` ).
        ENDIF.
        IF ls_db-trunc = 1.
          add_finding(
            iv_weight  = 1
            iv_title   = |Database { lv_name }: transaction log is cleared automatically (no log backups)|
            iv_meaning = `The option 'trunc log on chkpt' is set: the log is emptied automatically. This prevents a ` &&
                         `full log, but after a crash only the last full backup can be restored - all changes ` &&
                         `since then are lost.`
            iv_causes  = `Typical for test and sandbox systems.`
            iv_user_do = `Nothing.`
            iv_steps   = `Fine for test systems. For production: switch the option off and schedule regular ` &&
                         `transaction log backups (DBACOCKPIT > Jobs > DBA Planning Calendar).`
            iv_look_at = `DBACOCKPIT > Jobs` ).
        ELSE.
          lv_date = ls_db-dump_date.
          IF lv_date IS INITIAL OR ls_db-dump_date CN '0123456789'.
            add_finding(
              iv_weight  = 2
              iv_title   = |Database { lv_name }: transaction log has never been backed up|
              iv_meaning = `Without regular log backups the log keeps growing until it is full (then nobody can ` &&
                           `save), and a restore to a recent point in time is not possible.`
              iv_causes  = `Backup job not scheduled or failing.`
              iv_user_do = `Nothing - make sure the Basis team knows.`
              iv_steps   = `Basis: schedule transaction log backups in the DBA Planning Calendar (DBACOCKPIT > Jobs) ` &&
                           `and check their logs.`
              iv_look_at = `DBACOCKPIT > Jobs` ).
          ELSE.
            lv_days = sy-datum - lv_date.
            IF lv_days >= 1.
              add_finding(
                iv_weight  = COND #( WHEN lv_days >= 7 THEN 3 ELSE 2 )
                iv_title   = |Database { lv_name }: no transaction log backup since { lv_date DATE = USER }|
                iv_meaning = |The last transaction log backup is { lv_days } day(s) old. The log keeps growing until | &&
                             |it is backed up, and changes since then cannot be restored after a crash.|
                iv_causes  = `Backup job not scheduled, failing, or the backup device is full.`
                iv_user_do = `Nothing - make sure the Basis team knows.`
                iv_steps   = `Basis: check the backup jobs and their logs (DBACOCKPIT > Jobs) and run a log backup now.`
                iv_look_at = `DBACOCKPIT > Jobs` ).
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " large tables that hold old data which could be cleaned up
    LOOP AT mt_tables INTO DATA(ls_table).
      table_hint( EXPORTING iv_name = ls_table-name IMPORTING ev_text = lv_hint ev_cleanup = lv_cleanup ).
      IF lv_cleanup = abap_true AND ls_table-total_mb >= 500.
        add_finding(
          iv_weight  = 1
          iv_title   = |Table { ls_table-name } uses { ls_table-total_mb NUMBER = USER } MB|
          iv_meaning = lv_hint
          iv_causes  = `Old data is kept because no regular clean-up job runs.`
          iv_user_do = `Nothing.`
          iv_steps   = `Basis: run the clean-up mentioned above as a regular job (SM36 > Standard Jobs for the ` &&
                       `SAP_REORG_* jobs).`
          iv_look_at = `SM36, DB02` ).
      ENDIF.
    ENDLOOP.

    SORT mt_findings BY weight DESCENDING.
  ENDMETHOD.

  METHOD table_hint.
    " what is this table, and can old data be cleaned up?
    DATA lv_name TYPE string.
    lv_name = iv_name.
    CLEAR: ev_text, ev_cleanup.
    ev_cleanup = abap_true.
    IF lv_name = 'SNAP'.
      ev_text = `Short dumps (ST22). Old dumps are deleted by program RSSNAPDL (standard job SAP_REORG_ABAPDUMPS).`.
    ELSEIF lv_name = 'TST03'.
      ev_text = `Spool data (print output). Old spool requests are deleted by RSPO1041 (standard job SAP_REORG_SPOOL).`.
    ELSEIF lv_name = 'DBTABLOG'.
      ev_text = `Change log of customizing tables (table logging). Old entries can be deleted with RSTBPDEL.`.
    ELSEIF lv_name = 'BALDAT' OR lv_name = 'BALHDR'.
      ev_text = `Application logs (SLG1). Expired logs are deleted with transaction SLG2 (program SBAL_DELETE).`.
    ELSEIF lv_name = 'APQD' OR lv_name = 'APQI'.
      ev_text = `Batch input sessions (SM35). Processed sessions are deleted by RSBDCREO (job SAP_REORG_BATCHINPUT).`.
    ELSEIF lv_name CP 'TBTC*'.
      ev_text = `Background job administration (SM37). Old jobs are deleted by RSBTCDEL2 (standard job SAP_REORG_JOBS).`.
    ELSEIF lv_name = 'SOC3' OR lv_name = 'SOOD' OR lv_name = 'SOOS' OR lv_name = 'SOFFCONT1'.
      ev_text = `SAPoffice / Business Communication documents and mails (SOST). Old documents can be deleted with ` &&
                `RSBCS_REORG.`.
    ELSEIF lv_name CP 'EDI40' OR lv_name = 'EDIDS' OR lv_name = 'EDIDC'.
      ev_text = `IDocs (WE02). Old IDocs can be archived with archiving object IDOC (SARA).`.
    ELSEIF lv_name = 'CDCLS' OR lv_name = 'CDHDR' OR lv_name = 'CDPOS'.
      ev_text = `Change documents. Old ones can be archived with archiving object CHANGEDOCU (SARA).`.
    ELSEIF lv_name CP 'SWW*' OR lv_name CP 'SWWLOG*'.
      ev_text = `Workflow work items (SWI1). Completed work items can be archived with archiving object WORKITEM (SARA).`.
    ELSEIF lv_name CP 'RSDDSTAT*'.
      ev_text = `BW query and load statistics. Old statistics are deleted with RSDDSTAT_DATA_DELETE.`.
    ELSEIF lv_name CP 'ARFC*' OR lv_name CP 'TRFC*' OR lv_name CP 'QRFC*'.
      ev_text = `RFC queues (SM58 / SMQ1). A large size means stuck or old RFC calls - check and clean them up there.`.
    ELSE.
      ev_cleanup = abap_false.
      IF lv_name CP '/BI0/*' OR lv_name CP '/BIC/*'.
        ev_text = `BW data (InfoProvider table). Its size depends on the loaded data; reduce it by deleting old ` &&
                  `requests, compression or archiving.`.
      ELSEIF lv_name CP 'REPO*' OR lv_name CP 'DOK*' OR lv_name CP 'WBCROSS*' OR lv_name = 'E071'
          OR lv_name = 'SMIMCONT1' OR lv_name CP 'D010*' OR lv_name CP 'DD0*' OR lv_name = 'TADIR'.
        ev_text = `SAP system table (programs, documentation, repository, transports). A large size is normal - ` &&
                  `no action needed.`.
      ELSEIF lv_name CP 'Z*' OR lv_name CP 'Y*'.
        ev_text = `Own (customer) table. Ask its owner whether old data can be deleted or archived.`.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD count_high.
    LOOP AT mt_findings TRANSPORTING NO FIELDS WHERE severity = `High`.
      rv_count = rv_count + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD lif_section~summary_html.
    IF mv_error IS NOT INITIAL.
      rv_html = `<a href="#db">3. Database</a>: could not be checked - see below.`.
    ELSE.
      rv_html = |<a href="#db">3. Database</a>: <b>{ lines( mt_findings ) }</b> finding(s), | &&
                |<b>{ count_high( ) }</b> rated high.|.
    ENDIF.
  ENDMETHOD.

  METHOD lif_section~get_html.
    " findings first (what to do), then the figures: space per database and largest tables
    DATA lv_name TYPE string.
    DATA lv_date TYPE d.
    DATA lv_time TYPE t.
    DATA lv_hint TYPE string.
    DATA lv_cleanup TYPE abap_bool.

    APPEND `<h2 class="sec" id="db">3. Database (DB02)</h2>` TO rt_html.
    APPEND `<div class="box help">The database stores all data of the SAP system. Two areas must never run full: ` &&
           `the <b>data space</b> (where the tables are) and the <b>transaction log</b> (where every change is ` &&
           `written first). This section checks both, the log backups and the largest tables - like DB02 / ` &&
           `DBACOCKPIT.</div>` TO rt_html.
    IF mv_error IS NOT INITIAL.
      APPEND |<div class="box warnbox">{ lcl_util=>h( mv_error ) }</div>| TO rt_html.
      RETURN.
    ENDIF.

    IF mt_findings IS INITIAL.
      APPEND `<div class="box ok">No database problems found.</div>` TO rt_html.
    ELSE.
      APPEND |<p><b>{ lines( mt_findings ) }</b> finding(s), <b>{ count_high( ) }</b> rated high.</p>| TO rt_html.
      LOOP AT mt_findings INTO DATA(ls_finding).
        DATA(lv_idx) = sy-tabix.
        APPEND |<div class="card" id="d{ lv_idx }">| TO rt_html.
        APPEND |<h2>{ lv_idx }. { lcl_util=>h( ls_finding-title ) } <span class="badge { ls_finding-severity }">{ ls_finding-severity }</span></h2>| TO rt_html.
        APPEND `<table>` TO rt_html.
        APPEND |<tr><td class="k">What it means</td><td>{ lcl_util=>h( ls_finding-meaning ) }</td></tr>| TO rt_html.
        APPEND |<tr><td class="k">Typical causes</td><td>{ lcl_util=>h( ls_finding-causes ) }</td></tr>| TO rt_html.
        APPEND `</table>` TO rt_html.
        APPEND |<div class="box user"><b>What you can do now</b><br>{ lcl_util=>h( ls_finding-user_do ) }</div>| TO rt_html.
        APPEND |<div class="box tip"><b>How to fix it (Basis)</b><br>{ lcl_util=>h( ls_finding-steps ) }</div>| TO rt_html.
        APPEND |<div class="sub">Where to look: { lcl_util=>h( ls_finding-look_at ) }</div></div>| TO rt_html.
      ENDLOOP.
    ENDIF.

    " space per database
    APPEND `<h3>Space per database</h3><table><tr><th>Database</th><th>Size</th><th>Data used</th>` &&
           `<th>Log size</th><th>Log used</th><th>Last log backup</th><th>What it is</th></tr>` TO rt_html.
    LOOP AT mt_db INTO DATA(ls_db).
      lv_name = ls_db-name.
      DATA(lv_what) = COND string( WHEN lv_name = mv_sapdb        THEN `SAP data (main database)`
                                   WHEN lv_name = `saptools`      THEN `SAP tools database`
                                   WHEN lv_name CP '*temp*'       THEN `temporary data`
                                   ELSE `database system (internal)` ).
      IF ls_db-offline = 1.
        lv_what = |<b>OFFLINE</b> - { lv_what }|.
      ENDIF.
      DATA(lv_log) = COND string( WHEN ls_db-mixed = 1 THEN `shared with data`
                                  ELSE lcl_util=>bar( iv_pct  = pct( iv_total = ls_db-log_mb iv_free = ls_db-log_free )
                                                      iv_warn = 70 iv_crit = 90 ) ).
      IF ls_db-trunc = 1.
        DATA(lv_backup) = `cleared automatically`.
      ELSEIF ls_db-dump_date IS INITIAL OR ls_db-dump_date CN '0123456789'.
        lv_backup = `never`.
      ELSE.
        lv_date = ls_db-dump_date.
        REPLACE ALL OCCURRENCES OF ':' IN ls_db-dump_time WITH ''.
        lv_time = ls_db-dump_time.
        lv_backup = lcl_util=>fmt_ts( iv_date = lv_date iv_time = lv_time ).
      ENDIF.
      DATA(lv_data) = lcl_util=>bar( iv_pct  = pct( iv_total = ls_db-data_mb iv_free = ls_db-data_free )
                                     iv_warn = 85 iv_crit = 95 ).
      DATA(lv_log_size) = COND string( WHEN ls_db-mixed = 1 THEN `-` ELSE |{ ls_db-log_mb NUMBER = USER } MB| ).
      APPEND |<tr><td>{ lcl_util=>h( lv_name ) }</td><td>{ ls_db-data_mb NUMBER = USER } MB</td>| &&
             |<td>{ lv_data }</td><td>{ lv_log_size }</td>| &&
             |<td>{ lv_log }</td><td>{ lcl_util=>h( lv_backup ) }</td><td>{ lv_what }</td></tr>| TO rt_html.
    ENDLOOP.
    APPEND `</table>` TO rt_html.

    " largest tables
    READ TABLE mt_db INTO ls_db WITH KEY name = mv_sapdb.
    DATA(lv_db_mb) = COND i( WHEN sy-subrc = 0 THEN ls_db-data_mb ).
    APPEND |<h3>Largest tables in database { lcl_util=>h( mv_sapdb ) }</h3><table><tr><th>#</th><th>Table</th>| &&
           |<th>Rows</th><th>Size (with indexes)</th><th>Share</th><th>What it is / what to do</th></tr>| TO rt_html.
    APPEND `<div class="sub">Rows and sizes come from the database statistics, so they are approximate.</div>` TO rt_html.
    LOOP AT mt_tables INTO DATA(ls_table).
      table_hint( EXPORTING iv_name = ls_table-name IMPORTING ev_text = lv_hint ev_cleanup = lv_cleanup ).
      DATA(lv_share) = COND i( WHEN lv_db_mb > 0 THEN ls_table-total_mb * 100 / lv_db_mb ).
      APPEND |<tr><td>{ sy-tabix }</td><td>{ lcl_util=>h( ls_table-name ) }</td>| &&
             |<td>{ ls_table-rows NUMBER = USER }</td><td>{ ls_table-total_mb NUMBER = USER } MB</td>| &&
             |<td>{ lv_share }%</td><td>{ lcl_util=>h( lv_hint ) }</td></tr>| TO rt_html.
    ENDLOOP.
    APPEND `</table>` TO rt_html.
  ENDMETHOD.

  METHOD lif_section~write_list.
    DATA lv_text TYPE string.
    WRITE / `Database (DB02)`.
    ULINE.
    IF mv_error IS NOT INITIAL.
      WRITE / mv_error.
      RETURN.
    ENDIF.
    LOOP AT mt_db INTO DATA(ls_db).
      lv_text = |{ ls_db-name } - data { ls_db-data_mb } MB, { pct( iv_total = ls_db-data_mb iv_free = ls_db-data_free ) }% used|.
      IF ls_db-mixed = 0.
        lv_text = |{ lv_text }, log { ls_db-log_mb } MB, { pct( iv_total = ls_db-log_mb iv_free = ls_db-log_free ) }% used|.
      ENDIF.
      WRITE / lv_text.
    ENDLOOP.
    SKIP.
    IF mt_findings IS INITIAL.
      WRITE / `No database problems found.`.
    ENDIF.
    LOOP AT mt_findings INTO DATA(ls_finding).
      lv_text = |{ sy-tabix }. [{ ls_finding-severity }] { ls_finding-title }|.
      WRITE / lv_text.
      lv_text = |   Meaning: { ls_finding-meaning }|.
      WRITE / lv_text.
      lv_text = |   Fix: { ls_finding-steps }|.
      WRITE / lv_text.
      SKIP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_dump_section - section 1: short dumps (ST22)
*   Reads the dump headers of the period, groups identical dumps into
*   problems and explains each problem in plain language.
*----------------------------------------------------------------------*
CLASS lcl_dump_section DEFINITION FINAL FRIENDS ltc_dump_section.
  PUBLIC SECTION.
    INTERFACES lif_section.

    TYPES:
      tt_string TYPE lcl_util=>tt_string,
      ty_errid  TYPE c LENGTH 40,

      tt_date_range   TYPE RANGE OF sydatum,
      tt_user_range   TYPE RANGE OF syuname,
      tt_errid_range  TYPE RANGE OF ty_errid,
      tt_client_range TYPE RANGE OF symandt,
      tt_host_range   TYPE RANGE OF snap_beg-ahost,

      "! Header data of one short dump (SNAP_BEG + fields parsed from FLIST)
      BEGIN OF ty_dump,
        datum     TYPE sydatum,
        uzeit     TYPE syuzeit,
        ahost     TYPE snap_beg-ahost,
        uname     TYPE syuname,
        mandt     TYPE symandt,
        errid     TYPE string,
        program   TYPE string,
        include   TYPE string,
        line      TYPE i,
        exc_class TYPE string,
      END OF ty_dump,
      tt_dump TYPE STANDARD TABLE OF ty_dump WITH EMPTY KEY,

      "! Plain-language explanation of one family of runtime errors
      BEGIN OF ty_advice,
        category TYPE string,
        meaning  TYPE string,
        causes   TYPE string,
        who      TYPE string,
        user_do  TYPE string,     " what the user can do right now
        steps    TYPE string,     " how developer / Basis fix it
        example  TYPE string,     " code example of the fix (optional)
        weight   TYPE i,          " 3 = serious, 2 = medium, 1 = low
      END OF ty_advice,

      "! One problem = all identical dumps (same error + program + include + line)
      BEGIN OF ty_group,
        rank       TYPE i,
        errid      TYPE string,
        program    TYPE string,
        include    TYPE string,
        line       TYPE i,
        exc_class  TYPE string,
        count      TYPE i,
        users      TYPE i,
        severity   TYPE string,
        category   TYPE string,
        own_code   TYPE abap_bool,
        first_seen TYPE string,
        last_seen  TYPE string,
        last_datum TYPE sydatum,
        user_list  TYPE string,
        day_list   TYPE string,
        hosts      TYPE string,
        clients    TYPE string,
        advice     TYPE ty_advice,    " determined once in build_groups
        sort_key   TYPE i,
      END OF ty_group,
      tt_group TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY,

      "! Line of the ALV overview (flat, short fields)
      BEGIN OF ty_alv,
        rank       TYPE i,
        severity   TYPE char10,
        count      TYPE i,
        users      TYPE i,
        errid      TYPE char40,
        category   TYPE char40,
        program    TYPE char40,
        include    TYPE char40,
        line       TYPE i,
        own_code   TYPE char3,
        first_seen TYPE char20,
        last_seen  TYPE char20,
      END OF ty_alv,
      tt_alv TYPE STANDARD TABLE OF ty_alv WITH EMPTY KEY.

    "! @parameter it_dates | period (SNAP_BEG-DATUM)
    "! @parameter it_users | users (empty = all)
    "! @parameter it_errids | runtime errors (empty = all)
    "! @parameter it_clients | clients (empty = all)
    "! @parameter it_hosts | application servers (empty = all)
    "! @parameter iv_own_only | only dumps in own code (Z/Y/namespace)
    "! @parameter iv_langu | language for SAP texts
    METHODS constructor
      IMPORTING it_dates    TYPE tt_date_range OPTIONAL
                it_users    TYPE tt_user_range OPTIONAL
                it_errids   TYPE tt_errid_range OPTIONAL
                it_clients  TYPE tt_client_range OPTIONAL
                it_hosts    TYPE tt_host_range OPTIONAL
                iv_own_only TYPE abap_bool DEFAULT abap_false
                iv_langu    TYPE sylangu DEFAULT sy-langu.
    "! Were any problems found (for the ALV output)?
    METHODS has_problems
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    "! ALV overview of the short dump problems
    METHODS show_alv.

  PRIVATE SECTION.
    TYPES:
      "! Cached SNAPT text lines of one runtime error, text type and language
      BEGIN OF ty_snapt_text,
        errid TYPE snapt-errid,
        ttype TYPE snapt-ttype,
        langu TYPE snapt-langu,
        lines TYPE tt_string,
      END OF ty_snapt_text,
      BEGIN OF ty_class_text,
        clsname  TYPE seoclsname,
        langu    TYPE spras,
        descript TYPE seoclasstx-descript,
      END OF ty_class_text,
      BEGIN OF ty_trdir,
        name TYPE trdir-name,
        unam TYPE trdir-unam,
        udat TYPE trdir-udat,
      END OF ty_trdir.

    " settings
    DATA mt_dates TYPE tt_date_range.
    DATA mt_users TYPE tt_user_range.
    DATA mt_errids TYPE tt_errid_range.
    DATA mt_clients TYPE tt_client_range.
    DATA mt_hosts TYPE tt_host_range.
    DATA mv_own_only TYPE abap_bool.
    DATA mv_langu TYPE sylangu.

    " data
    DATA mt_dumps TYPE tt_dump.
    DATA mt_groups TYPE tt_group.

    " caches filled once by prefetch (instead of single SELECTs per problem)
    DATA mt_snapt TYPE HASHED TABLE OF ty_snapt_text WITH UNIQUE KEY errid ttype langu.
    DATA mt_class_texts TYPE HASHED TABLE OF ty_class_text WITH UNIQUE KEY clsname langu.
    DATA mt_trdir TYPE HASHED TABLE OF ty_trdir WITH UNIQUE KEY name.

    "! Read dump headers of the period from SNAP_BEG and apply the filters
    METHODS read_dumps.
    "! Split FLIST ('FC022COMPUTE_INT...AP010ZDUMP_TEST...') into its fields
    METHODS parse_flist
      IMPORTING iv_flist   TYPE csequence
      CHANGING  cs_dump    TYPE ty_dump.
    "! Group identical dumps into problems, rate and sort them
    METHODS build_groups.
    "! Read SAP texts and repository data for all problems at once
    METHODS prefetch.
    "! Number of dumps and of problems rated High
    METHODS count_totals
      EXPORTING ev_dumps TYPE i
                ev_high  TYPE i.
    "! Customer code: Z*/Y* programs, their function groups, namespaces /.../
    METHODS is_own_code
      IMPORTING iv_name       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    "! Knowledge base: plain-language explanation per runtime error family
    METHODS get_advice
      IMPORTING iv_errid         TYPE string
      RETURNING VALUE(rs_advice) TYPE ty_advice.
    "! Lines of SAP's text for a runtime error (SNAPT), falls back to English
    METHODS read_snapt
      IMPORTING iv_errid        TYPE string
                iv_ttype        TYPE sychar01
      RETURNING VALUE(rt_lines) TYPE tt_string.
    "! SAP's one-line description of the runtime error (SNAPT type K)
    METHODS sap_short_text
      IMPORTING iv_errid       TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    "! SAP's 'What happened?' text (SNAPT type U) with placeholders filled in
    METHODS sap_explanation
      IMPORTING is_group       TYPE ty_group
      RETURNING VALUE(rv_text) TYPE string.
    "! Description of an exception class (SEOCLASSTX)
    METHODS exception_text
      IMPORTING iv_class       TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    "! Still happening? Was the code changed after the last dump?
    METHODS status_info
      IMPORTING is_group TYPE ty_group
      EXPORTING ev_text  TYPE string
                ev_class TYPE string.
    "! Ready-to-copy text for a support ticket
    METHODS ticket_text
      IMPORTING is_group       TYPE ty_group
                is_advice      TYPE ty_advice
      RETURNING VALUE(rv_text) TYPE string.
    "! Source lines around the failing line as HTML (failing line highlighted)
    METHODS source_snippet
      IMPORTING iv_include     TYPE string
                iv_line        TYPE i
      RETURNING VALUE(rt_html) TYPE tt_string.
    "! 'last changed by X on Y' from TRDIR
    METHODS last_changed
      IMPORTING iv_include     TYPE string
      RETURNING VALUE(rv_text) TYPE string.
    "! Overview table and one card per problem
    METHODS dump_html
      RETURNING VALUE(rt_html) TYPE tt_string.
    "! Shortcuts to lcl_util (used very often in the HTML code)
    METHODS h
      IMPORTING iv_text        TYPE csequence
      RETURNING VALUE(rv_text) TYPE string.
    METHODS fmt_ts
      IMPORTING iv_date        TYPE sydatum
                iv_time        TYPE syuzeit
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS lcl_dump_section IMPLEMENTATION.

  METHOD constructor.
    mt_dates    = it_dates.
    mt_users    = it_users.
    mt_errids   = it_errids.
    mt_clients  = it_clients.
    mt_hosts    = it_hosts.
    mv_own_only = iv_own_only.
    mv_langu    = iv_langu.
  ENDMETHOD.

  METHOD lif_section~analyze.
    read_dumps( ).
    IF mt_dumps IS INITIAL.
      RETURN.
    ENDIF.
    build_groups( ).
    prefetch( ).
  ENDMETHOD.

  METHOD has_problems.
    rv_yes = xsdbool( mt_groups IS NOT INITIAL ).
  ENDMETHOD.

  METHOD count_totals.
    CLEAR: ev_dumps, ev_high.
    LOOP AT mt_groups INTO DATA(ls_group).
      ev_dumps = ev_dumps + ls_group-count.
      IF ls_group-severity = `High`.
        ev_high = ev_high + 1.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD lif_section~summary_html.
    count_totals( IMPORTING ev_dumps = DATA(lv_dumps) ev_high = DATA(lv_high) ).
    rv_html = |<a href="#dumps">1. Short dumps</a>: <b>{ lv_dumps }</b> dump(s) from <b>{ lines( mt_groups ) }</b> | &&
              |different problem(s), <b>{ lv_high }</b> rated high.|.
  ENDMETHOD.

  METHOD lif_section~get_html.
    APPEND `<h2 class="sec" id="dumps">1. Short dumps (ST22)</h2>` TO rt_html.
    IF mt_groups IS INITIAL.
      APPEND `<div class="box ok">No short dumps found for this selection - good news.</div>` TO rt_html.
      RETURN.
    ENDIF.
    count_totals( IMPORTING ev_dumps = DATA(lv_dumps) ev_high = DATA(lv_high) ).
    APPEND |<p><b>{ lv_dumps }</b> short dumps, caused by <b>{ lines( mt_groups ) }</b> different problems | &&
           |(<b>{ lv_high }</b> rated high).</p>| TO rt_html.
    APPEND LINES OF dump_html( ) TO rt_html.
  ENDMETHOD.

  METHOD lif_section~write_list.
    " background run (e.g. daily job): plain list in the spool
    DATA lv_status TYPE string.
    DATA lv_scls TYPE string.
    DATA lv_text TYPE string.
    count_totals( IMPORTING ev_dumps = DATA(lv_dumps) ).
    lv_text = |Short dumps (ST22) - { lv_dumps } dumps, { lines( mt_groups ) } different problems|.
    WRITE / lv_text.
    ULINE.
    LOOP AT mt_groups INTO DATA(ls_g).
      DATA(ls_adv) = ls_g-advice.
      status_info( EXPORTING is_group = ls_g IMPORTING ev_text = lv_status ev_class = lv_scls ).
      lv_text = |{ ls_g-rank }. [{ ls_g-severity }] { ls_adv-category } - { ls_g-errid } { ls_g-exc_class }|.
      WRITE / lv_text.
      lv_text = |   { ls_g-count } time(s), { ls_g-users } user(s), last { ls_g-last_seen }. { lv_status }|.
      WRITE / lv_text.
      lv_text = |   Where: { ls_g-program } / { ls_g-include } line { ls_g-line }|.
      WRITE / lv_text.
      lv_text = |   Meaning: { ls_adv-meaning }|.
      WRITE / lv_text.
      lv_text = |   User can: { ls_adv-user_do }|.
      WRITE / lv_text.
      lv_text = |   Fix: { ls_adv-steps }|.
      WRITE / lv_text.
      SKIP.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
* Reading
*----------------------------------------------------------------------*
  METHOD read_dumps.
    " SNAP_BEG = header line of every dump (SEQNO '000'); newest first, at most 5000
    SELECT datum, uzeit, ahost, uname, mandt, flist
      FROM snap_beg
      WHERE seqno = '000'
        AND datum IN @mt_dates
        AND uname IN @mt_users
        AND mandt IN @mt_clients
        AND ahost IN @mt_hosts
      ORDER BY datum DESCENDING, uzeit DESCENDING
      INTO TABLE @DATA(lt_snap)
      UP TO 5000 ROWS.

    LOOP AT lt_snap INTO DATA(ls_snap).
      DATA(ls_dump) = VALUE ty_dump( datum = ls_snap-datum
                                     uzeit = ls_snap-uzeit
                                     ahost = ls_snap-ahost
                                     uname = ls_snap-uname
                                     mandt = ls_snap-mandt ).
      parse_flist( EXPORTING iv_flist = ls_snap-flist CHANGING cs_dump = ls_dump ).
      IF ls_dump-errid IS INITIAL.
        ls_dump-errid = 'UNKNOWN'.
      ENDIF.
      " these filters need the parsed FLIST, so they cannot be done in the SELECT
      IF mt_errids IS NOT INITIAL AND NOT ls_dump-errid IN mt_errids.
        CONTINUE.
      ENDIF.
      IF mv_own_only = abap_true
         AND is_own_code( ls_dump-program ) = abap_false
         AND is_own_code( ls_dump-include ) = abap_false.
        CONTINUE.
      ENDIF.
      APPEND ls_dump TO mt_dumps.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_flist.
    " FLIST is a chain of entries: ID (2 chars) + length (3 digits) + value.
    "   FC = runtime error, AP = program, AI = include, AL = line,
    "   XC = exception class
    DATA lv_off   TYPE i.
    DATA lv_len   TYPE i.
    DATA lv_lenc  TYPE c LENGTH 3.
    DATA lv_id    TYPE c LENGTH 2.
    DATA lv_value TYPE string.

    DATA(lv_max) = strlen( iv_flist ).
    WHILE lv_off + 5 <= lv_max.
      lv_id   = substring( val = iv_flist off = lv_off len = 2 ).
      lv_lenc = substring( val = iv_flist off = lv_off + 2 len = 3 ).
      IF lv_lenc CN '0123456789'.
        EXIT.
      ENDIF.
      lv_len = lv_lenc.
      lv_off = lv_off + 5.
      IF lv_off + lv_len > lv_max.
        lv_len = lv_max - lv_off.
      ENDIF.
      IF lv_len > 0.
        lv_value = substring( val = iv_flist off = lv_off len = lv_len ).
        CONDENSE lv_value.
        CASE lv_id.
          WHEN 'FC'. cs_dump-errid     = lv_value.
          WHEN 'AP'. cs_dump-program   = lv_value.
          WHEN 'AI'. cs_dump-include   = lv_value.
          WHEN 'XC'. cs_dump-exc_class = lv_value.
          WHEN 'AL'.
            IF lv_value CO '0123456789 '.
              cs_dump-line = lv_value.
            ENDIF.
        ENDCASE.
      ENDIF.
      lv_off = lv_off + lv_len.
    ENDWHILE.
  ENDMETHOD.

  METHOD is_own_code.
    rv_yes = xsdbool( iv_name CP 'Z*'      OR iv_name CP 'Y*'
                   OR iv_name CP 'LZ*'     OR iv_name CP 'LY*'
                   OR iv_name CP 'SAPLZ*'  OR iv_name CP 'SAPLY*'
                   OR iv_name CP 'SAPMZ*'  OR iv_name CP 'SAPMY*'
                   OR iv_name CP '/*' ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Grouping duplicates
*----------------------------------------------------------------------*
  METHOD build_groups.
    TYPES: BEGIN OF ty_day,
             datum TYPE sydatum,
             count TYPE i,
           END OF ty_day.
    DATA lt_days TYPE SORTED TABLE OF ty_day WITH UNIQUE KEY datum.
    DATA ls_day TYPE ty_day.

    " One pass over all dumps: GROUP BY collects identical dumps (same error, program,
    " include and line) into one group. Replaces one LOOP ... WHERE per group, which
    " took (number of dumps x number of problems) steps.
    LOOP AT mt_dumps INTO DATA(ls_dump)
         GROUP BY ( errid   = ls_dump-errid
                    program = ls_dump-program
                    include = ls_dump-include
                    line    = ls_dump-line )
         INTO DATA(ls_key).
      DATA lt_users   TYPE SORTED TABLE OF syuname WITH UNIQUE KEY table_line.
      DATA lt_hosts   TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.
      DATA lt_clients TYPE SORTED TABLE OF symandt WITH UNIQUE KEY table_line.
      DATA lv_first   TYPE string.
      DATA lv_last    TYPE string.
      CLEAR: lt_users, lt_hosts, lt_clients, lt_days, lv_first, lv_last.

      DATA(ls_group) = VALUE ty_group( errid = ls_key-errid program = ls_key-program
                                       include = ls_key-include line = ls_key-line ).
      " aggregate the members: count, users, servers, clients, dumps per day, first/last time
      LOOP AT GROUP ls_key INTO DATA(ls_d).
        ls_group-count = ls_group-count + 1.
        INSERT ls_d-uname INTO TABLE lt_users.
        INSERT CONV string( ls_d-ahost ) INTO TABLE lt_hosts.
        INSERT ls_d-mandt INTO TABLE lt_clients.
        ls_day-datum = ls_d-datum.
        ls_day-count = 1.
        COLLECT ls_day INTO lt_days.
        IF ls_group-exc_class IS INITIAL.
          ls_group-exc_class = ls_d-exc_class.
        ENDIF.
        DATA(lv_ts) = |{ ls_d-datum }{ ls_d-uzeit }|.
        IF lv_first IS INITIAL OR lv_ts < lv_first.
          lv_first = lv_ts.
          ls_group-first_seen = fmt_ts( iv_date = ls_d-datum iv_time = ls_d-uzeit ).
        ENDIF.
        IF lv_ts > lv_last.
          lv_last = lv_ts.
          ls_group-last_seen  = fmt_ts( iv_date = ls_d-datum iv_time = ls_d-uzeit ).
          ls_group-last_datum = ls_d-datum.
        ENDIF.
      ENDLOOP.

      ls_group-users = lines( lt_users ).
      DATA lt_ulist TYPE tt_string.
      CLEAR lt_ulist.
      LOOP AT lt_users INTO DATA(lv_user).
        IF sy-tabix > 5.
          APPEND |+ { lines( lt_users ) - 5 } more| TO lt_ulist.
          EXIT.
        ENDIF.
        APPEND CONV string( lv_user ) TO lt_ulist.
      ENDLOOP.
      ls_group-user_list = concat_lines_of( table = lt_ulist sep = `, ` ).
      ls_group-hosts     = concat_lines_of( table = lt_hosts sep = `, ` ).
      DATA lt_clist TYPE tt_string.
      CLEAR lt_clist.
      LOOP AT lt_clients INTO DATA(lv_client).
        APPEND CONV string( lv_client ) TO lt_clist.
      ENDLOOP.
      ls_group-clients = concat_lines_of( table = lt_clist sep = `, ` ).

      " dumps per day (last 14 days with dumps)
      DATA lt_dlist TYPE tt_string.
      CLEAR lt_dlist.
      DATA(lv_skip) = lines( lt_days ) - 14.
      LOOP AT lt_days INTO ls_day.
        IF sy-tabix <= lv_skip.
          CONTINUE.
        ENDIF.
        APPEND |{ ls_day-datum DATE = USER }: { ls_day-count }x| TO lt_dlist.
      ENDLOOP.
      ls_group-day_list = concat_lines_of( table = lt_dlist sep = `, ` ).

      ls_group-own_code = xsdbool( is_own_code( ls_group-program ) = abap_true
                                OR is_own_code( ls_group-include ) = abap_true ).
      " explanation is used for the rating and for every output - determine it only once
      ls_group-advice   = get_advice( ls_group-errid ).
      ls_group-category = ls_group-advice-category.

      " severity: how serious the error type is + how often it happens + how many users
      DATA(lv_score) = ls_group-advice-weight.
      IF ls_group-count >= 10.
        lv_score = lv_score + 2.
      ELSEIF ls_group-count >= 3.
        lv_score = lv_score + 1.
      ENDIF.
      IF ls_group-users >= 3.
        lv_score = lv_score + 1.
      ENDIF.
      ls_group-severity = COND #( WHEN lv_score >= 5 THEN `High`
                                  WHEN lv_score >= 3 THEN `Medium`
                                  ELSE `Low` ).
      ls_group-sort_key = lv_score * 100000 + ls_group-count.
      APPEND ls_group TO mt_groups.
    ENDLOOP.

    " worst first; rank = position, used as anchor in the HTML
    SORT mt_groups BY sort_key DESCENDING.
    LOOP AT mt_groups ASSIGNING FIELD-SYMBOL(<ls_g>).
      <ls_g>-rank = sy-tabix.
    ENDLOOP.
  ENDMETHOD.

  METHOD fmt_ts.
    rv_text = lcl_util=>fmt_ts( iv_date = iv_date iv_time = iv_time ).
  ENDMETHOD.

*----------------------------------------------------------------------*
* Plain-language knowledge base
*----------------------------------------------------------------------*
  METHOD get_advice.
    IF iv_errid = 'TIME_OUT'.
      rs_advice = VALUE #(
        category = `Program ran too long`
        meaning  = `The program was still running when the system's time limit for online work was reached ` &&
                   `(usually 10-20 minutes), so the system stopped it.`
        causes   = `Too much data selected; a slow database read (missing index, no WHERE condition); a loop ` &&
                   `that never ends.`
        who      = `Developer (performance), or the user (smaller selection).`
        user_do  = `Run it again with a smaller selection (shorter period, one company code or plant). If you ` &&
                   `really need all the data, start it in the background instead: on the selection screen ` &&
                   `choose Program > Execute in Background (F9) - background jobs have no such time limit.`
        steps    = `Developer: measure the program with SAT or ST12 and fix the slowest statement (often a ` &&
                   `SELECT without a good WHERE condition or index, or a SELECT inside a LOOP). Do not just ` &&
                   `raise the time limit - it only hides the problem.`
        example  = |" Before: reads the whole table, then filters in ABAP\n| &&
                   |SELECT * FROM vbap INTO TABLE @DATA(lt_all).\n| &&
                   |DELETE lt_all WHERE erdat < p_date.\n\n| &&
                   |" After: the database filters and returns only needed fields\n| &&
                   |SELECT vbeln, posnr, matnr FROM vbap\n| &&
                   |  WHERE erdat >= @p_date\n| &&
                   |  INTO TABLE @DATA(lt_items).|
        weight   = 2 ).
    ELSEIF iv_errid CP 'TSV_*' OR iv_errid = 'SYSTEM_NO_ROLL' OR iv_errid CP 'MEMORY_*'
        OR iv_errid = 'STORAGE_PARAMETERS_WRONG_SET' OR iv_errid = 'SYSTEM_NO_SHM_MEMORY'.
      rs_advice = VALUE #(
        category = `Out of memory`
        meaning  = `The program tried to hold more data in memory than the system allows, so it was stopped.`
        causes   = `A very large selection (e.g. a whole table without filter); an internal table that keeps ` &&
                   `growing; data copied many times.`
        who      = `Developer; Basis only if the memory settings are really too small.`
        user_do  = `Restrict the selection (shorter period, fewer organisational units) and try again. If you ` &&
                   `really need all data, ask for it to be processed in smaller parts or in a background job.`
        steps    = `Developer: in ST22 look at 'Chosen variables' / memory consumption for the biggest ` &&
                   `internal tables. Process data in packages (PACKAGE SIZE / OPEN CURSOR), select only the ` &&
                   `fields you need and FREE tables that are no longer needed. Basis: check the memory ` &&
                   `parameters only if normal selections also fail.`
        example  = |" Process a big table in packages instead of all at once\n| &&
                   |SELECT * FROM bseg INTO TABLE @lt_pack PACKAGE SIZE 10000.\n| &&
                   |  " process lt_pack here\n| &&
                   |ENDSELECT.\n| &&
                   |FREE lt_big_table.   " release memory that is no longer needed|
        weight   = 3 ).
    ELSEIF iv_errid = 'MESSAGE_TYPE_X'.
      rs_advice = VALUE #(
        category = `Program stopped itself on purpose`
        meaning  = `The program found a situation it was not built for and stopped deliberately with an 'X' ` &&
                   `message.`
        causes   = `Unexpected data or missing customizing; often in SAP standard code reacting to ` &&
                   `inconsistent data.`
        who      = `Functional consultant / developer; search SAP Notes for the message.`
        user_do  = `Write down exactly what you entered (transaction, document number, values). The program ` &&
                   `stopped because of something in that data or in the system setup. Ask your key user or ` &&
                   `functional consultant to check the master data and customizing for it. Do not repeat the ` &&
                   `same step again and again - it will stop at the same place.`
        steps    = `Open the dump in ST22 and note the message class and number in 'Error analysis'. Search ` &&
                   `SAP Notes with that message plus the program name. Check whether the input data or ` &&
                   `customizing is complete.`
        example  = |" In own code: give the user a normal error message instead of a dump\n| &&
                   |MESSAGE e001(zmsg) WITH lv_document.   " instead of MESSAGE x001(zmsg)|
        weight   = 2 ).
    ELSEIF iv_errid CP 'OBJECTS_OBJREF_NOT_ASSIGNED*'.
      rs_advice = VALUE #(
        category = `Programming error: object missing`
        meaning  = `The program tried to use an object that was never created (a 'null reference').`
        causes   = `An object was not created because of an earlier error, or the code forgot to check that it` &&
                   ` exists.`
        who      = `Developer.`
        user_do  = `Try once more. If it happens again with the same steps, report it with the exact steps and ` &&
                   `data - this is a programming error that you cannot fix yourself. Sometimes another way ` &&
                   `(other transaction, other input order) avoids it until it is fixed.`
        steps    = `Look at the failing line below: the object used there is empty. The developer should find ` &&
                   `out why it was not created and add a check (IS BOUND) before using it.`
        example  = |" Before\n| &&
                   |lo_order->get_items( ).\n\n| &&
                   |" After: check that the object exists first\n| &&
                   |IF lo_order IS BOUND.\n| &&
                   |  lo_order->get_items( ).\n| &&
                   |ELSE.\n| &&
                   |  MESSAGE 'Order could not be loaded' TYPE 'E'.\n| &&
                   |ENDIF.|
        weight   = 2 ).
    ELSEIF iv_errid = 'GETWA_NOT_ASSIGNED'.
      rs_advice = VALUE #(
        category = `Programming error: field symbol empty`
        meaning  = `The program used a field symbol (a pointer) that did not point to anything.`
        causes   = `A READ TABLE ... ASSIGNING found no row, or an ASSIGN failed, and the code did not check ` &&
                   `sy-subrc / IS ASSIGNED.`
        who      = `Developer.`
        user_do  = `Report it with the exact steps and data. It is often triggered by data the program did ` &&
                   `not expect (e.g. an item without a matching entry), so mention the document or record.`
        steps    = `Look at the failing line below. Developer: check IS ASSIGNED / sy-subrc after the ASSIGN ` &&
                   `or READ before using the field symbol.`
        example  = |" Before\n| &&
                   |READ TABLE lt_items ASSIGNING <ls_item> WITH KEY matnr = lv_matnr.\n| &&
                   |<ls_item>-menge = 1.\n\n| &&
                   |" After\n| &&
                   |READ TABLE lt_items ASSIGNING <ls_item> WITH KEY matnr = lv_matnr.\n| &&
                   |IF sy-subrc = 0.\n| &&
                   |  <ls_item>-menge = 1.\n| &&
                   |ENDIF.|
        weight   = 2 ).
    ELSEIF iv_errid = 'UNCAUGHT_EXCEPTION' OR iv_errid = 'RAISE_EXCEPTION'.
      rs_advice = VALUE #(
        category = `Error not handled`
        meaning  = `Something went wrong and raised an error (exception), but no part of the program caught ` &&
                   `and handled it.`
        causes   = `The real cause depends on the exception class or name shown in the dump (e.g. row not ` &&
                   `found, conversion error, missing authorization).`
        who      = `Developer.`
        user_do  = `Note what you did and which data you used. Often the data is the trigger (a missing entry, ` &&
                   `a wrong value, a missing authorization) - check it first, then report it.`
        steps    = `Look at the exception class shown under 'Technical details'. Developer: fix the cause or ` &&
                   `add TRY ... CATCH (or EXCEPTIONS for function modules) to handle it with a clear message.`
        example  = |" Catch the error and show a clear message instead of a dump\n| &&
                   |TRY.\n| &&
                   |    lv_value = lo_reader->read( lv_key ).\n| &&
                   |  CATCH cx_root INTO DATA(lx_error).   " better: the exact class from the dump\n| &&
                   |    MESSAGE lx_error->get_text( ) TYPE 'E'.\n| &&
                   |ENDTRY.|
        weight   = 2 ).
    ELSEIF iv_errid CP 'CONVT_*'.
      rs_advice = VALUE #(
        category = `Data could not be converted`
        meaning  = `A value could not be turned into the required format - for example text like 'ABC' into a ` &&
                   `number, or a value too big for the field.`
        causes   = `Wrong or unexpected input data (file upload, interface, user entry); field too short for ` &&
                   `the value.`
        who      = `Developer, sometimes the owner of the incoming data.`
        user_do  = `Check the values you entered or uploaded: numbers must not contain letters, spaces or the ` &&
                   `wrong decimal separator, dates must be valid, and values must not be too long. Correct the ` &&
                   `input or the file and try again.`
        steps    = `Check the input data that was processed. Developer: validate values before converting, or ` &&
                   `catch CX_SY_CONVERSION_ERROR and tell the user which value is wrong.`
        example  = |TRY.\n| &&
                   |    lv_amount = lv_text.\n| &&
                   |  CATCH cx_sy_conversion_error.\n| &&
                   |    MESSAGE 'Invalid number in the input' TYPE 'E'.\n| &&
                   |ENDTRY.|
        weight   = 2 ).
    ELSEIF iv_errid CP '*ZERODIVIDE*' OR iv_errid CP 'COMPUTE_*' OR iv_errid CP 'BCD_*'.
      rs_advice = VALUE #(
        category = `Calculation error`
        meaning  = `A calculation failed - most often a division by zero or a result too large for the field.`
        causes   = `A quantity, price or total that is zero or empty in the data; field type too small.`
        who      = `Developer.`
        user_do  = `Check the data you used for zero or empty values - for example a quantity of 0, a price ` &&
                   `of 0 or a missing conversion factor in the material master. Fill in the missing value and ` &&
                   `try again.`
        steps    = `Look at the formula in the failing line below. Developer: check the divisor is not zero ` &&
                   `and that the result field is large enough.`
        example  = |" Before\n| &&
                   |lv_price = lv_amount / lv_quantity.\n\n| &&
                   |" After\n| &&
                   |IF lv_quantity <> 0.\n| &&
                   |  lv_price = lv_amount / lv_quantity.\n| &&
                   |ELSE.\n| &&
                   |  lv_price = 0.   " or tell the user that the quantity is missing\n| &&
                   |ENDIF.|
        weight   = 2 ).
    ELSEIF iv_errid CP '*DUPLICATE*' OR iv_errid = 'SAPSQL_ARRAY_INSERT_DUPREC'.
      rs_advice = VALUE #(
        category = `Record already exists`
        meaning  = `The program tried to insert a record whose key already exists in a database table or ` &&
                   `internal table.`
        causes   = `The same data processed twice (job ran twice, restarted load); key not unique in the ` &&
                   `source data.`
        who      = `Developer; check with whoever ran the job.`
        user_do  = `Check whether you or a job already processed this data - e.g. the upload or posting was ` &&
                   `started twice. Do not start it again before checking whether the first run already ` &&
                   `created the data.`
        steps    = `Check whether the job/process ran more than once. Developer: use MODIFY instead of INSERT ` &&
                   `if updating is intended, or check for existing entries first.`
        example  = |" Before: fails if the record already exists\n| &&
                   |INSERT zorders FROM ls_order.\n\n| &&
                   |" After: updates if it exists, inserts if not\n| &&
                   |MODIFY zorders FROM ls_order.|
        weight   = 2 ).
    ELSEIF iv_errid CP 'DBSQL_*' OR iv_errid CP 'DBIF_*' OR iv_errid CP 'SAPSQL_*'.
      rs_advice = VALUE #(
        category = `Database error`
        meaning  = `The database refused or could not complete a request from the program.`
        causes   = `Database or log space full; lock/deadlock; statement too large (huge FOR ALL ENTRIES or ` &&
                   `range list); table/view missing.`
        who      = `Basis (space, database) and developer (statement).`
        user_do  = `Try again a bit later - temporary database problems (locks, full log) often go away. If it ` &&
                   `keeps happening, tell your support team quickly: other users are probably affected too.`
        steps    = `Basis: check database space and logs (DB02, ST04). Developer: look at the SQL statement in` &&
                   ` the failing line below - split very large selections into smaller packages.`
        example  = |" An empty FOR ALL ENTRIES table selects EVERYTHING - always check it first\n| &&
                   |IF lt_keys IS NOT INITIAL.\n| &&
                   |  SELECT matnr, maktx FROM makt\n| &&
                   |    FOR ALL ENTRIES IN @lt_keys\n| &&
                   |    WHERE matnr = @lt_keys-matnr AND spras = @sy-langu\n| &&
                   |    INTO TABLE @DATA(lt_texts).\n| &&
                   |ENDIF.|
        weight   = 3 ).
    ELSEIF iv_errid CP 'CALL_FUNCTION_*NOT_FOUND*' OR iv_errid CP 'LOAD_PROGRAM_*'
        OR iv_errid = 'PERFORM_NOT_FOUND' OR iv_errid CP '*_NOT_FOUND'.
      rs_advice = VALUE #(
        category = `Something called does not exist`
        meaning  = `The program called a function, program or routine that does not exist or is not active in ` &&
                   `this system.`
        causes   = `Incomplete or missing transport; object deleted or not activated; typo in a dynamic call.`
        who      = `Developer / transport owner.`
        user_do  = `There is nothing you can do as a user - a part of the program is missing in this system. ` &&
                   `Report it with the program name; it is usually fixed by importing a missing transport.`
        steps    = `Check in SE37/SE38 that the called object exists and is active. Compare with the ` &&
                   `development system and check the transport logs (STMS).`
        example  = |" For dynamic calls, catch the error\n| &&
                   |TRY.\n| &&
                   |    CALL FUNCTION lv_fm_name.\n| &&
                   |  CATCH cx_sy_dyn_call_illegal_func.\n| &&
                   |    MESSAGE 'Function not available in this system' TYPE 'E'.\n| &&
                   |ENDTRY.|
        weight   = 2 ).
    ELSEIF iv_errid CP 'CALL_FUNCTION_*CONFLICT*' OR iv_errid CP 'CALL_METHOD_*CONFLICT*'
        OR iv_errid CP '*_PARAM_*'.
      rs_advice = VALUE #(
        category = `Call with wrong parameters`
        meaning  = `A function or method was called with parameters that do not match its definition (wrong ` &&
                   `type or missing).`
        causes   = `The called object was changed but the caller was not adapted, or only one side was ` &&
                   `transported.`
        who      = `Developer.`
        user_do  = `Report it with the program name - this is a programming or transport error, not caused ` &&
                   `by your data.`
        steps    = `Compare the call in the failing line with the definition of the called function/method. ` &&
                   `Make sure both are transported together.`
        example  = |" The called method got a new mandatory parameter IV_BUKRS -\n| &&
                   |" every caller must pass it:\n| &&
                   |lo_doc->post( iv_belnr = lv_belnr iv_bukrs = lv_bukrs ).|
        weight   = 2 ).
    ELSEIF iv_errid CP 'RFC_*' OR iv_errid CP 'CALL_FUNCTION_REMOTE*'
        OR iv_errid CP 'CALL_FUNCTION_*FAILURE*' OR iv_errid CP 'CALL_FUNCTION_SINGLE_LOGIN*'.
      rs_advice = VALUE #(
        category = `Connection to another system failed`
        meaning  = `A call to another system (RFC) failed - the other system was down, unreachable, or refused` &&
                   ` the logon.`
        causes   = `Target system down; wrong RFC destination settings; expired password of the RFC user; ` &&
                   `network problem.`
        who      = `Basis.`
        user_do  = `Try again in a few minutes - the other system may be restarting. If it still fails, report ` &&
                   `it with the exact time so Basis can check the connection.`
        steps    = `Basis: test the RFC destination in SM59 and check the target system. Check whether the RFC` &&
                   ` user is locked or its password expired.`
        example  = |" Catch connection errors in RFC calls\n| &&
                   |CALL FUNCTION 'Z_REMOTE_FM' DESTINATION lv_dest\n| &&
                   |  EXCEPTIONS\n| &&
                   |    system_failure        = 1 MESSAGE lv_msg\n| &&
                   |    communication_failure = 2 MESSAGE lv_msg\n| &&
                   |    OTHERS                = 3.\n| &&
                   |IF sy-subrc <> 0.\n| &&
                   |  MESSAGE lv_msg TYPE 'E'.\n| &&
                   |ENDIF.|
        weight   = 3 ).
    ELSEIF iv_errid = 'SYNTAX_ERROR' OR iv_errid CP 'LOAD_*'.
      rs_advice = VALUE #(
        category = `Program has a syntax error`
        meaning  = `The program could not even start because its code contains an error.`
        causes   = `Incomplete transport; a changed object that the program uses; code activated with errors.`
        who      = `Developer.`
        user_do  = `Report it right away - the program cannot run at all until a developer corrects it, and ` &&
                   `every user gets the same error.`
        steps    = `Open the program in SE38 and run the syntax check (Ctrl+F2). Fix and re-activate; check ` &&
                   `that all related objects are transported.`
        weight   = 3 ).
    ELSEIF iv_errid = 'ASSERTION_FAILED'.
      rs_advice = VALUE #(
        category = `Built-in check failed`
        meaning  = `The program contains a safety check (ASSERT) that found an impossible situation and ` &&
                   `stopped.`
        causes   = `Inconsistent data or an internal program error.`
        who      = `Developer (own code) or SAP (standard code - search SAP Notes).`
        user_do  = `Report it with the document or data you used - the program found data it considers ` &&
                   `impossible, so that data may need to be checked or corrected.`
        steps    = `Look at the ASSERT statement in the failing line below to see which condition was ` &&
                   `violated.`
        weight   = 2 ).
    ELSEIF iv_errid CP 'ITAB_*' OR iv_errid CP 'TABLE_*' OR iv_errid CP 'STRING_*'.
      rs_advice = VALUE #(
        category = `Programming error: invalid table or text access`
        meaning  = `The program accessed a row or a part of a text that does not exist (e.g. row 10 of a table` &&
                   ` with 5 rows, or characters beyond the end of a text).`
        causes   = `Missing check of table size or text length.`
        who      = `Developer.`
        user_do  = `Report it with the exact steps. It is often triggered by unusual data - an empty list, a ` &&
                   `document without items, or a very long text - so mention which data you used.`
        steps    = `Look at the failing line below. Developer: check LINES( ) / STRLEN( ) before accessing by ` &&
                   `index or offset.`
        example  = |" Before: dumps if the table is empty\n| &&
                   |lv_first = lt_items[ 1 ]-matnr.\n\n| &&
                   |" After\n| &&
                   |IF lt_items IS NOT INITIAL.\n| &&
                   |  lv_first = lt_items[ 1 ]-matnr.\n| &&
                   |ENDIF.|
        weight   = 2 ).
    ELSEIF iv_errid CP 'DATASET_*' OR iv_errid CP 'OPEN_DATASET_*'.
      rs_advice = VALUE #(
        category = `File problem on the server`
        meaning  = `A file on the application server could not be opened, read or written.`
        causes   = `Wrong path or file name; missing folder; no operating-system permission; disk full.`
        who      = `Basis (folder/permissions), developer (path).`
        user_do  = `Check the file name and folder you entered. If they are correct, ask Basis to check that ` &&
                   `the folder exists and that the SAP system may write there.`
        steps    = `Check the path in AL11 and the authorizations. Basis: check disk space on the application ` &&
                   `server.`
        example  = |OPEN DATASET lv_file FOR OUTPUT IN TEXT MODE ENCODING UTF-8.\n| &&
                   |IF sy-subrc <> 0.\n| &&
                   |  MESSAGE 'File could not be opened' TYPE 'E'.\n| &&
                   |ENDIF.|
        weight   = 2 ).
    ELSEIF iv_errid CP 'DYNPRO_*'.
      rs_advice = VALUE #(
        category = `Screen error`
        meaning  = `A screen (dynpro) could not be processed - for example a missing screen or a field ` &&
                   `problem.`
        causes   = `Screen not generated or transported; called in background where no screen exists.`
        who      = `Developer.`
        user_do  = `If this happened in a background job: the program needs a screen and cannot run in ` &&
                   `background - run it online instead. Otherwise report it with the steps.`
        steps    = `Check the screen in SE51 and whether the program was run in background while needing a ` &&
                   `screen.`
        weight   = 1 ).
    ELSEIF iv_errid = 'POSTING_ILLEGAL_STATEMENT'.
      rs_advice = VALUE #(
        category = `Statement not allowed during update`
        meaning  = `A statement (e.g. COMMIT WORK or a screen call) was executed inside an update function, ` &&
                   `where it is not allowed.`
        causes   = `Programming error in an update module or a user exit called during update.`
        who      = `Developer.`
        user_do  = `Your data may NOT have been saved. Check whether your document exists (display ` &&
                   `transaction) before entering it again, then report the problem.`
        steps    = `Remove COMMIT/CALL SCREEN/MESSAGE from the update-task code shown below.`
        weight   = 2 ).
    ELSE.
      rs_advice = VALUE #(
        category = `Other runtime error`
        meaning  = `The program was stopped by the ABAP runtime because of an error it could not handle.`
        causes   = `See SAP's own explanation above and the dump in ST22.`
        who      = `Developer (own code) or search SAP Notes (SAP standard code).`
        user_do  = `Try once more. If it happens again with the same steps, report it using the ticket text ` &&
                   `below.`
        steps    = `Open one of the dumps in ST22 and read 'What happened?' and 'Error analysis'. Search SAP ` &&
                   `Notes with the error name and the program name.`
        weight   = 1 ).
    ENDIF.
  ENDMETHOD.

*----------------------------------------------------------------------*
* SAP texts and extra information
*----------------------------------------------------------------------*
  METHOD prefetch.
    " Read all SAP texts and repository data the HTML needs in three SELECTs for ALL problems,
    " instead of 4-6 single SELECTs per problem card. FOR ALL ENTRIES splits long key lists
    " into blocks itself; an empty driver table would select everything, so it is checked first.
    TYPES: BEGIN OF ty_errid,
             errid TYPE snapt-errid,
           END OF ty_errid,
           BEGIN OF ty_class,
             clsname TYPE seoclsname,
           END OF ty_class,
           BEGIN OF ty_prog,
             name TYPE trdir-name,
           END OF ty_prog.
    DATA lt_errids TYPE SORTED TABLE OF ty_errid WITH UNIQUE KEY errid.
    DATA lt_classes TYPE SORTED TABLE OF ty_class WITH UNIQUE KEY clsname.
    DATA lt_progs TYPE SORTED TABLE OF ty_prog WITH UNIQUE KEY name.

    LOOP AT mt_groups INTO DATA(ls_group).
      INSERT VALUE #( errid = ls_group-errid ) INTO TABLE lt_errids.
      IF ls_group-exc_class IS NOT INITIAL.
        INSERT VALUE #( clsname = ls_group-exc_class ) INTO TABLE lt_classes.
      ENDIF.
      INSERT VALUE #( name = ls_group-program ) INTO TABLE lt_progs.
      INSERT VALUE #( name = ls_group-include ) INTO TABLE lt_progs.
    ENDLOOP.

    " SAP's runtime error texts: K = short text, U = what happened; user language and English
    IF lt_errids IS NOT INITIAL.
      SELECT errid, ttype, langu, seqno, tline FROM snapt
        FOR ALL ENTRIES IN @lt_errids
        WHERE errid = @lt_errids-errid
          AND ttype IN ('K','U')
          AND langu IN (@mv_langu,'E')
        INTO TABLE @DATA(lt_snapt).
      SORT lt_snapt BY errid ttype langu seqno.
      LOOP AT lt_snapt INTO DATA(ls_snapt).
        DATA(lv_line) = condense( CONV string( ls_snapt-tline ) ).
        " &INCLUDE lines refer to generic standard texts - skip them
        IF lv_line IS INITIAL OR lv_line CP '&INCLUDE*'.
          CONTINUE.
        ENDIF.
        READ TABLE mt_snapt ASSIGNING FIELD-SYMBOL(<ls_text>)
             WITH TABLE KEY errid = ls_snapt-errid ttype = ls_snapt-ttype langu = ls_snapt-langu.
        IF sy-subrc <> 0.
          INSERT VALUE #( errid = ls_snapt-errid ttype = ls_snapt-ttype langu = ls_snapt-langu )
                 INTO TABLE mt_snapt ASSIGNING <ls_text>.
        ENDIF.
        APPEND lv_line TO <ls_text>-lines.
      ENDLOOP.
    ENDIF.

    " descriptions of the exception classes
    IF lt_classes IS NOT INITIAL.
      SELECT clsname, langu, descript FROM seoclasstx
        FOR ALL ENTRIES IN @lt_classes
        WHERE clsname = @lt_classes-clsname
          AND langu IN (@mv_langu,'E')
        INTO TABLE @mt_class_texts.
    ENDIF.

    " who changed the program / include last, and when
    IF lt_progs IS NOT INITIAL.
      SELECT name, unam, udat FROM trdir
        FOR ALL ENTRIES IN @lt_progs
        WHERE name = @lt_progs-name
        INTO TABLE @mt_trdir.
    ENDIF.
  ENDMETHOD.

  METHOD read_snapt.
    " from the cache filled by prefetch: user language first, English as fallback
    READ TABLE mt_snapt INTO DATA(ls_text)
         WITH TABLE KEY errid = CONV snapt-errid( iv_errid ) ttype = iv_ttype langu = mv_langu.
    IF sy-subrc <> 0.
      READ TABLE mt_snapt INTO ls_text
           WITH TABLE KEY errid = CONV snapt-errid( iv_errid ) ttype = iv_ttype langu = 'E'.
    ENDIF.
    rt_lines = ls_text-lines.
  ENDMETHOD.

  METHOD sap_short_text.
    DATA(lt_lines) = read_snapt( iv_errid = iv_errid iv_ttype = 'K' ).
    rv_text = concat_lines_of( table = lt_lines sep = ` ` ).
  ENDMETHOD.

  METHOD sap_explanation.
    " SAP's 'What happened?' text, with its placeholders (&AP, &AI, ...) filled in
    TYPES: BEGIN OF ty_var,
             id  TYPE string,
             val TYPE string,
           END OF ty_var.
    DATA lt_vars TYPE STANDARD TABLE OF ty_var WITH EMPTY KEY.

    DATA(lt_lines) = read_snapt( iv_errid = is_group-errid iv_ttype = 'U' ).
    rv_text = concat_lines_of( table = lt_lines sep = ` ` ).
    IF rv_text IS INITIAL.
      RETURN.
    ENDIF.
    lt_vars = VALUE #( ( id = `AP` val = is_group-program )
                       ( id = `AI` val = is_group-include )
                       ( id = `AL` val = |{ is_group-line }| )
                       ( id = `XC` val = is_group-exc_class )
                       ( id = `FC` val = is_group-errid ) ).
    LOOP AT lt_vars INTO DATA(ls_var).
      DATA(lv_pattern) = |&{ ls_var-id }&|.
      REPLACE ALL OCCURRENCES OF lv_pattern IN rv_text WITH ls_var-val.
      lv_pattern = |&{ ls_var-id }|.
      REPLACE ALL OCCURRENCES OF lv_pattern IN rv_text WITH ls_var-val.
    ENDLOOP.
    " placeholders we cannot fill
    REPLACE ALL OCCURRENCES OF REGEX `&[A-Z][A-Z0-9]&?` IN rv_text WITH `(?)`.
  ENDMETHOD.

  METHOD exception_text.
    " from the cache filled by prefetch: user language first, English as fallback
    IF iv_class IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_class) = CONV seoclsname( iv_class ).
    READ TABLE mt_class_texts INTO DATA(ls_text) WITH TABLE KEY clsname = lv_class langu = mv_langu.
    IF sy-subrc <> 0.
      READ TABLE mt_class_texts INTO ls_text WITH TABLE KEY clsname = lv_class langu = 'E'.
    ENDIF.
    rv_text = ls_text-descript.
  ENDMETHOD.

  METHOD status_info.
    " is it still happening (same rule as for the other sections) ...
    lcl_util=>age_status( EXPORTING iv_date = is_group-last_datum IMPORTING ev_text = ev_text ev_class = ev_class ).

    " ... and was the code changed after the last dump? Then it may already be fixed.
    DATA(lv_name) = CONV trdir-name( COND string( WHEN is_group-include IS NOT INITIAL THEN is_group-include
                                                  ELSE is_group-program ) ).
    READ TABLE mt_trdir INTO DATA(ls_dir) WITH TABLE KEY name = lv_name.
    IF sy-subrc = 0 AND ls_dir-udat > is_group-last_datum.
      ev_text  = |{ ev_text } The code was changed on { ls_dir-udat DATE = USER }, after the last dump - it may | &&
                 |already be fixed. Watch whether it happens again.|.
      ev_class = `chg`.
    ENDIF.
  ENDMETHOD.

  METHOD ticket_text.
    " ready-to-copy text for a support ticket / e-mail
    rv_text = |Subject: Short dump { is_group-errid } in program { is_group-program }\n\n| &&
              |System / client : { sy-sysid } / { is_group-clients }\n| &&
              |Runtime error   : { is_group-errid } ({ is_advice-category })\n|.
    IF is_group-exc_class IS NOT INITIAL.
      rv_text = |{ rv_text }Exception class : { is_group-exc_class }\n|.
    ENDIF.
    rv_text = rv_text &&
              |Where           : program { is_group-program }, include { is_group-include }, line { is_group-line }\n| &&
              |How often       : { is_group-count } time(s), user(s): { is_group-user_list }\n| &&
              |First / last    : { is_group-first_seen } / { is_group-last_seen }\n\n| &&
              |What I was doing: <transaction, input values, which button - please fill in>\n| &&
              |Can I repeat it : <yes / no>\n\n| &&
              |Full details: transaction ST22, runtime error { is_group-errid }, { is_group-last_seen }.|.
  ENDMETHOD.

  METHOD source_snippet.
    DATA lt_src TYPE STANDARD TABLE OF char255 WITH EMPTY KEY.
    DATA lv_prog TYPE progname.
    IF iv_include IS INITIAL OR iv_line <= 0.
      RETURN.
    ENDIF.
    lv_prog = iv_include.
    READ REPORT lv_prog INTO lt_src.
    IF sy-subrc <> 0 OR lt_src IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_from) = nmax( val1 = 1 val2 = iv_line - 4 ).
    DATA(lv_to)   = nmin( val1 = lines( lt_src ) val2 = iv_line + 2 ).
    APPEND `<pre class="code">` TO rt_html.
    DATA lv_idx TYPE i.
    lv_idx = lv_from.
    WHILE lv_idx <= lv_to.
      DATA(lv_code) = h( lt_src[ lv_idx ] ).
      IF lv_idx = iv_line.
        APPEND |<span class="hit">{ lv_idx WIDTH = 6 ALIGN = RIGHT } &gt;&gt; { lv_code }</span>| TO rt_html.
      ELSE.
        APPEND |{ lv_idx WIDTH = 6 ALIGN = RIGHT }    { lv_code }| TO rt_html.
      ENDIF.
      lv_idx = lv_idx + 1.
    ENDWHILE.
    APPEND `</pre>` TO rt_html.
  ENDMETHOD.

  METHOD last_changed.
    " from the cache filled by prefetch
    READ TABLE mt_trdir INTO DATA(ls_dir) WITH TABLE KEY name = CONV trdir-name( iv_include ).
    IF sy-subrc = 0.
      rv_text = |last changed by { ls_dir-unam } on { ls_dir-udat DATE = USER }|.
    ENDIF.
  ENDMETHOD.

  METHOD h.
    rv_text = lcl_util=>h( iv_text ).
  ENDMETHOD.

  METHOD dump_html.
    " short dumps: overview table and one card per problem
    DATA lv_status TYPE string.
    DATA lv_scls TYPE string.
    DATA ls_g TYPE ty_group.

    APPEND `<h3>Overview</h3><table><tr><th>#</th><th>Severity</th><th>What went wrong</th><th>Error name</th>` &&
           `<th>Where</th><th>Times</th><th>Users</th><th>Last seen</th></tr>` TO rt_html.
    LOOP AT mt_groups INTO ls_g.
      APPEND |<tr><td><a href="#p{ ls_g-rank }">{ ls_g-rank }</a></td>| &&
             |<td><span class="badge { ls_g-severity }">{ ls_g-severity }</span></td>| &&
             |<td>{ h( ls_g-category ) }</td><td>{ h( ls_g-errid ) }</td>| &&
             |<td>{ h( ls_g-program ) }</td><td>{ ls_g-count }</td><td>{ ls_g-users }</td>| &&
             |<td>{ h( ls_g-last_seen ) }</td></tr>| TO rt_html.
    ENDLOOP.
    APPEND `</table>` TO rt_html.

    " one card per problem
    LOOP AT mt_groups INTO ls_g.
      DATA(ls_adv) = ls_g-advice.
      " SAP texts and repository data are read only here, for the problems actually shown
      DATA(lv_sap) = sap_short_text( ls_g-errid ).
      DATA(lv_expl) = sap_explanation( ls_g ).
      DATA(lv_exc) = exception_text( ls_g-exc_class ).
      status_info( EXPORTING is_group = ls_g IMPORTING ev_text = lv_status ev_class = lv_scls ).
      DATA(lv_who) = ls_adv-who.
      IF ls_g-own_code = abap_true.
        lv_who = |{ lv_who } This is your own (Z/Y) code, so your development team can fix it.|.
      ELSE.
        lv_who = |{ lv_who } The error happened in SAP standard code - first check whether your own data, | &&
                 |customizing or a user exit causes it, then search SAP Notes.|.
      ENDIF.

      APPEND |<div class="card" id="p{ ls_g-rank }">| TO rt_html.
      APPEND |<h2>{ ls_g-rank }. { h( ls_adv-category ) } <span class="badge { ls_g-severity }">{ ls_g-severity }</span></h2>| TO rt_html.
      APPEND |<div class="status { lv_scls }">{ h( lv_status ) }</div>| TO rt_html.
      APPEND `<table>` TO rt_html.
      APPEND |<tr><td class="k">What went wrong</td><td>{ h( ls_adv-meaning ) }</td></tr>| TO rt_html.
      IF lv_expl IS NOT INITIAL.
        APPEND |<tr><td class="k">SAP's explanation</td><td>{ h( lv_expl ) }</td></tr>| TO rt_html.
      ELSEIF lv_sap IS NOT INITIAL.
        APPEND |<tr><td class="k">SAP's description</td><td>{ h( lv_sap ) }</td></tr>| TO rt_html.
      ENDIF.
      APPEND |<tr><td class="k">Typical causes</td><td>{ h( ls_adv-causes ) }</td></tr>| TO rt_html.
      APPEND |<tr><td class="k">How often</td><td><b>{ ls_g-count } time(s)</b>, { ls_g-users } user(s): | &&
             |{ h( ls_g-user_list ) }<br>first { h( ls_g-first_seen ) }, last { h( ls_g-last_seen ) }| &&
             |<br>per day: { h( ls_g-day_list ) }</td></tr>| TO rt_html.
      APPEND |<tr><td class="k">Where</td><td>Program <b>{ h( ls_g-program ) }</b>, include { h( ls_g-include ) }, | &&
             |line { ls_g-line }<br>{ h( last_changed( ls_g-include ) ) }</td></tr>| TO rt_html.
      APPEND |<tr><td class="k">Who should act</td><td>{ h( lv_who ) }</td></tr>| TO rt_html.
      DATA(lv_tech) = |{ h( ls_g-errid ) }|.
      IF lv_sap IS NOT INITIAL.
        lv_tech = |{ lv_tech } - { h( lv_sap ) }|.
      ENDIF.
      IF ls_g-exc_class IS NOT INITIAL.
        lv_tech = |{ lv_tech }<br>Exception class { h( ls_g-exc_class ) }|.
        IF lv_exc IS NOT INITIAL.
          lv_tech = |{ lv_tech } ({ h( lv_exc ) })|.
        ENDIF.
      ENDIF.
      lv_tech = |{ lv_tech }<br>Client(s) { h( ls_g-clients ) } &middot; server(s) { h( ls_g-hosts ) }|.
      APPEND |<tr><td class="k">Technical details</td><td>{ lv_tech }</td></tr>| TO rt_html.
      APPEND `</table>` TO rt_html.

      APPEND |<div class="box user"><b>What you can do now</b><br>{ h( ls_adv-user_do ) }</div>| TO rt_html.
      APPEND |<div class="box tip"><b>How to fix it (developer / Basis)</b><br>{ h( ls_adv-steps ) }</div>| TO rt_html.
      IF ls_adv-example IS NOT INITIAL.
        APPEND `<h3>Example of a fix in ABAP</h3>` TO rt_html.
        APPEND |<pre class="code">{ h( ls_adv-example ) }</pre>| TO rt_html.
      ENDIF.

      DATA(lt_src) = source_snippet( iv_include = ls_g-include iv_line = ls_g-line ).
      IF lt_src IS NOT INITIAL.
        APPEND `<h3>Code at the failing line (marked &gt;&gt;)</h3>` TO rt_html.
        APPEND LINES OF lt_src TO rt_html.
      ENDIF.

      DATA(lv_search) = |{ ls_g-errid } { ls_g-program }|.
      IF ls_g-exc_class IS NOT INITIAL.
        lv_search = |{ lv_search } { ls_g-exc_class }|.
      ENDIF.
      APPEND |<p><b>Search SAP Notes</b> (me.sap.com) or the web for: <code>{ h( lv_search ) }</code>| &&
             |{ COND string( WHEN ls_g-own_code = abap_true THEN ` - for own code, SAP Notes help only if SAP functions are called.` ) }</p>| TO rt_html.

      APPEND `<h3>Text for a support ticket</h3>` TO rt_html.
      APPEND |<pre class="ticket">{ h( ticket_text( is_group = ls_g is_advice = ls_adv ) ) }</pre>| TO rt_html.
      APPEND |<div class="sub">Full details: transaction ST22, runtime error { h( ls_g-errid ) }, | &&
             |date { h( ls_g-last_seen ) }.</div></div>| TO rt_html.
    ENDLOOP.
  ENDMETHOD.

*----------------------------------------------------------------------*
* ALV and background list
*----------------------------------------------------------------------*
  METHOD show_alv.
    " ALV needs a flat table: copy the problems into short fields and set readable column titles
    DATA lt_alv TYPE tt_alv.
    LOOP AT mt_groups INTO DATA(ls_g).
      APPEND VALUE #( rank = ls_g-rank severity = ls_g-severity count = ls_g-count users = ls_g-users
                      errid = ls_g-errid category = ls_g-category program = ls_g-program
                      include = ls_g-include line = ls_g-line
                      own_code = COND #( WHEN ls_g-own_code = abap_true THEN 'Yes' ELSE 'No' )
                      first_seen = ls_g-first_seen last_seen = ls_g-last_seen ) TO lt_alv.
    ENDLOOP.
    TRY.
        cl_salv_table=>factory( IMPORTING r_salv_table = DATA(lo_alv) CHANGING t_table = lt_alv ).
        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        LOOP AT lo_cols->get( ) INTO DATA(ls_col).
          DATA(lv_text) = SWITCH scrtext_l( ls_col-columnname
            WHEN 'RANK' THEN 'No.' WHEN 'SEVERITY' THEN 'Severity' WHEN 'COUNT' THEN 'Times'
            WHEN 'USERS' THEN 'Users' WHEN 'ERRID' THEN 'Runtime error' WHEN 'CATEGORY' THEN 'What went wrong'
            WHEN 'PROGRAM' THEN 'Program' WHEN 'INCLUDE' THEN 'Include' WHEN 'LINE' THEN 'Line'
            WHEN 'OWN_CODE' THEN 'Own code' WHEN 'FIRST_SEEN' THEN 'First seen' WHEN 'LAST_SEEN' THEN 'Last seen'
            ELSE ls_col-columnname ).
          ls_col-r_column->set_long_text( lv_text ).
          ls_col-r_column->set_medium_text( CONV scrtext_m( lv_text ) ).
          ls_col-r_column->set_short_text( CONV scrtext_s( lv_text ) ).
        ENDLOOP.
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* lcl_report - the report as a whole
*   The only class that reads the selection screen. Creates the selected
*   sections with their settings, lets them analyse, and builds one output
*   from all of them: HTML page, ALV (short dumps) or spool list.
*----------------------------------------------------------------------*
CLASS lcl_report DEFINITION FINAL.
  PUBLIC SECTION.
    "! Analyse all selected areas and show the result
    METHODS run.

  PRIVATE SECTION.
    "! All selected sections, in output order
    DATA mt_sections TYPE STANDARD TABLE OF REF TO lif_section WITH EMPTY KEY.
    "! The short dump section is also needed directly, for the ALV output
    DATA mo_dumps TYPE REF TO lcl_dump_section.
    DATA mv_from TYPE sydatum.
    DATA mv_to TYPE sydatum.

    "! Create the selected sections from the selection screen
    METHODS create_sections.
    "! Whole HTML page: style, summary, all sections, glossary
    METHODS build_html
      RETURNING VALUE(rt_html) TYPE lcl_util=>tt_string.
    "! Plain list for background runs (spool)
    METHODS write_list.
ENDCLASS.

CLASS lcl_report IMPLEMENTATION.

  METHOD run.
    IF p_dump = abap_false AND p_slog = abap_false AND p_db = abap_false.
      MESSAGE 'Select at least one area to analyse.' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    create_sections( ).
    LOOP AT mt_sections INTO DATA(lo_section).
      lo_section->analyze( ).
    ENDLOOP.

    IF sy-batch = abap_true.
      write_list( ).
      RETURN.
    ENDIF.

    DATA(lt_html) = build_html( ).

    IF p_file IS NOT INITIAL.
      cl_gui_frontend_services=>gui_download(
        EXPORTING filename = p_file filetype = 'ASC' codepage = '4110'
        CHANGING  data_tab = lt_html
        EXCEPTIONS OTHERS = 1 ).
      IF sy-subrc = 0.
        MESSAGE |Report saved to { p_file }| TYPE 'S'.
      ELSE.
        MESSAGE |Could not save { p_file }| TYPE 'S' DISPLAY LIKE 'W'.
      ENDIF.
    ENDIF.

    IF p_alv = abap_true AND mo_dumps IS BOUND.
      " the ALV overview covers the short dumps only
      IF mo_dumps->has_problems( ) = abap_false.
        MESSAGE 'No short dumps found for this selection - good news.' TYPE 'S'.
      ELSE.
        mo_dumps->show_alv( ).
      ENDIF.
    ELSE.
      cl_abap_browser=>show_html(
        title       = 'SAP problem report'
        html_string = concat_lines_of( table = lt_html )
        size        = cl_abap_browser=>xlarge
        context_menu = abap_true ).
    ENDIF.
  ENDMETHOD.

  METHOD create_sections.
    " period: first line of the date selection (default: last 7 days)
    READ TABLE s_datum INTO DATA(ls_range) INDEX 1.
    IF sy-subrc = 0.
      mv_from = ls_range-low.
      mv_to   = ls_range-high.
    ENDIF.
    IF mv_to IS INITIAL.
      mv_to = COND #( WHEN mv_from IS INITIAL THEN sy-datum ELSE mv_from ).
    ENDIF.

    " each section gets its settings here, so no section depends on the selection screen
    IF p_dump = abap_true.
      mo_dumps = NEW #( it_dates    = s_datum[]
                        it_users    = s_uname[]
                        it_errids   = s_errid[]
                        it_clients  = s_mandt[]
                        it_hosts    = s_ahost[]
                        iv_own_only = p_cust
                        iv_langu    = p_lang ).
      APPEND mo_dumps TO mt_sections.
    ENDIF.
    IF p_slog = abap_true.
      APPEND NEW lcl_syslog( iv_from         = mv_from
                             iv_to           = mv_to
                             iv_include_info = p_slinf
                             it_users        = s_uname[]
                             it_clients      = s_mandt[]
                             iv_langu        = p_lang ) TO mt_sections.
    ENDIF.
    IF p_db = abap_true.
      APPEND NEW lcl_dbcheck( ) TO mt_sections.
    ENDIF.
  ENDMETHOD.

  METHOD write_list.
    DATA lv_text TYPE string.
    lv_text = |SAP problem report { sy-sysid }, { mv_from DATE = USER } - { mv_to DATE = USER }|.
    WRITE / lv_text.
    LOOP AT mt_sections INTO DATA(lo_section).
      SKIP.
      lo_section->write_list( ).
    ENDLOOP.
  ENDMETHOD.

  METHOD build_html.
    " One self-contained HTML page (inline CSS) - shown in cl_abap_browser or saved as a file.
    " Page frame only; the content of each area comes from its section object.
    APPEND `<html><head><meta charset="utf-8"><style>` TO rt_html.
    APPEND `body{font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#222;margin:20px;max-width:1100px}` TO rt_html.
    APPEND `h1{font-size:22px;margin-bottom:4px} h2{font-size:17px;margin:0 0 6px 0} h3{font-size:15px;margin:14px 0 4px 0}` TO rt_html.
    APPEND `.sub{color:#666;margin-bottom:16px} table{border-collapse:collapse;width:100%}` TO rt_html.
    APPEND `th,td{border-bottom:1px solid #ddd;padding:6px 8px;text-align:left;vertical-align:top}` TO rt_html.
    APPEND `th{background:#f3f4f6} .card{border:1px solid #ddd;border-radius:8px;padding:14px 16px;margin:16px 0}` TO rt_html.
    APPEND `.High{background:#fde2e1;color:#9b1c1c} .Medium{background:#fef3c7;color:#92400e} .Low{background:#e0f2fe;color:#075985}` TO rt_html.
    APPEND `.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;font-weight:600}` TO rt_html.
    APPEND `.k{color:#555;width:170px} .code{background:#f8f8f8;border:1px solid #e5e5e5;padding:8px;font-size:12px;overflow:auto}` TO rt_html.
    APPEND `.hit{background:#fde68a;font-weight:600} .box{padding:8px 10px;margin:8px 0;border-left:4px solid #999}` TO rt_html.
    APPEND `.user{background:#eff6ff;border-color:#2563eb} .tip{background:#f0fdf4;border-color:#16a34a} .help{background:#f9fafb;border-color:#6b7280}` TO rt_html.
    APPEND `.status{padding:6px 10px;border-radius:6px;margin:4px 0 10px 0} .act{background:#fde2e1;color:#9b1c1c}` TO rt_html.
    APPEND `.old{background:#f3f4f6;color:#444} .chg{background:#fef3c7;color:#92400e}` TO rt_html.
    APPEND `.ticket{background:#fff;border:1px dashed #999;padding:8px;font-size:12px} code{background:#f3f4f6;padding:1px 4px}` TO rt_html.
    APPEND `.Info{background:#f3f4f6;color:#444} .ok{background:#f0fdf4;border-color:#16a34a} .warnbox{background:#fef3c7;border-color:#d97706}` TO rt_html.
    APPEND `h2.sec{font-size:20px;margin:32px 0 8px 0;padding-bottom:4px;border-bottom:2px solid #333}` TO rt_html.
    APPEND `.bar{display:inline-block;width:110px;height:10px;background:#e5e7eb;border-radius:5px;vertical-align:middle;overflow:hidden}` TO rt_html.
    APPEND `.fill{display:block;height:10px} .good{background:#16a34a} .warn{background:#d97706} .crit{background:#dc2626}` TO rt_html.
    APPEND `</style></head><body>` TO rt_html.

    APPEND |<h1>SAP problem report - system { sy-sysid }</h1>| TO rt_html.
    APPEND |<div class="sub">Period { mv_from DATE = USER } to { mv_to DATE = USER } &middot; | &&
           |created { sy-datum DATE = USER } { sy-uzeit TIME = USER } by { sy-uname }</div>| TO rt_html.

    " at a glance: one line per section
    APPEND `<div class="box help"><b>At a glance</b><br>` TO rt_html.
    LOOP AT mt_sections INTO DATA(lo_section).
      APPEND |{ lo_section->summary_html( ) }<br>| TO rt_html.
    ENDLOOP.
    APPEND `</div>` TO rt_html.

    " how to read this report
    APPEND `<div class="box help"><b>How to read this report</b><br>` TO rt_html.
    APPEND `Every problem is explained in plain words, with <b>what you can do right now</b> (blue box) and <b>how a ` &&
           `developer or the Basis team can fix it</b> (green box). Short dumps also come with a text you can copy ` &&
           `into a support ticket. Identical problems are explained only once and counted.<br>` TO rt_html.
    APPEND `Severity: <span class="badge High">High</span> serious or frequent - start here. ` &&
           `<span class="badge Medium">Medium</span> should be fixed. <span class="badge Low">Low</span> ` &&
           `rare or harmless. <span class="badge Info">Info</span> for information only.</div>` TO rt_html.

    " the sections: short dumps, system log, database (as selected)
    LOOP AT mt_sections INTO lo_section.
      APPEND LINES OF lo_section->get_html( ) TO rt_html.
    ENDLOOP.

    " glossary
    APPEND `<h2 class="sec">Words used in this report</h2><table>` TO rt_html.
    APPEND `<tr><td class="k">Short dump</td><td>The error record SAP writes when a program crashes. Shown in transaction ST22.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Runtime error</td><td>SAP's technical name for the kind of crash, e.g. COMPUTE_INT_ZERODIVIDE.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Exception class</td><td>Technical name of the error object (CX_...). Developers use it to catch the error.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Program / include / line</td><td>Where in the code the crash happened. An include is a part of a program.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Own code (Z/Y)</td><td>Developed by your company (names start with Z or Y). Everything else is SAP standard.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">SAP Note</td><td>An official correction or explanation from SAP, searchable on me.sap.com.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Basis</td><td>The team that runs the SAP system technically (servers, database, connections).</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Background job</td><td>A program run by the system without a screen (F9 / SM36), without the online time limit.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">System log</td><td>SM21: the log of important technical events (errors, restarts, configuration problems).</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Work process</td><td>One of the worker programs of the SAP system that run the users' requests (SM50).</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Profile parameter</td><td>A configuration setting of the SAP system, maintained by Basis (RZ10 / RZ11).</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Data space / transaction log</td><td>The database keeps the tables in the data space; every change is first written to the transaction log.</td></tr>` TO rt_html.
    APPEND `<tr><td class="k">Device</td><td>A file on disk that holds a part of the database (SAP ASE / Sybase term).</td></tr>` TO rt_html.
    APPEND `</table>` TO rt_html.

    APPEND `</body></html>` TO rt_html.
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
* ABAP Unit tests (Ctrl+Shift+F10 in SE80/ADT, or Program > Test > Unit Test)
*   Only the logic is tested - no database reads, no SM21 access.
*----------------------------------------------------------------------*
CLASS ltc_util DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS add_unique_skips_duplicates FOR TESTING.
    METHODS add_unique_respects_max FOR TESTING.
    METHODS age_status_today_is_active FOR TESTING.
    METHODS age_status_old FOR TESTING.
    METHODS bar_levels FOR TESTING.
ENDCLASS.

CLASS ltc_util IMPLEMENTATION.

  METHOD add_unique_skips_duplicates.
    DATA lt_list TYPE lcl_util=>tt_string.
    lcl_util=>add_unique( EXPORTING iv_value = `A` CHANGING ct_list = lt_list ).
    lcl_util=>add_unique( EXPORTING iv_value = `A` CHANGING ct_list = lt_list ).
    lcl_util=>add_unique( EXPORTING iv_value = `  ` CHANGING ct_list = lt_list ).
    lcl_util=>add_unique( EXPORTING iv_value = `B` CHANGING ct_list = lt_list ).
    cl_abap_unit_assert=>assert_equals( act = lt_list exp = VALUE lcl_util=>tt_string( ( `A` ) ( `B` ) )
                                        msg = 'duplicates and empty values must be skipped' ).
  ENDMETHOD.

  METHOD add_unique_respects_max.
    DATA lt_list TYPE lcl_util=>tt_string.
    lcl_util=>add_unique( EXPORTING iv_value = `A` iv_max = 2 CHANGING ct_list = lt_list ).
    lcl_util=>add_unique( EXPORTING iv_value = `B` iv_max = 2 CHANGING ct_list = lt_list ).
    lcl_util=>add_unique( EXPORTING iv_value = `C` iv_max = 2 CHANGING ct_list = lt_list ).
    cl_abap_unit_assert=>assert_equals( act = lines( lt_list ) exp = 2 msg = 'list must stop at iv_max' ).
  ENDMETHOD.

  METHOD age_status_today_is_active.
    lcl_util=>age_status( EXPORTING iv_date = sy-datum IMPORTING ev_class = DATA(lv_class) ).
    cl_abap_unit_assert=>assert_equals( act = lv_class exp = `act` ).
  ENDMETHOD.

  METHOD age_status_old.
    DATA lv_date TYPE d.
    lv_date = sy-datum - 5.
    lcl_util=>age_status( EXPORTING iv_date = lv_date IMPORTING ev_text = DATA(lv_text) ev_class = DATA(lv_class) ).
    cl_abap_unit_assert=>assert_equals( act = lv_class exp = `old` ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_text exp = '*5 days*' ).
  ENDMETHOD.

  METHOD bar_levels.
    cl_abap_unit_assert=>assert_char_cp( act = lcl_util=>bar( iv_pct = 96 iv_warn = 85 iv_crit = 95 ) exp = '*crit*' ).
    cl_abap_unit_assert=>assert_char_cp( act = lcl_util=>bar( iv_pct = 90 iv_warn = 85 iv_crit = 95 ) exp = '*warn*' ).
    cl_abap_unit_assert=>assert_char_cp( act = lcl_util=>bar( iv_pct = 10 iv_warn = 85 iv_crit = 95 ) exp = '*good*' ).
    cl_abap_unit_assert=>assert_char_cp( act = lcl_util=>bar( iv_pct = 150 iv_warn = 85 iv_crit = 95 )
                                         exp = '*width:100%*' ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS ltc_dump_section DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_dump_section.
    METHODS setup.
    "! dump with error, program/include and line - the grouping key
    METHODS dump
      IMPORTING iv_errid       TYPE string
                iv_line        TYPE i
                iv_user        TYPE syuname DEFAULT 'DEVELOPER'
      RETURNING VALUE(rs_dump) TYPE lcl_dump_section=>ty_dump.
    METHODS parse_flist_real_dump FOR TESTING.
    METHODS parse_flist_garbage FOR TESTING.
    METHODS own_code FOR TESTING.
    METHODS identical_dumps_grouped FOR TESTING.
    METHODS frequent_error_is_high FOR TESTING.
    METHODS advice_mapping FOR TESTING.
ENDCLASS.

CLASS ltc_dump_section IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( iv_langu = 'E' ).
  ENDMETHOD.

  METHOD dump.
    rs_dump = VALUE #( datum = sy-datum uzeit = '120000' uname = iv_user mandt = '001'
                       errid = iv_errid program = `ZPROG` include = `ZPROG` line = iv_line ).
  ENDMETHOD.

  METHOD parse_flist_real_dump.
    " FLIST of a real dump of ZDUMP_TEST (taken from SNAP_BEG)
    DATA ls_dump TYPE lcl_dump_section=>ty_dump.
    mo_cut->parse_flist(
      EXPORTING iv_flist = `FC022COMPUTE_INT_ZERODIVIDEAP010ZDUMP_TESTAI010ZDUMP_TESTAL00214XC016CX_SY_ZERODIVIDE`
      CHANGING  cs_dump  = ls_dump ).
    cl_abap_unit_assert=>assert_equals( act = ls_dump-errid     exp = `COMPUTE_INT_ZERODIVIDE` ).
    cl_abap_unit_assert=>assert_equals( act = ls_dump-program   exp = `ZDUMP_TEST` ).
    cl_abap_unit_assert=>assert_equals( act = ls_dump-include   exp = `ZDUMP_TEST` ).
    cl_abap_unit_assert=>assert_equals( act = ls_dump-line      exp = 14 ).
    cl_abap_unit_assert=>assert_equals( act = ls_dump-exc_class exp = `CX_SY_ZERODIVIDE` ).
  ENDMETHOD.

  METHOD parse_flist_garbage.
    " must neither dump nor fill fields with nonsense
    DATA ls_dump TYPE lcl_dump_section=>ty_dump.
    mo_cut->parse_flist( EXPORTING iv_flist = `XYZ-not-a-flist` CHANGING cs_dump = ls_dump ).
    cl_abap_unit_assert=>assert_initial( act = ls_dump ).
  ENDMETHOD.

  METHOD own_code.
    cl_abap_unit_assert=>assert_true( act = mo_cut->is_own_code( `ZDUMP_TEST` ) ).
    cl_abap_unit_assert=>assert_true( act = mo_cut->is_own_code( `SAPLZFG` ) ).
    cl_abap_unit_assert=>assert_true( act = mo_cut->is_own_code( `/ABC/CL_X` ) ).
    cl_abap_unit_assert=>assert_false( act = mo_cut->is_own_code( `SAPMV45A` ) ).
    cl_abap_unit_assert=>assert_false( act = mo_cut->is_own_code( `RSPARAM` ) ).
  ENDMETHOD.

  METHOD identical_dumps_grouped.
    " two identical dumps (same line) + one at another line = 2 problems, the double one first
    mo_cut->mt_dumps = VALUE #( ( dump( iv_errid = `COMPUTE_INT_ZERODIVIDE` iv_line = 14 iv_user = 'A' ) )
                                ( dump( iv_errid = `COMPUTE_INT_ZERODIVIDE` iv_line = 14 iv_user = 'B' ) )
                                ( dump( iv_errid = `COMPUTE_INT_ZERODIVIDE` iv_line = 20 ) ) ).
    mo_cut->build_groups( ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_groups ) exp = 2 ).
    DATA(ls_first) = mo_cut->mt_groups[ 1 ].
    cl_abap_unit_assert=>assert_equals( act = ls_first-count exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_first-users exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_first-line  exp = 14 ).
    cl_abap_unit_assert=>assert_equals( act = ls_first-rank  exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_first-category exp = `Calculation error` ).
  ENDMETHOD.

  METHOD frequent_error_is_high.
    " TIME_OUT (weight 2) + 10 times (+2) + 3 users (+1) = 5 -> High
    DATA lv_user TYPE syuname.
    DO 10 TIMES.
      lv_user = |U{ sy-index MOD 3 }|.
      APPEND dump( iv_errid = `TIME_OUT` iv_line = 1 iv_user = lv_user ) TO mo_cut->mt_dumps.
    ENDDO.
    mo_cut->build_groups( ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_groups ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->mt_groups[ 1 ]-severity exp = `High` ).
  ENDMETHOD.

  METHOD advice_mapping.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->get_advice( `COMPUTE_INT_ZERODIVIDE` )-category
                                        exp = `Calculation error` ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->get_advice( `TIME_OUT` )-category
                                        exp = `Program ran too long` ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->get_advice( `ZZ_SOMETHING_NEW` )-category
                                        exp = `Other runtime error` ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS ltc_syslog DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_syslog.
    METHODS setup.
    "! one SM21 entry of a work process (iv_proc), with SM21 priority (iv_prio, e.g. RA = red)
    METHODS entry
      IMPORTING iv_proc         TYPE rslgselnum
                iv_msgid        TYPE rslgno
                iv_prio         TYPE rslgnkkd
                iv_text         TYPE string
                iv_user         TYPE syuname DEFAULT 'DEVELOPER'
      RETURNING VALUE(rs_entry) TYPE rslgentry.
    "! group of a message ID after process_entries (initial if there is none)
    METHODS group
      IMPORTING iv_msgid        TYPE rslgno
      RETURNING VALUE(rs_group) TYPE lcl_syslog=>ty_group.
    METHODS continuation_attached FOR TESTING.
    METHODS continuation_of_hidden_dropped FOR TESTING.
    METHODS continuation_other_process FOR TESTING.
    METHODS severity_from_priority FOR TESTING.
    METHODS user_filter FOR TESTING.
ENDCLASS.

CLASS ltc_syslog IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( iv_from = sy-datum iv_to = sy-datum iv_include_info = abap_false iv_langu = 'E' ).
  ENDMETHOD.

  METHOD entry.
    rs_entry = VALUE #( zdate = sy-datum ztime = '120000' instance = 'host_NPL_00' processid = iv_proc
                        messageid = iv_msgid monbew = iv_prio text = iv_text zuser = iv_user client = '001' ).
  ENDMETHOD.

  METHOD group.
    READ TABLE mo_cut->mt_groups INTO rs_group WITH TABLE KEY by_msgid COMPONENTS msgid = iv_msgid.
  ENDMETHOD.

  METHOD continuation_attached.
    mo_cut->process_entries( VALUE #(
      ( entry( iv_proc = '001' iv_msgid = 'AB0' iv_prio = 'RA' iv_text = `Runtime error "X" occurred.` ) )
      ( entry( iv_proc = '001' iv_msgid = 'AB1' iv_prio = 'WH' iv_text = `> Short dump "1" created.` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_groups ) exp = 1
                                        msg = 'continuation line must not become an own group' ).
    cl_abap_unit_assert=>assert_equals( act = group( 'AB0' )-details
                                        exp = VALUE lcl_util=>tt_string( ( `Short dump "1" created.` ) ) ).
  ENDMETHOD.

  METHOD continuation_of_hidden_dropped.
    " information message is hidden -> its continuation line must be dropped as well
    mo_cut->process_entries( VALUE #(
      ( entry( iv_proc = '002' iv_msgid = 'Q02' iv_prio = 'WH' iv_text = `Stop Workp. 6` ) )
      ( entry( iv_proc = '002' iv_msgid = 'Q03' iv_prio = 'WH' iv_text = `> detail` ) ) ) ).
    cl_abap_unit_assert=>assert_initial( act = mo_cut->mt_groups ).
  ENDMETHOD.

  METHOD continuation_other_process.
    " another work process writes in between - the detail still belongs to work process 001
    mo_cut->process_entries( VALUE #(
      ( entry( iv_proc = '001' iv_msgid = 'AB0' iv_prio = 'RA' iv_text = `Runtime error "X" occurred.` ) )
      ( entry( iv_proc = '002' iv_msgid = 'BY2' iv_prio = 'RA' iv_text = `Database error 281` ) )
      ( entry( iv_proc = '001' iv_msgid = 'AB1' iv_prio = 'WH' iv_text = `> dump detail` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( group( 'AB0' )-details ) exp = 1 ).
    cl_abap_unit_assert=>assert_initial( act = group( 'BY2' )-details ).
  ENDMETHOD.

  METHOD severity_from_priority.
    mo_cut->process_entries( VALUE #(
      ( entry( iv_proc = '001' iv_msgid = 'BY2' iv_prio = 'RA' iv_text = `Database error 281` ) )
      ( entry( iv_proc = '002' iv_msgid = 'IM1' iv_prio = 'GR' iv_text = `ICM started on host x` ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = group( 'BY2' )-severity exp = `High` ).
    cl_abap_unit_assert=>assert_equals( act = group( 'IM1' )-severity exp = `Info`
                                        msg = 'normal start-up message must be information only' ).
  ENDMETHOD.

  METHOD user_filter.
    mo_cut = NEW #( iv_from = sy-datum iv_to = sy-datum iv_include_info = abap_false iv_langu = 'E'
                    it_users = VALUE #( ( sign = 'I' option = 'EQ' low = 'ALICE' ) ) ).
    mo_cut->process_entries( VALUE #(
      ( entry( iv_proc = '001' iv_msgid = 'BY2' iv_prio = 'RA' iv_text = `Database error` iv_user = 'BOB' ) )
      ( entry( iv_proc = '002' iv_msgid = 'D01' iv_prio = 'RA' iv_text = `Transaction canceled` iv_user = 'ALICE' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_groups ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->mt_groups[ 1 ]-msgid exp = 'D01' ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
CLASS ltc_dbcheck DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    DATA mo_cut TYPE REF TO lcl_dbcheck.
    METHODS setup.
    METHODS data_92_pct_is_medium FOR TESTING.
    METHODS data_96_pct_is_high FOR TESTING.
    METHODS full_log_is_high FOR TESTING.
    METHODS log_never_backed_up FOR TESTING.
    METHODS system_db_ignored FOR TESTING.
    METHODS table_hints FOR TESTING.
    METHODS percent FOR TESTING.
ENDCLASS.

CLASS ltc_dbcheck IMPLEMENTATION.

  METHOD setup.
    mo_cut = NEW #( ).
    mo_cut->mv_sapdb = `NPL`.
  ENDMETHOD.

  METHOD data_92_pct_is_medium.
    mo_cut->mt_db = VALUE #( ( name = 'NPL' data_mb = 1000 data_free = 80 log_mb = 100 log_free = 90 trunc = 1 ) ).
    mo_cut->evaluate( ).
    " findings: data space (Medium) + automatic log truncation (Low), worst first
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_findings ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->mt_findings[ 1 ]-severity exp = `Medium` ).
    cl_abap_unit_assert=>assert_char_cp( act = mo_cut->mt_findings[ 1 ]-title exp = '*data space 92%*' ).
  ENDMETHOD.

  METHOD data_96_pct_is_high.
    mo_cut->mt_db = VALUE #( ( name = 'NPL' data_mb = 1000 data_free = 40 log_mb = 100 log_free = 90 trunc = 1 ) ).
    mo_cut->evaluate( ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->mt_findings[ 1 ]-severity exp = `High` ).
  ENDMETHOD.

  METHOD full_log_is_high.
    " log backup today -> only the full log is a finding
    mo_cut->mt_db = VALUE #( ( name = 'NPL' data_mb = 1000 data_free = 900 log_mb = 100 log_free = 5
                               dump_date = sy-datum ) ).
    mo_cut->evaluate( ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_findings ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->mt_findings[ 1 ]-severity exp = `High` ).
    cl_abap_unit_assert=>assert_char_cp( act = mo_cut->mt_findings[ 1 ]-title exp = '*transaction log 95%*' ).
  ENDMETHOD.

  METHOD log_never_backed_up.
    mo_cut->mt_db = VALUE #( ( name = 'NPL' data_mb = 1000 data_free = 900 log_mb = 100 log_free = 90 ) ).
    mo_cut->evaluate( ).
    cl_abap_unit_assert=>assert_equals( act = lines( mo_cut->mt_findings ) exp = 1 ).
    cl_abap_unit_assert=>assert_char_cp( act = mo_cut->mt_findings[ 1 ]-title exp = '*never been backed up*' ).
  ENDMETHOD.

  METHOD system_db_ignored.
    " internal ASE databases are listed but not judged
    mo_cut->mt_db = VALUE #( ( name = 'master' data_mb = 300 data_free = 3 mixed = 1 ) ).
    mo_cut->evaluate( ).
    cl_abap_unit_assert=>assert_initial( act = mo_cut->mt_findings ).
  ENDMETHOD.

  METHOD table_hints.
    mo_cut->table_hint( EXPORTING iv_name = 'SNAP' IMPORTING ev_text = DATA(lv_text) ev_cleanup = DATA(lv_cleanup) ).
    cl_abap_unit_assert=>assert_true( act = lv_cleanup ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_text exp = '*RSSNAPDL*' ).
    mo_cut->table_hint( EXPORTING iv_name = 'REPOSRC' IMPORTING ev_text = lv_text ev_cleanup = lv_cleanup ).
    cl_abap_unit_assert=>assert_false( act = lv_cleanup ).
    cl_abap_unit_assert=>assert_char_cp( act = lv_text exp = '*normal*' ).
  ENDMETHOD.

  METHOD percent.
    cl_abap_unit_assert=>assert_equals( act = mo_cut->pct( iv_total = 0 iv_free = 0 ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = mo_cut->pct( iv_total = 200 iv_free = 50 ) exp = 75 ).
  ENDMETHOD.

ENDCLASS.

*----------------------------------------------------------------------*
START-OF-SELECTION.
  NEW lcl_report( )->run( ).
