# Replacing BAPI_ALM_ORDER_MAINTAIN with the RAP component class

Reference for migrating component creation in `ZPP_I_COLLECTIVE_PROD_ORD_CLS`
(`LCL_MAIN=>CREATE`) from `BAPI_ALM_ORDER_MAINTAIN` to the RAP business object
`I_PRODUCTIONORDERTP` via the wrapper class `ZCL_PP_PRODUCTION_ORDER`
(repo copy: `ZCL_GILGAR_PROD_ORDER_COMP`).

The class is **not** changed. Internal IDs are resolved on the caller side, and all
component fields are preserved using `create_components_full`.

## Why
- SAP Note 1694267: use the RAP BO for production orders instead of BAPI_ALM_ORDER_MAINTAIN.
- `BAPI_ALM_ORDER_MAINTAIN` uses external keys (`AUFNR`, operation `VORNR`).
  The RAP BO needs internal keys: `OrderInternalID` + `OrderOperationInternalID`.

## What to replace
Inside `LOOP AT LT_ONLINE_OFLINE INTO DATA(LS_ONLINE_OFLINE)`, remove the whole block
from `FREE LV_NUMC.` / `DATA: LT_METHODS ...` down to
`FREE: LT_METHODS, LT_COMPONENTS, LT_COMPONENTS_UP.` — i.e. the
`CO_ZF_DATA_RESET_COMPLETE` + `BAPI_ALM_ORDER_MAINTAIN` + `LT_ALM_ORDER_RETURN`
handling — and paste the block below in its place. It consumes the already-built
`LT_RESB` and `LS_ONLINE_OFLINE-AUFNR`.

## Replacement block

