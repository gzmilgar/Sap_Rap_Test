REPORT zgilgar_split_form_check.

"&---------------------------------------------------------------------*
"& Report  ZGILGAR_SPLIT_FORM_CHECK
"&---------------------------------------------------------------------*
"& ZSPLIT cercevesi (ZWBC0001_SPLTHDR) icin: her kayitta kaynak standart
"& FORM (SPROG/SFORM - genelde enhancement/user-exit include'i) ile bizim
"& Z kopya FORM (DPROG/DFORM) imzalari karsilastirilir.
"&
"& Upgrade sonrasi standart exit/BAdI/FORM parametreleri degisince, donmus
"& Z kopyanin TABLES/USING/CHANGING arayuzu artik eslesmez. Bu rapor
"& eslesmeyen (veya kaynagi/kopya formu artik bulunamayan) kayitlari
"& listeler.
"&
"& Kaynak iki turlu olabilir:
"&  * FORM  : SPROG/SFORM klasik subroutine. Karsilastirma POZISYONELdir
"&           (PERFORM pozisyonel): ad yok sayilir, kind + tip karsilastirilir.
"&  * FM    : SPROG bir SAPL* function-grup main programi ise SFORM bir
"&           function module adidir. FM arayuzu FUPARAREF'ten okunur.
"&           Enhancement icinde ZBC_FM_SPLIT_FIND ile bulunan formlara
"&           PERFORM (dform) IN PROGRAM (dprog) USING ... cagrisi FM
"&           parametrelerini AYNI ISIMLE gectiginden, Z form parametreleri
"&           FM arayuzu ile ISIM BAZLI karsilastirilir.
"&
"& DDIC yapilarinin (LIPS, LIKP...) ic alan degisiklikleri bu statik
"& karsilastirma ile yakalanmaz - parametre eklenmesi/cikarilmasi/yeniden
"& adlandirilmasi ve tip referansi degisimi yakalanir.
"&
"& NOT: Tablo adi kuruluma gore degisebilir; gerekirse ZWBC0001_SPLTHDR
"&      satirini kendi tablonuzla degistirin.
"&---------------------------------------------------------------------*

DATA: gv_prog TYPE programm,
      gv_form TYPE c LENGTH 30.

SELECT-OPTIONS: s_sprog FOR gv_prog,
                s_sform FOR gv_form,
                s_dprog FOR gv_prog,
                s_dform FOR gv_form.
PARAMETERS: p_onlym AS CHECKBOX DEFAULT 'X'.

