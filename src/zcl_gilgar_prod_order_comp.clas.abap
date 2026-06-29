CLASS zcl_gilgar_prod_order_comp DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .

    "! Input row: one component to be assigned to a production order operation.
    "! As an alternative to BAPI_ALM_ORDER_MAINTAIN we feed these rows into the
    "! RAP business object I_PRODUCTIONORDERTP.
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

    "! Output row: one message returned by the RAP modify / commit.
    TYPES: BEGIN OF ty_message,
             order_internal_id     TYPE i_productionorderoperationtp-orderinternalid,
             operation_internal_id TYPE i_productionorderoperationtp-orderoperationinternalid,
             severity              TYPE if_abap_behv_message=>t_severity,
             text                  TYPE string,
           END OF ty_message,
           tt_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY .

    "! Creates the given components for their production order operations.
    "! The EML statement is built dynamically from the supplied table, so any
    "! number of operations / components can be processed in a single call.
    "!
    "! @parameter it_component | Components to create (table type).
    "! @parameter iv_commit    | If set, COMMIT ENTITIES is executed on success.
    "! @parameter et_message   | All collected messages (modify + commit).
    "! @parameter ev_success   | abap_true when nothing failed.
    METHODS create_components
      IMPORTING
        !it_component TYPE tt_component
        !iv_commit    TYPE abap_boolean DEFAULT abap_true
      EXPORTING
        !et_message   TYPE tt_message
        !ev_success   TYPE abap_boolean .

  PROTECTED SECTION.
  PRIVATE SECTION.

    "! Collects messages out of a REPORTED structure of I_PRODUCTIONORDERTP.
    METHODS collect_messages
      IMPORTING
        !is_reported TYPE RESPONSE FOR REPORTED i_productionordertp
      CHANGING
        !ct_message  TYPE tt_message .

ENDCLASS.



CLASS zcl_gilgar_prod_order_comp IMPLEMENTATION.


  METHOD create_components.

    CLEAR: et_message,
           ev_success.

    IF it_component IS INITIAL.
      RETURN.
    ENDIF.

    " Derived type for "create by association" operation -> component.
    DATA lt_create TYPE TABLE FOR CREATE i_productionordertp\\productionorderoperation\_operationcomponent.

    DATA lv_cid TYPE i.

    " Build the EML input table dynamically from the supplied components.
    " Rows that share the same operation key are grouped under one parent row.
    LOOP AT it_component ASSIGNING FIELD-SYMBOL(<comp>).

      ASSIGN lt_create[ KEY entity COMPONENTS
                          %key-orderinternalid          = <comp>-order_internal_id
                          %key-orderoperationinternalid = <comp>-operation_internal_id
                      ] TO FIELD-SYMBOL(<operation>).
      IF sy-subrc <> 0.
        INSERT VALUE #( %key-orderinternalid          = <comp>-order_internal_id
                        %key-orderoperationinternalid = <comp>-operation_internal_id )
               INTO TABLE lt_create ASSIGNING <operation>.
      ENDIF.

      lv_cid = lv_cid + 1.

      INSERT VALUE #(
          %cid                             = |CID_{ lv_cid }|
          %data-material                   = <comp>-material
          %data-plant                      = <comp>-plant
          %data-billofmaterialitemcategory = <comp>-bom_item_category
          %data-requiredquantity           = <comp>-required_quantity
          %data-baseunit                   = <comp>-base_unit )
        INTO TABLE <operation>-%target.

    ENDLOOP.

    MODIFY ENTITIES OF i_productionordertp
      ENTITY productionorderoperation
      CREATE BY \_operationcomponent
      FIELDS ( material
               plant
               billofmaterialitemcategory
               requiredquantity
               baseunit )
      WITH lt_create
      FAILED   DATA(failed)
      REPORTED DATA(reported)
      MAPPED   DATA(mapped).

    collect_messages( EXPORTING is_reported = reported
                      CHANGING  ct_message  = et_message ).

    IF failed IS NOT INITIAL.
      ROLLBACK ENTITIES.
      ev_success = abap_false.
      RETURN.
    ENDIF.

    IF iv_commit = abap_false.
      ev_success = abap_true.
      RETURN.
    ENDIF.

    COMMIT ENTITIES RESPONSES
      FAILED   DATA(failed_commit)
      REPORTED DATA(reported_commit).

    collect_messages( EXPORTING is_reported = reported_commit
                      CHANGING  ct_message  = et_message ).

    IF failed_commit IS INITIAL.
      ev_success = abap_true.
    ELSE.
      ev_success = abap_false.
    ENDIF.

  ENDMETHOD.


  METHOD collect_messages.

    LOOP AT is_reported-productionorderoperation ASSIGNING FIELD-SYMBOL(<op>).
      IF <op>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <op>-orderinternalid
                        operation_internal_id = <op>-orderoperationinternalid
                        severity              = <op>-%msg->m_severity
                        text                  = <op>-%msg->if_message~get_text( ) )
               INTO TABLE ct_message.
      ENDIF.
    ENDLOOP.

    LOOP AT is_reported-productionordercomponent ASSIGNING FIELD-SYMBOL(<comp>).
      IF <comp>-%msg IS BOUND.
        INSERT VALUE #( order_internal_id     = <comp>-orderinternalid
                        operation_internal_id = <comp>-orderoperationinternalid
                        severity              = <comp>-%msg->m_severity
                        text                  = <comp>-%msg->if_message~get_text( ) )
               INTO TABLE ct_message.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.

    " Demo: same data as the original report, but now driven by a table that
    " could just as well be filled from a file, an OData payload, etc.
    DATA(lt_component) = VALUE tt_component(
      ( order_internal_id     = '4996180'
        operation_internal_id = '00000002'
        material              = 'F1190210T300UC001'
        bom_item_category     = 'L'
        required_quantity     = 22
        base_unit             = 'PLK' )
    ).

    create_components(
      EXPORTING
        it_component = lt_component
        iv_commit    = abap_true
      IMPORTING
        et_message   = DATA(lt_message)
        ev_success   = DATA(lv_success) ).

    IF lv_success = abap_true.
      out->write( |Components created successfully.| ).
    ELSE.
      out->write( |Component creation failed.| ).
    ENDIF.

    out->write( lt_message ).

  ENDMETHOD.

ENDCLASS.