```abap
*--- Resolve RAP internal IDs from the TP views (one SELECT for all orders) --*
* NOTE: OrderInternalID exists ONLY on the *TP* views. Using the plain
* I_ProductionOrder / I_ProductionOrderOperation views gives
* "Unknown column name ORDERINTERNALID".
SELECT op~OrderInternalID,
       op~OrderOperationInternalID,
       op~ProductionOrderOperation AS operationnumber,   "VORNR (NOT OperationNumber)
       hdr~ProductionOrder         AS aufnr              "confirmed: element ProductionOrder
  FROM @LT_ONLINE_OFLINE AS ofl
  INNER JOIN I_ProductionOrderTP          AS hdr ON hdr~ProductionOrder = ofl~aufnr
  INNER JOIN I_ProductionOrderOperationTP AS op  ON op~OrderInternalID  = hdr~OrderInternalID
  INTO TABLE @DATA(LT_OP_MAP).
SORT LT_OP_MAP BY aufnr operationnumber.
* Simpler alternative: if I_ProductionOrderOperationTP itself exposes the order
* number, drop the header join and filter the operation TP view directly.

*--- Build the full-data component table -------------------------------------*
DATA LT_RAP_COMP TYPE ZCL_PP_PRODUCTION_ORDER=>TT_COMPONENT_FULL.
CLEAR LT_RAP_COMP.

LOOP AT LT_RESB INTO LS_RESB WHERE VORNR NE '0010'.

  READ TABLE LT_OP_MAP INTO DATA(LS_OP)
       WITH KEY aufnr           = LS_ONLINE_OFLINE-AUFNR
                operationnumber = LS_RESB-VORNR BINARY SEARCH.
  CHECK SY-SUBRC = 0.

  DATA(LV_QTY) = COND #( WHEN LS_RESB-MEINS = 'ST'
                         THEN CEIL( LS_RESB-BDMNG )
                         ELSE LS_RESB-BDMNG ).

  DATA LV_STGE TYPE LGORT_D.
  CLEAR LV_STGE.
  PERFORM GET_LGORT USING LS_RESB-AUFPL LS_RESB-VORNR CHANGING LV_STGE.

  APPEND VALUE #(
    order_internal_id     = LS_OP-OrderInternalID
    operation_internal_id = LS_OP-OrderOperationInternalID
    data = VALUE #( material                   = LS_RESB-MATNR
                    plant                      = LS_RESB-WERKS
                    storagelocation            = LV_STGE          "*** confirm field exists
                    billofmaterialitemcategory = LS_RESB-POSTP
                    requiredquantity           = LV_QTY
                    baseunit                   = LS_RESB-MEINS
                    requirementdate            = LS_RESB-BDTER )   "*** confirm field exists
  ) TO LT_RAP_COMP.

ENDLOOP.

*--- Call the RAP wrapper class and surface messages on the ALV --------------*
IF LT_RAP_COMP IS NOT INITIAL.

  " Tier-1 dump fix: clear the classic order context (locks + CO buffer/status
  " left by BAPI_PRODORD_* / CO_SE_PRODORD_CHANGE) so the standard MFG-order RAP
  " handler (CL_PPRAP_MFGORDER_BILHDLR) can load/lock the order without ASSERTION_FAILED.
  CALL FUNCTION 'DEQUEUE_ALL'.
  CALL FUNCTION 'CO_ZF_DATA_RESET_COMPLETE'
    EXPORTING i_no_ocm_reset = ' ' i_status_reset = 'X'.

  DATA(LO_PO) = NEW ZCL_PP_PRODUCTION_ORDER( ).
  LO_PO->CREATE_COMPONENTS_FULL(
    EXPORTING IT_COMPONENT = LT_RAP_COMP
              IV_COMMIT    = ABAP_TRUE
    IMPORTING ET_MESSAGE   = DATA(LT_MSG)
              EV_SUCCESS   = DATA(LV_OK) ).

  READ TABLE GT_ALV ASSIGNING FIELD-SYMBOL(<LFS_ALV>)
       WITH KEY ORDER_NUMBER = LS_ONLINE_OFLINE-AUFNR.
  IF SY-SUBRC = 0.
    IF LV_OK = ABAP_TRUE.
      MESSAGE ID 'ZPP_1' TYPE 'S' NUMBER '009' INTO DATA(LV_MES).
      <LFS_ALV>-MESSAGE = |{ <LFS_ALV>-MESSAGE }{ LV_MES }|.
    ELSE.
      <LFS_ALV>-ICON    = GC_RED.
      <LFS_ALV>-MESSAGE = |{ <LFS_ALV>-MESSAGE }{ VALUE #( LT_MSG[ severity = 'E' ]-text OPTIONAL ) }|.
    ENDIF.
  ENDIF.

ENDIF.
```

## Field names (verified / to confirm)
Use the **TP** views (`OrderInternalID` exists only there).
- `I_ProductionOrderTP`: `OrderInternalID` and `ProductionOrder` (order number) —
  **confirmed** via the table field list (technical name PRODUCTIONORDER).
- `I_ProductionOrderOperationTP`: `OrderInternalID`, `OrderOperationInternalID`
  (confirmed). The operation number is **`ProductionOrderOperation`** (VORNR) —
  `OperationNumber` does NOT exist here. Confirm in your release with SE16 on
  `I_PRODUCTIONORDEROPERATIONTP` (the same field-list view used for the header).
- Component `%data`: type `data-` + Ctrl+Space — confirm `storagelocation` and
  `requirementdate` exist; if not, omit those two lines. The others
  (material/plant/billofmaterialitemcategory/requiredquantity/baseunit) are proven.

## Notes
- `create_components_full( iv_commit = abap_true )` runs `MODIFY ENTITIES` +
  `COMMIT ENTITIES` internally. The later classic `MODIFY ZPP_T_ONLINE_ORD` /
  `COMMIT WORK` stays as is (separate LUW, runs afterwards).
- The operations are created/committed earlier in the same method
  (`CO_SE_PRODORD_CHANGE` + commit), so the CDS read returns them. If buffering bites,
  add a short `WAIT` or read the operations via `READ ENTITIES OF i_productionordertp`.
- Both internal IDs come straight from `I_ProductionOrderOperationTP`, so no assumption
  about `OrderInternalID = AUFNR` is made.