CLASS lcl_app DEFINITION.
  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_param,
             kind   TYPE string,        " TABLES / USING / CHANGING
             name   TYPE string,
             pass   TYPE string,        " VALUE (value-by-value) ya da bos
             typing TYPE string,        " TYPE / LIKE / STRUCTURE
             type   TYPE string,        " tip referansi
           END OF ty_param,
           tt_param TYPE STANDARD TABLE OF ty_param WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_cache,
             prog   TYPE programm,
             form   TYPE string,
             found  TYPE abap_bool,
             kind   TYPE string,        " FORM / FM
             params TYPE tt_param,
           END OF ty_cache.

    TYPES: BEGIN OF ty_inc,
             prog TYPE programm,
             tab  TYPE STANDARD TABLE OF programm WITH DEFAULT KEY,
           END OF ty_inc.

    TYPES: BEGIN OF ty_result,
             sprog    TYPE programm,
             sform    TYPE string,
             src_kind TYPE string,
             dprog    TYPE programm,
             dform    TYPE string,
             status  TYPE string,
             detail  TYPE string,
             src_cnt TYPE i,
             dst_cnt TYPE i,
             src_sig TYPE string,
             dst_sig TYPE string,
             t_color TYPE lvc_t_scol,
           END OF ty_result.

    DATA mt_result TYPE STANDARD TABLE OF ty_result.
    DATA mt_cache  TYPE HASHED TABLE OF ty_cache WITH UNIQUE KEY prog form.
    DATA mt_inc    TYPE HASHED TABLE OF ty_inc   WITH UNIQUE KEY prog.

    METHODS get_includes
      IMPORTING iv_prog       TYPE programm
      RETURNING VALUE(rt_inc) TYPE ty_inc-tab.
    METHODS get_signature
      IMPORTING iv_prog  TYPE programm
                iv_form  TYPE string
      EXPORTING et_param TYPE tt_param
                ev_found TYPE abap_bool
                ev_kind  TYPE string.
    METHODS compare_fm
      IMPORTING it_src    TYPE tt_param
                it_dst    TYPE tt_param
      EXPORTING ev_status TYPE string
                ev_detail TYPE string.
    METHODS strip_comment
      IMPORTING iv_line   TYPE string
      RETURNING VALUE(rv) TYPE string.
    METHODS read_header
      IMPORTING it_src    TYPE string_table
                iv_start  TYPE i
      RETURNING VALUE(rv) TYPE string.
    METHODS parse_header
      IMPORTING iv_header       TYPE string
      RETURNING VALUE(rt_param) TYPE tt_param.
    METHODS build_norm
      IMPORTING it_param  TYPE tt_param
      RETURNING VALUE(rv) TYPE string.
    METHODS build_human
      IMPORTING it_param  TYPE tt_param
      RETURNING VALUE(rv) TYPE string.
    METHODS diff_detail
      IMPORTING it_src    TYPE tt_param
                it_dst    TYPE tt_param
      RETURNING VALUE(rv) TYPE string.
    METHODS display.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    SELECT DISTINCT dprog, dform, sprog, sform
      FROM zwbc0001_splthdr
      INTO TABLE @DATA(lt_hdr)
      WHERE sprog IN @s_sprog
        AND sform IN @s_sform
        AND dprog IN @s_dprog
        AND dform IN @s_dform
      ORDER BY sprog, sform, dprog, dform.
    IF sy-subrc <> 0.
      MESSAGE 'Kritere uyan split kaydi bulunamadi.' TYPE 'I'.
      RETURN.
    ENDIF.

    LOOP AT lt_hdr INTO DATA(ls_hdr).
      get_signature( EXPORTING iv_prog  = CONV #( ls_hdr-sprog )
                               iv_form  = CONV #( ls_hdr-sform )
                     IMPORTING et_param = DATA(lt_src)
                               ev_found = DATA(lv_src_found)
                               ev_kind  = DATA(lv_src_kind) ).
      get_signature( EXPORTING iv_prog  = CONV #( ls_hdr-dprog )
                               iv_form  = CONV #( ls_hdr-dform )
                     IMPORTING et_param = DATA(lt_dst)
                               ev_found = DATA(lv_dst_found) ).

      DATA(ls_res) = VALUE ty_result(
        sprog    = ls_hdr-sprog
        sform    = ls_hdr-sform
        src_kind = lv_src_kind
        dprog    = ls_hdr-dprog
        dform    = ls_hdr-dform
        src_cnt  = lines( lt_src )
        dst_cnt  = lines( lt_dst )
        src_sig  = build_human( lt_src )
        dst_sig  = build_human( lt_dst ) ).

      DATA(lv_ok) = abap_false.
      IF lv_src_found = abap_false AND lv_dst_found = abap_false.
        ls_res-status = 'HER IKI TARAF DA YOK'.
        ls_res-detail = 'Kaynak FORM/FM ve zsplit form bulunamadi'.
      ELSEIF lv_src_found = abap_false.
        ls_res-status = 'KAYNAK FORM/FM YOK'.
        ls_res-detail = 'Standart form/FM bulunamadi (upgrade ile silinmis/yeniden adlandirilmis olabilir)'.
      ELSEIF lv_dst_found = abap_false.
        ls_res-status = 'ZSPLIT FORM YOK'.
        ls_res-detail = 'Z kopya form bulunamadi'.
      ELSEIF lv_src_kind = 'FM'.
        " kaynak FM -> Z form parametreleri isim bazli karsilastirilir
        compare_fm( EXPORTING it_src    = lt_src
                              it_dst    = lt_dst
                    IMPORTING ev_status = ls_res-status
                              ev_detail = ls_res-detail ).
        IF ls_res-status = 'ESLESIYOR'.
          lv_ok = abap_true.
        ENDIF.
      ELSEIF build_norm( lt_src ) = build_norm( lt_dst ).
        ls_res-status = 'ESLESIYOR'.
        lv_ok = abap_true.
      ELSE.
        ls_res-status = 'PARAMETRE UYUSMUYOR'.
        ls_res-detail = diff_detail( it_src = lt_src it_dst = lt_dst ).
      ENDIF.

      " satir rengi: yesil = eslesti, kirmizi = sorun
      ls_res-t_color = VALUE #( ( fname = space
                                  color = VALUE #( col = COND i( WHEN lv_ok = abap_true THEN 5 ELSE 6 ) ) ) ).

      IF p_onlym = abap_true AND lv_ok = abap_true.
        CONTINUE.
      ENDIF.
      APPEND ls_res TO mt_result.
    ENDLOOP.

    display( ).
  ENDMETHOD.

  METHOD get_includes.
    READ TABLE mt_inc INTO DATA(ls_inc) WITH KEY prog = iv_prog.
    IF sy-subrc = 0.
      rt_inc = ls_inc-tab.
      RETURN.
    ENDIF.

    APPEND iv_prog TO rt_inc.

    DATA lt_raw TYPE STANDARD TABLE OF programm.
    CALL FUNCTION 'RS_GET_ALL_INCLUDES'
      EXPORTING
        program      = iv_prog
      TABLES
        includetab   = lt_raw
      EXCEPTIONS
        not_existent = 1
        no_program   = 2
        OTHERS       = 3.
    IF sy-subrc = 0.
      APPEND LINES OF lt_raw TO rt_inc.
    ENDIF.

    SORT rt_inc.
    DELETE ADJACENT DUPLICATES FROM rt_inc.
    INSERT VALUE #( prog = iv_prog tab = rt_inc ) INTO TABLE mt_inc.
  ENDMETHOD.

  METHOD get_signature.
    DATA(lv_form_u) = to_upper( condense( iv_form ) ).

    READ TABLE mt_cache INTO DATA(ls_cache)
         WITH KEY prog = iv_prog form = lv_form_u.
    IF sy-subrc = 0.
      et_param = ls_cache-params.
      ev_found = ls_cache-found.
      ev_kind  = ls_cache-kind.
      RETURN.
    ENDIF.

    CLEAR: et_param, ev_found, ev_kind.
    DATA(lt_inc) = get_includes( iv_prog ).

    LOOP AT lt_inc INTO DATA(lv_inc).
      DATA lt_src TYPE string_table.
      READ REPORT lv_inc INTO lt_src.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      LOOP AT lt_src INTO DATA(lv_line).
        DATA(lv_idx)  = sy-tabix.
        DATA(lv_code) = to_upper( condense( strip_comment( lv_line ) ) ).

        DATA lv_fname TYPE string.
        CLEAR lv_fname.
        FIND REGEX '^FORM\s+([A-Z0-9_]+)' IN lv_code SUBMATCHES lv_fname.
        IF sy-subrc = 0 AND lv_fname = lv_form_u.
          DATA(lv_header) = read_header( it_src = lt_src iv_start = lv_idx ).
          et_param = parse_header( lv_header ).
          ev_found = abap_true.
          ev_kind  = 'FORM'.
          EXIT.
        ENDIF.
      ENDLOOP.

      IF ev_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    " FORM bulunamadi -> SFORM bir function module olabilir.
    " (SAPL* programlari function grup main programidir; SFORM = FM adi.)
    " FM arayuzu FUPARAREF'ten okunur; enhancement icindeki
    " PERFORM (dform) IN PROGRAM (dprog) USING ... cagrisi FM parametrelerini
    " ayni isimle gectiginden Z form ile isim bazli karsilastirilir.
    IF ev_found = abap_false.
      DATA lv_func TYPE rs38l_fnam.
      lv_func = lv_form_u.
      SELECT parameter, paramtype, structure
        FROM fupararef
        INTO TABLE @DATA(lt_fp)
        WHERE funcname = @lv_func
          AND r3state  = 'A'.
      IF sy-subrc = 0.
        LOOP AT lt_fp INTO DATA(ls_fp).
          DATA(lv_k) = SWITCH string( ls_fp-paramtype
                         WHEN 'I' THEN 'IMPORTING'
                         WHEN 'E' THEN 'EXPORTING'
                         WHEN 'C' THEN 'CHANGING'
                         WHEN 'T' THEN 'TABLES'
                         ELSE space ).
          IF lv_k IS INITIAL.
            CONTINUE.                          " exception vs.
          ENDIF.
          APPEND VALUE #( kind = lv_k
                          name = to_upper( CONV string( ls_fp-parameter ) )
                          type = to_upper( CONV string( ls_fp-structure ) ) ) TO et_param.
        ENDLOOP.
        ev_found = abap_true.
        ev_kind  = 'FM'.
      ENDIF.
    ENDIF.

    INSERT VALUE #( prog   = iv_prog
                    form   = lv_form_u
                    found  = ev_found
                    kind   = ev_kind
                    params = et_param ) INTO TABLE mt_cache.
  ENDMETHOD.

  METHOD strip_comment.
    DATA(lv_c) = condense( iv_line ).
    IF lv_c IS INITIAL OR lv_c(1) = '*'.
      rv = ''.
      RETURN.
    ENDIF.
    " satir ici yorumu ( " ) at
    SPLIT iv_line AT '"' INTO rv DATA(lv_rest).
  ENDMETHOD.

  METHOD read_header.
    " FORM ifadesi cok satira yayilabilir; ilk noktaya kadar topla.
    DATA lv TYPE string.
    LOOP AT it_src FROM iv_start INTO DATA(lv_line).
      DATA(lv_code) = strip_comment( lv_line ).
      IF lv_code CS '.'.
        SPLIT lv_code AT '.' INTO DATA(lv_before) DATA(lv_after).
        lv = lv && ` ` && lv_before.
        EXIT.
      ELSE.
        lv = lv && ` ` && lv_code.
      ENDIF.
    ENDLOOP.
    rv = condense( to_upper( lv ) ).
  ENDMETHOD.

  METHOD parse_header.
    SPLIT iv_header AT ` ` INTO TABLE DATA(lt_w).
    DELETE lt_w WHERE table_line IS INITIAL.
    DATA(lv_n) = lines( lt_w ).
    IF lv_n < 2.
      RETURN.
    ENDIF.

    DATA lv_kind TYPE string.
    DATA(lv_i) = 3.                              " FORM <ad> atlanir
    WHILE lv_i <= lv_n.
      DATA(lv_w) = lt_w[ lv_i ].

      IF lv_w = 'TABLES' OR lv_w = 'USING' OR lv_w = 'CHANGING'.
        lv_kind = lv_w.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.
      IF lv_w = 'RAISING'.
        EXIT.
      ENDIF.

      IF lv_w = 'TYPE' OR lv_w = 'LIKE' OR lv_w = 'STRUCTURE'.
        DATA(lv_typing) = lv_w.
        DATA lv_type TYPE string.
        CLEAR lv_type.
        IF lv_w = 'TYPE' AND lv_i + 1 <= lv_n AND lt_w[ lv_i + 1 ] = 'REF'.
          IF lv_i + 3 <= lv_n.
            lv_type = |REF TO { lt_w[ lv_i + 3 ] }|.
          ELSE.
            lv_type = 'REF TO'.
          ENDIF.
          lv_i = lv_i + 4.
        ELSE.
          IF lv_i + 1 <= lv_n.
            lv_type = lt_w[ lv_i + 1 ].
          ENDIF.
          lv_i = lv_i + 2.
        ENDIF.
        IF rt_param IS NOT INITIAL.
          DATA(lv_last) = lines( rt_param ).
          rt_param[ lv_last ]-typing = lv_typing.
          rt_param[ lv_last ]-type   = lv_type.
        ENDIF.
        CONTINUE.
      ENDIF.

      IF lv_w = '(' OR lv_w = ')'.
        lv_i = lv_i + 1.
        CONTINUE.
      ENDIF.

      " parametre adi (gerekirse VALUE(...) cozulur)
      DATA(lv_name) = lv_w.
      DATA(lv_pass) = ``.
      IF lv_name CP 'VALUE(*'.
        lv_pass = 'VALUE'.
        REPLACE ALL OCCURRENCES OF 'VALUE(' IN lv_name WITH ``.
        REPLACE ALL OCCURRENCES OF ')'      IN lv_name WITH ``.
      ENDIF.
      IF lv_name IS NOT INITIAL AND lv_kind IS NOT INITIAL.
        APPEND VALUE #( kind = lv_kind name = lv_name pass = lv_pass ) TO rt_param.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD build_norm.
    " pozisyonel imza: ad yok sayilir, kind + tip referansi
    LOOP AT it_param INTO DATA(ls).
      rv = |{ rv }{ ls-kind }[{ ls-type }];|.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_human.
    LOOP AT it_param INTO DATA(ls).
      DATA(lv_t) = COND string( WHEN ls-type IS NOT INITIAL THEN | { ls-typing } { ls-type }| ELSE `` ).
      DATA(lv_v) = COND string( WHEN ls-pass = 'VALUE' THEN |VALUE({ ls-name })| ELSE ls-name ).
      rv = |{ rv }{ ls-kind } { lv_v }{ lv_t } / |.
    ENDLOOP.
  ENDMETHOD.

  METHOD diff_detail.
    IF lines( it_src ) <> lines( it_dst ).
      rv = |Parametre sayisi farkli: kaynak={ lines( it_src ) } / zsplit={ lines( it_dst ) }|.
      RETURN.
    ENDIF.
    LOOP AT it_src INTO DATA(ls_s).
      DATA(lv_i) = sy-tabix.
      DATA(ls_d) = VALUE #( it_dst[ lv_i ] OPTIONAL ).
      IF ls_s-kind <> ls_d-kind OR ls_s-type <> ls_d-type.
        rv = |Poz { lv_i }: kaynak [{ ls_s-kind } { ls_s-type }] <> zsplit [{ ls_d-kind } { ls_d-type }]|.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv = 'Tip/siralama farki'.
  ENDMETHOD.

  METHOD compare_fm.
    " Z form parametrelerini (it_dst) kaynak FM arayuzu (it_src) ile isim
    " bazli karsilastir. Kind (USING/IMPORTING...) yok sayilir; cunku
    " enhancement FM importing/exporting parametrelerini USING ile geciyor.
    " Z form FM'in alt kumesini kullandigindan ters yon kontrol edilmez.
    DATA lt_issue   TYPE string_table.
    DATA lv_missing TYPE abap_bool.

    LOOP AT it_dst INTO DATA(ls_d).
      READ TABLE it_src INTO DATA(ls_s) WITH KEY name = ls_d-name.
      IF sy-subrc <> 0.
        APPEND |'{ ls_d-name }' kaynak FM arayuzunde yok| TO lt_issue.
        lv_missing = abap_true.
      ELSEIF ls_d-type IS NOT INITIAL AND ls_s-type IS NOT INITIAL
         AND ls_d-type <> ls_s-type.
        APPEND |'{ ls_d-name }' tip farkli: FM[{ ls_s-type }] <> Z[{ ls_d-type }]| TO lt_issue.
      ENDIF.
    ENDLOOP.

    IF lt_issue IS INITIAL.
      ev_status = 'ESLESIYOR'.
    ELSEIF lv_missing = abap_true.
      ev_status = 'PARAMETRE UYUSMUYOR'.
    ELSE.
      ev_status = 'TIP FARKLI'.
    ENDIF.
    ev_detail = concat_lines_of( table = lt_issue sep = `; ` ).
  ENDMETHOD.

  METHOD display.
    IF mt_result IS INITIAL.
      MESSAGE 'Uyusmayan form bulunamadi (tum imzalar eslesiyor).' TYPE 'I'.
      RETURN.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = DATA(lo_alv)
          CHANGING  t_table      = mt_result ).

        lo_alv->get_functions( )->set_all( abap_true ).

        DATA(lo_cols) = lo_alv->get_columns( ).
        lo_cols->set_optimize( abap_true ).
        lo_cols->set_color_column( 'T_COLOR' ).

        lo_cols->get_column( 'SPROG'    )->set_short_text( 'Src Prog' ).
        lo_cols->get_column( 'SFORM'    )->set_short_text( 'Src Form' ).
        lo_cols->get_column( 'SRC_KIND' )->set_short_text( 'Src Kind' ).
        lo_cols->get_column( 'DPROG'   )->set_short_text( 'Z Prog' ).
        lo_cols->get_column( 'DFORM'   )->set_short_text( 'Z Form' ).
        lo_cols->get_column( 'STATUS'  )->set_short_text( 'Status' ).
        lo_cols->get_column( 'DETAIL'  )->set_short_text( 'Detail' ).
        lo_cols->get_column( 'SRC_CNT' )->set_short_text( 'Src #' ).
        lo_cols->get_column( 'DST_CNT' )->set_short_text( 'Z #' ).
        lo_cols->get_column( 'SRC_SIG' )->set_short_text( 'Src Sig' ).
        lo_cols->get_column( 'DST_SIG' )->set_short_text( 'Z Sig' ).
        lo_cols->get_column( 'SRC_SIG' )->set_long_text( 'Source signature' ).
        lo_cols->get_column( 'DST_SIG' )->set_long_text( 'Z-copy signature' ).

        lo_alv->get_display_settings( )->set_list_header(
          |ZSPLIT FORM parametre kontrolu - { lines( mt_result ) } bulgu| ).

        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
