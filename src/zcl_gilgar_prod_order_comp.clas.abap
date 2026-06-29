CLASS zcl_gilgar_prod_order_comp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .

    " Input row: one component to be assigned to a production order operation.
    " As an alternative to BAPI_ALM_ORDER_MAINTAIN we feed these rows into the
    " RAP business object I_PRODUCTIONORDERTP. Only the fields you actually fill
    " are sent to the BO (driven by %control), so a row can set just the columns
    " it needs.
    TYPES: BEGIN OF ty_component,
             order_internal_id     TYPE i_productionorderoperationtp-orderinternalid,
             operation_internal_id TYPE i_productionorderoperationtp-orderoperationinternalid,
             material              TYPE i_productionordercomponenttp-material,
             plant                 TYPE i_productionordercomponenttp-plant,
             bom_item_category     TYPE i_productionordercomponenttp-billofmaterialitemcategory,
             required_quantity     TYPE i_productionordercomponenttp-requiredquantity,
             base_unit             TYPE i_productionordercomponenttp-baseunit,
           END OF ty_component,
           tt_component TYPE STANDARD TABLE OF ty_component WITH EMPTY KEY .

    " Generic field name/value pair, used by the fully dynamic variant.
    " NAME must match a component element (e.g. 'MATERIAL', 'REQUIREDQUANTITY').
    TYPES: BEGIN OF ty_field,
             name  TYPE string,
             value TYPE string,
           END OF ty_field,
           tt_field TYPE STANDARD TABLE OF ty_field WITH EMPTY KEY .

    " Fully dynamic input row: an operation key plus an arbitrary list of
    " field name/value pairs. You decide at runtime which fields are filled.
    TYPES: BEGIN OF ty_component_dyn,
             order_internal_id     TYPE i_productionorderoperationtp-orderinternalid,
             operation_internal_id TYPE i_productionorderoperationtp-orderoperationinternalid,
             fields                TYPE tt_field,
           END OF ty_component_dyn,
           tt_component_dyn TYPE STANDARD TABLE OF ty_component_dyn WITH EMPTY KEY .

    " Output row: one message returned by the RAP modify / commit.
    TYPES: BEGIN OF ty_message,
             order_internal_id     TYPE i_productionorderoperationtp-orderinternalid,
             operation_internal_id TYPE i_productionorderoperationtp-orderoperationinternalid,
             severity              TYPE if_abap_behv_message=>t_severity,
             text                  TYPE string,
           END OF ty_message,
           tt_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY .

    "! Create components from a typed table. For every row, each non-initial
    "! field is flagged in %control and sent to the BO; initial fields are left
    "! untouched, so you can fill different columns per row.
    METHODS create_components
      IMPORTING
        !it_component TYPE tt_component
        !iv_commit    TYPE abap_boolean DEFAULT abap_true
      EXPORTING
        !et_message   TYPE tt_message
        !ev_success   TYPE abap_boolean .

    "! Create components from name/value pairs - the field names themselves are
    "! decided at runtime. Each pair is mapped onto %data and %control with
    "! ASSIGN COMPONENT, so unknown / empty fields are simply ignored.
    METHODS create_components_dyn
      IMPORTING
        !it_component TYPE tt_component_dyn
        !iv_commit    TYPE abap_boolean DEFAULT abap_true
      EXPORTING
        !et_message   TYPE tt_message
        !ev_success   TYPE abap_boolean .

  PROTECTED SECTION.
  PRIVATE SECTION.

    "! Type for the "create by association" EML input table.
    TYPES tt_create TYPE TABLE FOR CREATE i_productionordertp\\productionorderoperation\_operationcomponent .

    "! Returns (creating if needed) the parent operation row for the given key.
    METHODS get_operation_ref
      IMPORTING
        !iv_order_internal_id     TYPE i_productionorderoperationtp-orderinternalid
        !iv_operation_internal_id TYPE i_productionorderoperationtp-orderoperationinternalid
      CHANGING
        !ct_create                TYPE tt_create
      RETURNING
        VALUE(rr_operation)       TYPE REF TO data .

    "! Runs MODIFY ENTITIES (+ optional COMMIT) and collects all messages.
    METHODS save_components
      IMPORTING
        !it_create  TYPE tt_create
        !iv_commit  TYPE abap_boolean
      EXPORTING
        !et_message TYPE tt_message
        !ev_success TYPE abap_boolean .

ENDCLASS.