## Troubleshooting: ASSERTION_FAILED in CL_PPRAP_MFGORDER_BILHDLR
A bare `ASSERT` in the standard MFG-order RAP handler (component PP-SFC) happens when the
RAP BO is called right after classic order processing (`BAPI_PRODORD_*`,
`CO_SE_PRODORD_CHANGE`) in the same session — the order is still locked/buffered
classically when the RAP handler tries to load and lock it. **Confirmed by isolation: the
class works standalone from SE24 and only dumps when called inside the program**, i.e. the
keys/fields are correct; it is a same-session context conflict.

**Tier 1 (applied above):** before the RAP call, release locks and reset the classic order
buffer:
```abap
CALL FUNCTION 'DEQUEUE_ALL'.
CALL FUNCTION 'CO_ZF_DATA_RESET_COMPLETE'
  EXPORTING i_no_ocm_reset = ' ' i_status_reset = 'X'.
```

**Tier 2 (if Tier 1 still dumps): run the RAP create in a fresh session via STARTING NEW TASK.**
Wrap "resolve IDs + call the class" in an RFC-enabled FM `Z_PP_CREATE_ORDER_COMPONENTS`
(DDIC-typed params: `IV_ORDER TYPE AUFNR`, a flat `IT_COMP` table type, `EV_SUCCESS`,
`ET_MESSAGE`). The FM resolves the internal IDs from `I_ManufacturingOrderOperation`, calls
`create_components_full( iv_commit = abap_true )` and returns messages. Call it async and
collect the result:
```abap
CALL FUNCTION 'DEQUEUE_ALL'.                 "main session still holds the classic lock
DATA gv_rap_done TYPE abap_bool.
CALL FUNCTION 'Z_PP_CREATE_ORDER_COMPONENTS'
  STARTING NEW TASK 'RAPCOMP'
  PERFORMING receive_rap_result ON END OF TASK
  EXPORTING iv_order = ls_online_ofline-aufnr
            it_comp  = lt_comp_ext.
WAIT UNTIL gv_rap_done = abap_true UP TO 30 SECONDS.

FORM receive_rap_result USING p_task TYPE clike.
  RECEIVE RESULTS FROM FUNCTION 'Z_PP_CREATE_ORDER_COMPONENTS'
    IMPORTING ev_success = gv_rap_ok
              et_message = gt_rap_msg
    EXCEPTIONS system_failure = 1 communication_failure = 2 OTHERS = 3.
  gv_rap_done = abap_true.
ENDFORM.
```
The new task has no classic CO buffer, so the handler loads the order cleanly; the create
commits in the new task's own LUW. If even this dumps, capture ST22 **Active Calls/Events**
+ **Source Code Extract** — the fix is then an SAP Note / release-specific restriction.

## Wrapping the call in a function module (ZPP_FM_CREATE_ORDER_COMPONENTS)
If you encapsulate the RAP call in a FM, HOW you call it depends on whether Tier 1 fixed
the dump:

**Case A — Tier 1 reset fixed it → a normal (same-session) FM call is enough** (no RFC):
```abap
CALL FUNCTION 'DEQUEUE_ALL'.
CALL FUNCTION 'CO_ZF_DATA_RESET_COMPLETE'
  EXPORTING i_no_ocm_reset = ' ' i_status_reset = 'X'.
CALL FUNCTION 'ZPP_FM_CREATE_ORDER_COMPONENTS'
  EXPORTING it_component = lt_rap_comp     "class TT_COMPONENT / TT_COMPONENT_FULL is fine here
            iv_commit    = abap_true
  IMPORTING et_message   = DATA(lt_msg)
            ev_success   = DATA(lv_ok).
```
A same-session FM adds nothing over calling the class directly — it only matters with the
Tier-1 reset in front of it.

