*&---------------------------------------------------------------------*
*& Report ZDUMP_TEST
*&---------------------------------------------------------------------*
*& Test helper for ZDUMP_EXPLAINER: always dumps with
*& COMPUTE_INT_ZERODIVIDE at the same line. Run it twice to get two
*& identical dumps.
*&---------------------------------------------------------------------*
REPORT zdump_test.

DATA gv_zero   TYPE i.
DATA gv_result TYPE i.

START-OF-SELECTION.
  gv_result = 1 / gv_zero.
  WRITE / gv_result.
