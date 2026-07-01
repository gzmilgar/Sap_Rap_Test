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

  " Clear the classic order context (locks left by BAPI_PRODORD_* /
  " CO_SE_PRODORD_CHANGE) so the standard MFG-order RAP handler
  " (CL_PPRAP_MFGORDER_BILHDLR) can load/lock the order without ASSERTION_FAILED.
  CALL FUNCTION 'DEQUEUE_ALL'.
  " If it still dumps, also reset the classic order buffer/status before the call:
  " CALL FUNCTION 'CO_ZF_DATA_RESET_COMPLETE'
  "   EXPORTING i_no_ocm_reset = ' ' i_status_reset = 'X'.

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
classically when the RAP handler tries to load and lock it.
- First fix (applied above): `CALL FUNCTION 'DEQUEUE_ALL'.` before the RAP call.
- If it still dumps: add `CO_ZF_DATA_RESET_COMPLETE` (status reset) before the call, and
  capture ST22 **Active Calls/Events** + **Source Code Extract** to identify the exact
  asserting method. The definitive fix may be an SAP Note or running the RAP create in a
  separate task/LUW (`STARTING NEW TASK`).

## Verification
1. Activate class + program.
2. Run the report, upload the Excel template, select rows with an online scenario, press CREATE.
3. Check components appear on the correct operations (CO03 / table `RESB`) with the same
   field values the BAPI produced.
4. Success → `ZPP_1-009` on the ALV; failure → RAP error text + red icon.
5. Compare one order created the old way vs. the new way for parity.
```