**Case B — need a separate session → the FM must be Remote-Enabled with DDIC-only params.**
`STARTING NEW TASK` / `DESTINATION 'NONE'` reject class/program-local types in the RFC
interface, so change `IT_COMPONENT` to a DDIC table type (e.g. `ZPP_TT_PO_COMPONENT`) and
`ET_MESSAGE` to `BAPIRET2_T`, map DDIC↔class inside the FM, then call it — simplest is
synchronous `DESTINATION 'NONE'`:
```abap
CALL FUNCTION 'DEQUEUE_ALL'.                       "main session still holds the classic lock
CALL FUNCTION 'ZPP_FM_CREATE_ORDER_COMPONENTS'
  DESTINATION 'NONE'                               "fresh session, synchronous, results back
  EXPORTING it_component = lt_comp_ddic
            iv_commit    = abap_true
  IMPORTING et_message   = DATA(lt_ret)
            ev_success   = DATA(lv_ok)
  EXCEPTIONS system_failure = 1 MESSAGE DATA(lv_sysmsg)
             communication_failure = 2 MESSAGE DATA(lv_commsg)
             OTHERS = 3.
```

## STARTING NEW TASK + result collection (full pattern)
Resolve the internal IDs **inside** the FM (in the fresh session) and pass only external keys,
so the RFC interface uses standard DDIC data elements only.

**DDIC to create:** structure `ZPP_S_PO_COMP_EXT` (`VORNR TYPE VORNR`, `MATERIAL TYPE MATNR`,
`PLANT TYPE WERKS_D`, `POSTP TYPE POSTP`, `MENGE TYPE MENGE_D`, `MEINS TYPE MEINS`,
`LGORT TYPE LGORT_D`, `BDTER TYPE BDTER`) + table type `ZPP_TT_PO_COMP_EXT`. Messages use
standard `BAPIRET2_T`.

**FM `ZPP_FM_CREATE_ORDER_COMPONENTS` — Remote-Enabled:**
```abap
*"  IMPORTING VALUE(IV_ORDER)  TYPE AUFNR
*"            VALUE(IT_COMP)   TYPE ZPP_TT_PO_COMP_EXT
*"            VALUE(IV_COMMIT) TYPE ABAP_BOOLEAN DEFAULT ABAP_TRUE
*"  EXPORTING VALUE(EV_SUCCESS) TYPE ABAP_BOOLEAN
*"            VALUE(ET_MESSAGE) TYPE BAPIRET2_T
FUNCTION zpp_fm_create_order_components.
  SELECT manufacturingorder          AS aufnr,
         manufacturingorderoperation AS vornr,
         mfgorderinternalid          AS order_internal_id,
         orderoperationinternalid
    FROM i_manufacturingorderoperation
    WHERE manufacturingorder = @iv_order
    INTO TABLE @DATA(lt_op_map).
  SORT lt_op_map BY vornr.

  DATA lt_comp TYPE zcl_pp_production_order=>tt_component_full.
  LOOP AT it_comp INTO DATA(ls_c).
    READ TABLE lt_op_map INTO DATA(ls_op) WITH KEY vornr = ls_c-vornr BINARY SEARCH.
    CHECK sy-subrc = 0.
    APPEND VALUE #(
      order_internal_id     = ls_op-order_internal_id
      operation_internal_id = ls_op-orderoperationinternalid
      data = VALUE #( material                   = ls_c-material
                      plant                      = ls_c-plant
                      billofmaterialitemcategory = ls_c-postp
                      requiredquantity           = ls_c-menge
                      baseunit                   = ls_c-meins
                      storagelocation            = ls_c-lgort
                      requirementdate            = ls_c-bdter ) ) TO lt_comp.
  ENDLOOP.

  DATA(lo_po) = NEW zcl_pp_production_order( ).
  lo_po->create_components_full(
    EXPORTING it_component = lt_comp
              iv_commit    = iv_commit
    IMPORTING et_message   = DATA(lt_msg)
              ev_success   = ev_success ).

  LOOP AT lt_msg INTO DATA(ls_msg).
    APPEND VALUE #( type = ls_msg-severity message = ls_msg-text ) TO et_message.
  ENDLOOP.
ENDFUNCTION.
```

