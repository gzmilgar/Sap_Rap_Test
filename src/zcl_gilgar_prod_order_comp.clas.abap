CLASS zcl_gilgar_prod_order_comp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .

    " The component can only be created through the association
    " (CREATE BY \_operationcomponent); the operation/component entities have no
    " standalone CREATE. So we derive every type from the create-by-association
    " table itself:
    "   ty_create_line-%key  -> the operation key fields (orderinternalid, ...)
    "   ty_target_line-%data -> the component fields (material, plant, ...)
    TYPES tt_create      TYPE TABLE FOR CREATE i_productionordertp\\productionorderoperation\_operationcomponent .
    TYPES ty_create_line TYPE LINE OF tt_create .
    TYPES ty_target_tab  TYPE ty_create_line-%target .
    TYPES ty_target_line TYPE LINE OF ty_target_tab .

    " Input row: one component to be assigned to a production order operation.
    " As an alternative to BAPI_ALM_ORDER_MAINTAIN we feed these rows into the
    " RAP business object I_PRODUCTIONORDERTP. Only the fields you actually fill
    " are sent to the BO (driven by %control), so a row can set just the columns
    " it needs.
    TYPES: BEGIN OF ty_component,
             order_internal_id     TYPE ty_create_line-%key-orderinternalid,
             operation_internal_id TYPE ty_create_line-%key-orderoperationinternalid,
             material              TYPE ty_target_line-%data-material,
             plant                 TYPE ty_target_line-%data-plant,
             bom_item_category     TYPE ty_target_line-%data-billofmaterialitemcategory,
             required_quantity     TYPE ty_target_line-%data-requiredquantity,
             base_unit             TYPE ty_target_line-%data-baseunit,
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
             order_internal_id     TYPE ty_create_line-%key-orderinternalid,
             operation_internal_id TYPE ty_create_line-%key-orderoperationinternalid,
             fields                TYPE tt_field,
           END OF ty_component_dyn,
           tt_component_dyn TYPE STANDARD TABLE OF ty_component_dyn WITH EMPTY KEY .

    " Full-data input row: an operation key plus the COMPLETE component %data
    " structure. You are not limited to a fixed field list - fill any field the
    " BO exposes (use Ctrl+Space on -data-...). %control is set automatically for
    " every field you actually fill.
    TYPES: BEGIN OF ty_component_full,
             order_internal_id     TYPE ty_create_line-%key-orderinternalid,
             operation_internal_id TYPE ty_create_line-%key-orderoperationinternalid,
             data                  TYPE ty_target_line-%data,
           END OF ty_component_full,
           tt_component_full TYPE STANDARD TABLE OF ty_component_full WITH EMPTY KEY .

    " Output row: one message returned by the RAP modify / commit.
    TYPES: BEGIN OF ty_message,
             order_internal_id     TYPE ty_create_line-%key-orderinternalid,
             operation_internal_id TYPE ty_create_line-%key-orderoperationinternalid,
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

    "! Create components from the full, typed component data structure - every
    "! field the BO exposes can be supplied, with no fixed field list. %control
    "! is derived automatically (on for each non-initial field).
    METHODS create_components_full
      IMPORTING
        !it_component TYPE tt_component_full
        !iv_commit    TYPE abap_boolean DEFAULT abap_true
      EXPORTING
        !et_message   TYPE tt_message
        !ev_success   TYPE abap_boolean .

  PROTECTED SECTION.
  PRIVATE SECTION.

    "! Runs MODIFY ENTITIES (+ optional COMMIT) and collects the messages.
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

      " Find (or create) the parent operation row, grouping by its key.
      ASSIGN lt_create[ KEY entity
                        %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id
                      ] TO FIELD-SYMBOL(<operation>).
      IF sy-subrc <> 0.
        INSERT VALUE #( %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id )
               INTO TABLE lt_create ASSIGNING <operation>.
      ENDIF.

      lv_cid = lv_cid + 1.

      " Build one target row, then switch %control on only for filled fields.
      DATA ls_target LIKE LINE OF <operation>-%target.
      CLEAR ls_target.
      ls_target-%cid = |CID_{ lv_cid }|.

      IF <comp>-material IS NOT INITIAL.
        ls_target-%data-material    = <comp>-material.
        ls_target-%control-material = if_abap_behv=>mk-on.
      ENDIF.
      IF <comp>-plant IS NOT INITIAL.
        ls_target-%data-plant    = <comp>-plant.
        ls_target-%control-plant = if_abap_behv=>mk-on.
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
        ls_target-%data-baseunit    = <comp>-base_unit.
        ls_target-%control-baseunit = if_abap_behv=>mk-on.
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

      ASSIGN lt_create[ KEY entity
                        %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id
                      ] TO FIELD-SYMBOL(<operation>).
      IF sy-subrc <> 0.
        INSERT VALUE #( %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id )
               INTO TABLE lt_create ASSIGNING <operation>.
      ENDIF.

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


  METHOD create_components_full.

    CLEAR: et_message, ev_success.
    IF it_component IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_create TYPE tt_create.
    DATA lv_cid    TYPE i.

    " Describe the component %data structure once, to drive %control generically.
    DATA ls_data TYPE ty_target_line-%data.
    DATA(lt_comp) = CAST cl_abap_structdescr(
                      cl_abap_typedescr=>describe_by_data( ls_data ) )->components.

    LOOP AT it_component ASSIGNING FIELD-SYMBOL(<comp>).

      ASSIGN lt_create[ KEY entity
                        %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id
                      ] TO FIELD-SYMBOL(<operation>).
      IF sy-subrc <> 0.
        INSERT VALUE #( %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id )
               INTO TABLE lt_create ASSIGNING <operation>.
      ENDIF.

      lv_cid = lv_cid + 1.

      DATA ls_target LIKE LINE OF <operation>-%target.
      CLEAR ls_target.
      ls_target-%cid  = |CID_{ lv_cid }|.
      ls_target-%data = <comp>-data.

      " Switch %control on for every field that was actually filled.
      LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<c>).
        ASSIGN COMPONENT <c>-name OF STRUCTURE ls_target-%data TO FIELD-SYMBOL(<data_val>).
        IF sy-subrc = 0 AND <data_val> IS NOT INITIAL.
          ASSIGN COMPONENT <c>-name OF STRUCTURE ls_target-%control TO FIELD-SYMBOL(<ctrl_val>).
          IF sy-subrc = 0.
            <ctrl_val> = if_abap_behv=>mk-on.
          ENDIF.
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


  METHOD save_components.

    CLEAR: et_message, ev_success.

    " Explicit FIELDS ( ... ) form: on this standard/unmanaged MFG-order BO the
    " FROM/%control form does not actually create the component, whereas the
    " field-list form (as used by the working direct EML) does. Add further
    " fields to the list once their element names are confirmed.
    MODIFY ENTITIES OF i_productionordertp
      ENTITY productionorderoperation
      CREATE BY \_operationcomponent
      AUTO FILL CID
      FIELDS ( material
               plant
               billofmaterialitemcategory
               requiredquantity
               baseunit )
      WITH it_create
      FAILED   DATA(failed)
      REPORTED DATA(reported)
      MAPPED   DATA(mapped).

    " The component reported line carries the component's own key (not the
    " operation key), so we only surface the message itself here.
    LOOP AT reported-productionordercomponent ASSIGNING FIELD-SYMBOL(<comp>).
      IF <comp>-%msg IS BOUND.
        INSERT VALUE #( severity = <comp>-%msg->m_severity
                        text     = <comp>-%msg->if_message~get_text( ) )
               INTO TABLE et_message.
      ENDIF.
    ENDLOOP.

    LOOP AT reported-productionorderoperation ASSIGNING FIELD-SYMBOL(<op>).
      IF <op>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <op>-orderinternalid
                        operation_internal_id = <op>-orderoperationinternalid
                        severity              = <op>-%msg->m_severity
                        text                  = <op>-%msg->if_message~get_text( ) )
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

    COMMIT ENTITIES RESPONSES FAILED DATA(failed_commit).
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

    " Variant 3 - full typed %data: fill ANY field the BO exposes, no fixed list.
    DATA(lt_component_full) = VALUE tt_component_full(
      ( order_internal_id     = '4996180'
        operation_internal_id = '00000002'
        data = VALUE #( material                   = 'F1190210T300UC001'
                        billofmaterialitemcategory = 'L'
                        requiredquantity           = 22
                        baseunit                   = 'PLK' ) )
    ).

    create_components_full(
      EXPORTING it_component = lt_component_full
                iv_commit    = abap_false   " demo only - no commit
      IMPORTING et_message   = DATA(lt_message_full)
                ev_success   = DATA(lv_success_full) ).

    out->write( COND #( WHEN lv_success_full = abap_true
                        THEN |create_components_full: OK|
                        ELSE |create_components_full: FAILED| ) ).
    out->write( lt_message_full ).

  ENDMETHOD.

ENDCLASS.