CLASS zcl_gilgar_prod_order_comp IMPLEMENTATION.


  METHOD create_components.

    CLEAR: et_message, ev_success.
    IF it_component IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_create TYPE tt_create.
    DATA lv_cid    TYPE i.

    LOOP AT it_component ASSIGNING FIELD-SYMBOL(<comp>).

      DATA(lr_op) = get_operation_ref(
                      EXPORTING iv_order_internal_id     = <comp>-order_internal_id
                                iv_operation_internal_id = <comp>-operation_internal_id
                      CHANGING  ct_create                = lt_create ).
      ASSIGN lr_op->* TO FIELD-SYMBOL(<operation>).

      lv_cid = lv_cid + 1.

      " Build one target row, then switch %control on only for filled fields.
      DATA ls_target LIKE LINE OF <operation>-%target.
      CLEAR ls_target.
      ls_target-%cid = |CID_{ lv_cid }|.

      IF <comp>-material IS NOT INITIAL.
        ls_target-%data-material      = <comp>-material.
        ls_target-%control-material   = if_abap_behv=>mk-on.
      ENDIF.
      IF <comp>-plant IS NOT INITIAL.
        ls_target-%data-plant         = <comp>-plant.
        ls_target-%control-plant      = if_abap_behv=>mk-on.
      ENDIF.
      IF <comp>-bom_item_category IS NOT INITIAL.
        ls_target-%data-billofmaterialitemcategory    = <comp>-bom_item_category.
        ls_target-%control-billofmaterialitemcategory = if_abap_behv=>mk-on.
      ENDIF.
      IF <comp>-required_quantity IS NOT INITIAL.
        ls_target-%data-requiredquantity    = <comp>-required_quantity.
        ls_target-%control-requiredquantity = if_abap_behv=>mk-on.
      ENDIF.
      IF <comp>-base_unit IS NOT INITIAL.
        ls_target-%data-baseunit      = <comp>-base_unit.
        ls_target-%control-baseunit   = if_abap_behv=>mk-on.
      ENDIF.

      INSERT ls_target INTO TABLE <operation>-%target.

    ENDLOOP.

    save_components(
      EXPORTING it_create  = lt_create
                iv_commit  = iv_commit
      IMPORTING et_message = et_message
                ev_success = ev_success ).

  ENDMETHOD.


  METHOD create_components_dyn.

    CLEAR: et_message, ev_success.
    IF it_component IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_create TYPE tt_create.
    DATA lv_cid    TYPE i.

    LOOP AT it_component ASSIGNING FIELD-SYMBOL(<comp>).

      DATA(lr_op) = get_operation_ref(
                      EXPORTING iv_order_internal_id     = <comp>-order_internal_id
                                iv_operation_internal_id = <comp>-operation_internal_id
                      CHANGING  ct_create                = lt_create ).
      ASSIGN lr_op->* TO FIELD-SYMBOL(<operation>).

      lv_cid = lv_cid + 1.

      DATA ls_target LIKE LINE OF <operation>-%target.
      CLEAR ls_target.
      ls_target-%cid = |CID_{ lv_cid }|.

      " Map each name/value pair onto %data and %control dynamically. Unknown
      " field names or empty values are simply skipped.
      LOOP AT <comp>-fields ASSIGNING FIELD-SYMBOL(<field>) WHERE value IS NOT INITIAL.

        ASSIGN COMPONENT <field>-name OF STRUCTURE ls_target-%data TO FIELD-SYMBOL(<data_val>).
        CHECK sy-subrc = 0.
        <data_val> = <field>-value.

        ASSIGN COMPONENT <field>-name OF STRUCTURE ls_target-%control TO FIELD-SYMBOL(<ctrl_val>).
        IF sy-subrc = 0.
          <ctrl_val> = if_abap_behv=>mk-on.
        ENDIF.

      ENDLOOP.

      INSERT ls_target INTO TABLE <operation>-%target.

    ENDLOOP.

    save_components(
      EXPORTING it_create  = lt_create
                iv_commit  = iv_commit
      IMPORTING et_message = et_message
                ev_success = ev_success ).

  ENDMETHOD.


  METHOD get_operation_ref.

    ASSIGN ct_create[ KEY entity COMPONENTS
                        %key-orderinternalid          = iv_order_internal_id
                        %key-orderoperationinternalid = iv_operation_internal_id
                    ] TO FIELD-SYMBOL(<operation>).
    IF sy-subrc <> 0.
      INSERT VALUE #( %key-orderinternalid          = iv_order_internal_id
                      %key-orderoperationinternalid = iv_operation_internal_id )
             INTO TABLE ct_create ASSIGNING <operation>.
    ENDIF.

    GET REFERENCE OF <operation> INTO rr_operation.

  ENDMETHOD.


  METHOD save_components.

    CLEAR: et_message, ev_success.

    " No FIELDS clause: the BO honours %control, so each row only sets the
    " fields that were flagged on.
    MODIFY ENTITIES OF i_productionordertp
      ENTITY productionorderoperation
      CREATE BY \_operationcomponent
      WITH it_create
      FAILED   DATA(failed)
      REPORTED DATA(reported)
      MAPPED   DATA(mapped).

    " Messages from the interaction phase (EARLY reported).
    LOOP AT reported-productionorderoperation ASSIGNING FIELD-SYMBOL(<op>).
      IF <op>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <op>-orderinternalid
                        operation_internal_id = <op>-orderoperationinternalid
                        severity              = <op>-%msg->m_severity
                        text                  = <op>-%msg->if_message~get_text( ) )
               INTO TABLE et_message.
      ENDIF.
    ENDLOOP.
    LOOP AT reported-productionordercomponent ASSIGNING FIELD-SYMBOL(<comp>).
      IF <comp>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <comp>-orderinternalid
                        operation_internal_id = <comp>-orderoperationinternalid
                        severity              = <comp>-%msg->m_severity
                        text                  = <comp>-%msg->if_message~get_text( ) )
               INTO TABLE et_message.
      ENDIF.
    ENDLOOP.

    IF failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      RETURN.
    ENDIF.

    IF iv_commit = abap_false.
      ev_success = abap_true.
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSES
      FAILED   DATA(failed_commit)
      REPORTED DATA(reported_commit).

    " Messages from the save phase (LATE reported).
    LOOP AT reported_commit-productionorderoperation ASSIGNING FIELD-SYMBOL(<op_c>).
      IF <op_c>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <op_c>-orderinternalid
                        operation_internal_id = <op_c>-orderoperationinternalid
                        severity              = <op_c>-%msg->m_severity
                        text                  = <op_c>-%msg->if_message~get_text( ) )
               INTO TABLE et_message.
      ENDIF.
    ENDLOOP.
    LOOP AT reported_commit-productionordercomponent ASSIGNING FIELD-SYMBOL(<comp_c>).
      IF <comp_c>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <comp_c>-orderinternalid
                        operation_internal_id = <comp_c>-orderoperationinternalid
                        severity              = <comp_c>-%msg->m_severity
                        text                  = <comp_c>-%msg->if_message~get_text( ) )
               INTO TABLE et_message.
      ENDIF.
    ENDLOOP.

    ev_success = xsdbool( failed_commit IS INITIAL ).

  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.

    " Variant 1 - typed table, only filled fields are sent (per-row dynamic).
    DATA(lt_component) = VALUE tt_component(
      ( order_internal_id     = '4996180'
        operation_internal_id = '00000002'
        material              = 'F1190210T300UC001'
        bom_item_category     = 'L'
        required_quantity     = 22
        base_unit             = 'PLK' )
    ).

    create_components(
      EXPORTING it_component = lt_component
                iv_commit    = abap_true
      IMPORTING et_message   = DATA(lt_message)
                ev_success   = DATA(lv_success) ).

    out->write( COND #( WHEN lv_success = abap_true
                        THEN |create_components: OK|
                        ELSE |create_components: FAILED| ) ).
    out->write( lt_message ).

    " Variant 2 - fully dynamic name/value pairs (field names chosen at runtime).
    DATA(lt_component_dyn) = VALUE tt_component_dyn(
      ( order_internal_id     = '4996180'
        operation_internal_id = '00000002'
        fields = VALUE #(
          ( name = 'MATERIAL'                   value = 'F1190210T300UC001' )
          ( name = 'BILLOFMATERIALITEMCATEGORY' value = 'L' )
          ( name = 'REQUIREDQUANTITY'           value = '22' )
          ( name = 'BASEUNIT'                   value = 'PLK' ) ) )
    ).

    create_components_dyn(
      EXPORTING it_component = lt_component_dyn
                iv_commit    = abap_false   " demo only - no commit
      IMPORTING et_message   = DATA(lt_message_dyn)
                ev_success   = DATA(lv_success_dyn) ).

    out->write( COND #( WHEN lv_success_dyn = abap_true
                        THEN |create_components_dyn: OK|
                        ELSE |create_components_dyn: FAILED| ) ).
    out->write( lt_message_dyn ).

  ENDMETHOD.

ENDCLASS.