**Program globals** (top include — the aRFC callback is a FORM):
```abap
DATA: gv_rap_done TYPE abap_bool,
      gv_rap_ok   TYPE abap_bool,
      gt_rap_ret  TYPE bapiret2_t.
```

**Async call + WAIT** (per order, inside `LOOP AT lt_online_ofline`):
```abap
DATA lt_comp_ext TYPE zpp_tt_po_comp_ext.
CLEAR lt_comp_ext.
LOOP AT lt_resb INTO ls_resb WHERE vornr NE '0010'.
  DATA(lv_qty) = COND menge_d( WHEN ls_resb-meins = 'ST'
                               THEN ceil( ls_resb-bdmng ) ELSE ls_resb-bdmng ).
  DATA lv_stge TYPE lgort_d.
  CLEAR lv_stge.
  PERFORM get_lgort USING ls_resb-aufpl ls_resb-vornr CHANGING lv_stge.
  APPEND VALUE #( vornr = ls_resb-vornr material = ls_resb-matnr plant = ls_resb-werks
                  postp = ls_resb-postp menge = lv_qty meins = ls_resb-meins
                  lgort = lv_stge bdter = ls_resb-bdter ) TO lt_comp_ext.
ENDLOOP.

IF lt_comp_ext IS NOT INITIAL.
  CALL FUNCTION 'DEQUEUE_ALL'.
  gv_rap_done = abap_false.
  CLEAR: gv_rap_ok, gt_rap_ret.

  CALL FUNCTION 'ZPP_FM_CREATE_ORDER_COMPONENTS'
    STARTING NEW TASK 'RAPCOMP'
    PERFORMING receive_rap_result ON END OF TASK
    EXPORTING iv_order = ls_online_ofline-aufnr
              it_comp  = lt_comp_ext
              iv_commit = abap_true
    EXCEPTIONS communication_failure = 1 system_failure = 2
               resource_failure = 3 OTHERS = 4.
  IF sy-subrc <> 0.
    gv_rap_done = abap_true.
  ENDIF.

  WAIT UNTIL gv_rap_done = abap_true UP TO 60 SECONDS.

  READ TABLE gt_alv ASSIGNING FIELD-SYMBOL(<lfs_alv>)
       WITH KEY order_number = ls_online_ofline-aufnr.
  IF sy-subrc = 0.
    IF gv_rap_ok = abap_true.
      MESSAGE ID 'ZPP_1' TYPE 'S' NUMBER '009' INTO DATA(lv_mes).
      <lfs_alv>-message = |{ <lfs_alv>-message }{ lv_mes }|.
    ELSE.
      <lfs_alv>-icon = gc_red.
      <lfs_alv>-message = |{ <lfs_alv>-message }{ VALUE #( gt_rap_ret[ type = 'E' ]-message OPTIONAL ) }|.
    ENDIF.
  ENDIF.
ENDIF.
```

**Callback FORM** (in the report's FORM section):
```abap
FORM receive_rap_result USING p_task TYPE clike.
  RECEIVE RESULTS FROM FUNCTION 'ZPP_FM_CREATE_ORDER_COMPONENTS'
    IMPORTING ev_success = gv_rap_ok
              et_message = gt_rap_ret
    EXCEPTIONS communication_failure = 1 system_failure = 2 OTHERS = 3.
  gv_rap_done = abap_true.
ENDFORM.
```
`STARTING NEW TASK 'RAPCOMP'` (no DESTINATION) uses a free local dialog work process = a fresh
session with no classic CO buffer; `WAIT UNTIL` drives the aRFC reply. Reusing the task name is
fine because we `WAIT` before the next iteration. The create commits in the new task's own LUW.

## Verification
1. Activate class + program.
2. Run the report, upload the Excel template, select rows with an online scenario, press CREATE.
3. Check components appear on the correct operations (CO03 / table `RESB`) with the same
   field values the BAPI produced.
4. Success → `ZPP_1-009` on the ALV; failure → RAP error text + red icon.
5. Compare one order created the old way vs. the new way for parity.
```
