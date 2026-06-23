REPORT zgilgar_scan_hdc_refresh.

"&---------------------------------------------------------------------*
"& Report  ZGILGAR_SCAN_HDC_REFRESH
"&---------------------------------------------------------------------*
"& Sistemdeki tum Z*/Y* program, include ve global siniflarini tarar.
"& "...DATA_CHANGED" benzeri event-handler metotlari (or. ALV grid
"& HANDLE_DATA_CHANGED) icinde REFRESH kullanilip kullanilmadigini
"& bulup ALV olarak raporlar.
"&
"& - Programlar/include'lar READ REPORT ile okunur, METHOD..ENDMETHOD
"&   bloklari ayristirilir.
"& - Global siniflar icin metot include'lari CL_OO_CLASSNAME_SERVICE
"&   uzerinden tek tek okunur.
"& - Metot adi p_meth (CP pattern), aranan token p_tok (substring).
"&---------------------------------------------------------------------*

DATA gv_name TYPE progname.

SELECT-OPTIONS s_name FOR gv_name DEFAULT 'Z*' OPTION CP SIGN I.
PARAMETERS: p_meth(60) TYPE c DEFAULT '*DATA_CHANGED*',
            p_tok(30)  TYPE c DEFAULT 'REFRESH',
            p_rep      AS CHECKBOX DEFAULT 'X',
            p_cls      AS CHECKBOX DEFAULT 'X'.

TYPES: BEGIN OF ty_result,
         object TYPE progname,
         type   TYPE string,
         method TYPE string,
         line   TYPE i,
         code   TYPE string,
       END OF ty_result,
       tt_result TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

CLASS lcl_scanner DEFINITION.
  PUBLIC SECTION.
    METHODS run.
  PRIVATE SECTION.
    DATA mt_result TYPE tt_result.
    DATA mv_meth   TYPE string.
    DATA mv_tok    TYPE string.

    METHODS scan_reports.
    METHODS scan_classes.
    METHODS scan_source
      IMPORTING iv_object TYPE progname
                iv_type   TYPE string.
    METHODS scan_method_include
      IMPORTING iv_include TYPE progname
                iv_class   TYPE seoclsname
                iv_method  TYPE seocpdname.
    METHODS add_hit
      IMPORTING iv_object TYPE progname
                iv_type   TYPE string
                iv_method TYPE string
                iv_index  TYPE i
                iv_line   TYPE string.
    METHODS is_comment
      IMPORTING iv_line       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    METHODS has_token
      IMPORTING iv_line       TYPE string
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    METHODS display.
ENDCLASS.

