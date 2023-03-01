CLASS lhc_item DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Item RESULT result.

    METHODS TestButton FOR MODIFY
      IMPORTING keys FOR ACTION Item~TestButton RESULT result.

ENDCLASS.

CLASS lhc_item IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD TestButton.
  ENDMETHOD.

ENDCLASS.

CLASS lhc_Header DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Header RESULT result.
    METHODS testbutton FOR MODIFY
      IMPORTING keys FOR ACTION header~testbutton RESULT result.

ENDCLASS.

CLASS lhc_Header IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD TestButton.

" Modify in local mode
 MODIFY ENTITIES OF Zi_GILGAR_T_HEADER IN LOCAL MODE
 ENTITY Header
 UPDATE FROM VALUE #( for key in keys ( id = key-id
 TestButton = 'A'
 %control-TestButton = if_abap_behv=>mk-on ) )
 FAILED failed
 REPORTED reported.


*    SELECT MAX( id ) FROM zgilgar_t_header INTO @DATA(lv_id). "#EC CI_NOWHERE
*
*    READ ENTITIES OF Zi_GILGAR_T_HEADER IN LOCAL MODE
*    ENTITY Header
*    FIELDS ( id
*             customer
*         )
*    WITH CORRESPONDING #( keys )
*    RESULT DATA(lt_read_result)
*    FAILED failed
*    REPORTED reported.
*
*    DATA(lv_today) = cl_abap_context_info=>get_system_date( ).
*    DATA lt_create TYPE TABLE FOR CREATE Zi_GILGAR_T_HEADER.
*
*    lt_create = VALUE #( FOR row IN lt_read_result INDEX INTO idx
*    ( id          = lv_id + idx
*      customer    = row-customer
*      TestButton  = 'X' ) ). " Open
*    MODIFY ENTITIES OF Zi_GILGAR_T_HEADER IN LOCAL MODE
*    ENTITY Header
**Develop
*    CREATE FIELDS ( id
*                    customer
*                    TestButton )
*    WITH lt_create
*    MAPPED mapped
*    FAILED failed
*    REPORTED reported.
*    result = VALUE #( FOR create IN lt_create INDEX INTO idx
*                    ( %cid_ref = keys[ idx ]-%cid_ref
*                      %key     = keys[ idx ]-Id
*                      %param   = CORRESPONDING #( create ) ) ) .
*


*  UPDATE zgilgar_t_header set test_button = 'X' WHERE id = '1'.

  ENDMETHOD.

ENDCLASS.