CLASS lcl_scanner IMPLEMENTATION.

  METHOD run.
    mv_meth = to_upper( condense( p_meth ) ).
    mv_tok  = to_upper( condense( p_tok ) ).

    IF mv_tok IS INITIAL.
      MESSAGE 'Aranacak token (p_tok) bos olamaz.' TYPE 'I'.
      RETURN.
    ENDIF.

    IF p_rep = abap_true.
      scan_reports( ).
    ENDIF.
    IF p_cls = abap_true.
      scan_classes( ).
    ENDIF.

    display( ).
  ENDMETHOD.

  METHOD scan_reports.
    SELECT name, subc FROM trdir
      INTO TABLE @DATA(lt_trdir)
      WHERE name IN @s_name
        AND subc <> 'K'.            "K = global sinif havuzu, ayri taranir

    LOOP AT lt_trdir INTO DATA(ls_dir).
      " sinif/arayuz icin generate edilen include'lari atla ('=' dolgusu)
      IF ls_dir-name CS '='.
        CONTINUE.
      ENDIF.
      scan_source( iv_object = ls_dir-name
                   iv_type   = 'PROG/INCLUDE' ).
    ENDLOOP.
  ENDMETHOD.

  METHOD scan_classes.
    SELECT clsname FROM seoclass
      INTO TABLE @DATA(lt_cls)
      WHERE clsname IN @s_name.

    LOOP AT lt_cls INTO DATA(ls_cls).
      TRY.
          DATA(lt_inc) =
            cl_oo_classname_service=>get_all_method_includes( ls_cls-clsname ).
        CATCH cx_root.
          CONTINUE.
      ENDTRY.

      LOOP AT lt_inc INTO DATA(ls_inc).
        DATA(lv_mname) = to_upper( condense( CONV string( ls_inc-cpdkey-cpdname ) ) ).
        IF lv_mname CP mv_meth.
          scan_method_include( iv_include = ls_inc-incname
                               iv_class   = ls_cls-clsname
                               iv_method  = ls_inc-cpdkey-cpdname ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD scan_source.
    DATA lt_src TYPE STANDARD TABLE OF string.

    READ REPORT iv_object INTO lt_src.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_in     TYPE abap_bool.
    DATA lv_method TYPE string.
    DATA lv_mname  TYPE string.

    LOOP AT lt_src INTO DATA(lv_line).
      DATA(lv_idx)  = sy-tabix.
      DATA(lv_norm) = to_upper( condense( lv_line ) ).

      IF is_comment( lv_norm ) = abap_true.
        CONTINUE.
      ENDIF.

      " METHOD <ad>. -> metot blogu basi
      CLEAR lv_mname.
      FIND REGEX '^METHOD\s+([A-Z0-9_~/]+)' IN lv_norm SUBMATCHES lv_mname.
      IF sy-subrc = 0.
        IF lv_mname CS '~'.
          SPLIT lv_mname AT '~' INTO DATA(lv_pre) lv_mname.
        ENDIF.
        IF lv_mname CP mv_meth.
          lv_in     = abap_true.
          lv_method = lv_mname.
        ELSE.
          lv_in = abap_false.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_norm CP 'ENDMETHOD*'.
        lv_in = abap_false.
        CONTINUE.
      ENDIF.

      IF lv_in = abap_true AND has_token( lv_norm ) = abap_true.
        add_hit( iv_object = iv_object
                 iv_type   = iv_type
                 iv_method = lv_method
                 iv_index  = lv_idx
                 iv_line   = condense( lv_line ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD scan_method_include.
    DATA lt_src TYPE STANDARD TABLE OF string.

    READ REPORT iv_include INTO lt_src.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_src INTO DATA(lv_line).
      DATA(lv_idx)  = sy-tabix.
      DATA(lv_norm) = to_upper( condense( lv_line ) ).

      IF is_comment( lv_norm ) = abap_true.
        CONTINUE.
      ENDIF.

      IF has_token( lv_norm ) = abap_true.
        add_hit( iv_object = CONV progname( iv_class )
                 iv_type   = 'CLASS METHOD'
                 iv_method = CONV string( iv_method )
                 iv_index  = lv_idx
                 iv_line   = condense( lv_line ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_comment.
    IF iv_line IS INITIAL OR iv_line(1) = '*'.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD has_token.
    " satir ici yorumu ( " ) at, kalan kod kismini kontrol et
    SPLIT iv_line AT '"' INTO DATA(lv_code) DATA(lv_rest).
    IF lv_code CS mv_tok.
      rv_yes = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD add_hit.
    APPEND VALUE #( object = iv_object
                    type   = iv_type
                    method = iv_method
                    line   = iv_index
                    code   = iv_line ) TO mt_result.
  ENDMETHOD.

  METHOD display.
    IF mt_result IS INITIAL.
      MESSAGE 'Kriterlere uyan REFRESH kullanimi bulunamadi.' TYPE 'I'.
      RETURN.
    ENDIF.

    SORT mt_result BY object method line.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_alv)
          CHANGING  t_table      = mt_result ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).

        lo_alv->get_display_settings( )->set_list_header(
          |REFRESH @ { mv_meth } - { lines( mt_result ) } bulgu| ).

        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->get_column( 'OBJECT' )->set_short_text( 'Object' ).
        lo_cols->get_column( 'TYPE'   )->set_short_text( 'Type' ).
        lo_cols->get_column( 'METHOD' )->set_short_text( 'Method' ).
        lo_cols->get_column( 'LINE'   )->set_short_text( 'Line' ).
        lo_cols->get_column( 'CODE'   )->set_short_text( 'Code' ).
        lo_cols->get_column( 'CODE'   )->set_long_text( 'Coding' ).

        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_scanner( )->run( ).
