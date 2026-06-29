REPORT zgilgar_split_form_check.

"&---------------------------------------------------------------------*
"& Report  ZGILGAR_SPLIT_FORM_CHECK
"&---------------------------------------------------------------------*
"& ZSPLIT cercevesi (ZWBC0001_SPLTHDR) icin: her kayitta, kaynak
"& exit/form/FM icindeki ZBC_FM_SPLIT_FIND'den sonra cagrilan DINAMIK
"&   PERFORM (dform) IN PROGRAM (dprog) [TABLES..][USING..][CHANGING..]
"& ifadesinin parametre profili (TABLES/USING/CHANGING sayisi) ile,
"& Z split formunun (DPROG/DFORM) formal parametre profili karsilastirilir.
"&
"& Dinamik PERFORM cagrisinin calisma-zamani sozlesmesi: TABLES/USING/
"& CHANGING parametre SAYILARI form ile birebir uymak zorundadir; uymazsa
"& CX_SY_DYN_CALL_PARAM_* dump olur. Upgrade sonrasi exit/FM degisip de
"& Z form guncellenmediyse bu sayilar tutmaz -> rapor bunu listeler.
"&
"& Iki karsilastirma modu (MODE kolonu):
"&  * PERFORM : sform govdesinde dinamik PERFORM bulundu -> U/C/T sayilari.
"&  * FM      : PERFORM yok ve kaynak bir function module -> Z form param.
"&             FM arayuzu (FUPARAREF) ile ISIM bazli karsilastirilir.
"&
"& Kaynak PERFORM'un yeri:
"&  * Customer-exit FM (EXIT_*): FM govdesi -> INCLUDE Zxxx -> dogrudan
"&    ZBC_FM_SPLIT_FIND + PERFORM. READ REPORT + INCLUDE zinciri ile bulunur.
"&  * Klasik FORM exit: FORM govdesi / include'u.
"&  * Enhancement (form ICINDE): kaynak once CL_WB_PGEDITOR=>READ_SOURCE
"&    ile enhancement'lar INLINE gomulu okunur; boylece form govdesindeki
"&    enhancement de form-bazli (SAPMV45A'daki cok sayida userexit gibi)
"&    tam eslestirilir. (Dinamik cagri; API yoksa READ REPORT'a duser.)
"&  * Enhancement (cozulemeyen): READ REPORT/READ_SOURCE ile gorulemezse
"&    ZBC_FM_SPLIT_FIND
"&    where-used (RS_EU_CROSSREF) ile tum cagri yerleri bulunur; her cagri
"&    yerindeki include okunup PERFORM imzasi cikarilir ve ana programa
"&    (ENCL_OBJEC) gore eslestirilir. Bir programda birden fazla FARKLI
"&    imza varsa 'ENHANCEMENT BELIRSIZ' (manuel kontrol) isaretlenir.
"&
"& sform'a gore CAPALANIR (bir function grupta birden cok exit ve farkli
"& PERFORM imzasi olabilir).
"&
"& NOT: Tablo adi kuruluma gore degisebilir; gerekirse ZWBC0001_SPLTHDR.
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
             typing TYPE string,
             type   TYPE string,
           END OF ty_param,
           tt_param TYPE STANDARD TABLE OF ty_param WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_inc,
             prog TYPE programm,
             tab  TYPE STANDARD TABLE OF programm WITH DEFAULT KEY,
           END OF ty_inc.

    TYPES: BEGIN OF ty_src,
             prog TYPE programm,
             src  TYPE string_table,
           END OF ty_src.

    TYPES: BEGIN OF ty_fcache,
             prog   TYPE programm,
             form   TYPE string,
             found  TYPE abap_bool,
             params TYPE tt_param,
           END OF ty_fcache.

    TYPES: BEGIN OF ty_pcache,
             prog  TYPE programm,
             form  TYPE string,
             found TYPE abap_bool,
             kind  TYPE string,         " FM / FORM
             u     TYPE i,
             c     TYPE i,
             t     TYPE i,
             raw   TYPE string,
           END OF ty_pcache.

    TYPES: BEGIN OF ty_result,
             sprog    TYPE programm,
             sform    TYPE string,
             src_kind TYPE string,
             mode     TYPE string,
             dprog    TYPE programm,
             dform    TYPE string,
             status   TYPE string,
             detail   TYPE string,
             perf_u   TYPE i,
             perf_c   TYPE i,
             perf_t   TYPE i,
             z_u      TYPE i,
             z_c      TYPE i,
             z_t      TYPE i,
             perf_raw TYPE string,
             z_sig    TYPE string,
             t_color  TYPE lvc_t_scol,
           END OF ty_result.

    DATA mt_result TYPE STANDARD TABLE OF ty_result.
    TYPES: BEGIN OF ty_wu,
             prog      TYPE programm,
             found     TYPE abap_bool,
             u         TYPE i,
             c         TYPE i,
             t         TYPE i,
             ambiguous TYPE abap_bool,
           END OF ty_wu.

    DATA mt_inc     TYPE HASHED TABLE OF ty_inc    WITH UNIQUE KEY prog.
    DATA mt_src     TYPE HASHED TABLE OF ty_src    WITH UNIQUE KEY prog.
    DATA mt_fcache  TYPE HASHED TABLE OF ty_fcache WITH UNIQUE KEY prog form.
    DATA mt_pcache  TYPE HASHED TABLE OF ty_pcache WITH UNIQUE KEY prog form.
    TYPES: BEGIN OF ty_ficache,
             func   TYPE string,
             params TYPE tt_param,
           END OF ty_ficache.

    DATA mt_wu      TYPE HASHED TABLE OF ty_wu      WITH UNIQUE KEY prog.
    DATA mv_wu_done TYPE abap_bool.
    DATA mo_editor  TYPE REF TO object.
    DATA mv_ed_fail TYPE abap_bool.
    DATA mt_ficache TYPE HASHED TABLE OF ty_ficache WITH UNIQUE KEY func.

    METHODS get_includes
      IMPORTING iv_prog       TYPE programm
      RETURNING VALUE(rt_inc) TYPE ty_inc-tab.
    METHODS read_src
      IMPORTING iv_prog    TYPE programm
      RETURNING VALUE(rt)  TYPE string_table.
    METHODS read_enhanced
      IMPORTING iv_prog   TYPE programm
      RETURNING VALUE(rt) TYPE string_table.
    METHODS strip_comment
      IMPORTING iv_line   TYPE string
      RETURNING VALUE(rv) TYPE string.
    METHODS words
      IMPORTING iv_line   TYPE string
      RETURNING VALUE(rt) TYPE string_table.
    METHODS word_at
      IMPORTING it_w      TYPE string_table
                iv_idx    TYPE i
      RETURNING VALUE(rv) TYPE string.
    METHODS read_stmt
      IMPORTING it_src    TYPE string_table
                iv_start  TYPE i
      RETURNING VALUE(rv) TYPE string.
    METHODS parse_header
      IMPORTING iv_header       TYPE string
      RETURNING VALUE(rt_param) TYPE tt_param.
    METHODS build_human
      IMPORTING it_param  TYPE tt_param
      RETURNING VALUE(rv) TYPE string.
    METHODS get_form_params
      IMPORTING iv_prog  TYPE programm
                iv_form  TYPE string
      EXPORTING et_param TYPE tt_param
                ev_found TYPE abap_bool.
    METHODS get_fm_prog
      IMPORTING iv_form   TYPE string
      EXPORTING ev_is_fm  TYPE abap_bool
                ev_prog   TYPE programm.
    METHODS collect_unit_source
      IMPORTING iv_prog    TYPE programm
                iv_form    TYPE string
                iv_keyword TYPE string
      EXPORTING et_src     TYPE string_table
                ev_found   TYPE abap_bool.
    METHODS find_perform_sig
      IMPORTING iv_prog  TYPE programm
                iv_form  TYPE string
      EXPORTING ev_found TYPE abap_bool
                ev_kind  TYPE string
                ev_u     TYPE i
                ev_c     TYPE i
                ev_t     TYPE i
                ev_raw   TYPE string.
    METHODS parse_perform_counts
      IMPORTING iv_stmt TYPE string
      EXPORTING ev_u    TYPE i
                ev_c    TYPE i
                ev_t    TYPE i.
    METHODS scan_perform
      IMPORTING it_src   TYPE string_table
                iv_from  TYPE i DEFAULT 1
      EXPORTING ev_found TYPE abap_bool
                ev_u     TYPE i
                ev_c     TYPE i
                ev_t     TYPE i
                ev_raw   TYPE string.
    METHODS build_where_used_map.
    METHODS add_wu
      IMPORTING iv_prog TYPE programm
                iv_u    TYPE i
                iv_c    TYPE i
                iv_t    TYPE i.
    METHODS get_fm_interface
      IMPORTING iv_form         TYPE string
      RETURNING VALUE(rt_param) TYPE tt_param.
    METHODS is_class
      IMPORTING iv_prog       TYPE programm
      RETURNING VALUE(rv_yes) TYPE abap_bool.
    METHODS get_method_source
      IMPORTING iv_class  TYPE programm
                iv_method TYPE string
      RETURNING VALUE(rt) TYPE string_table.
    METHODS get_method_interface
      IMPORTING iv_class        TYPE programm
                iv_method       TYPE string
      RETURNING VALUE(rt_param) TYPE tt_param.
    METHODS compare_fm
      IMPORTING it_fm     TYPE tt_param
                it_z      TYPE tt_param
      EXPORTING ev_status TYPE string
                ev_detail TYPE string.
    METHODS display.
    METHODS on_link_click
      FOR EVENT link_click OF cl_salv_events_table
      IMPORTING row column.
    METHODS on_double_click
      FOR EVENT double_click OF cl_salv_events_table
      IMPORTING row column.
    METHODS navigate
      IMPORTING iv_type TYPE trobjtype
                iv_name TYPE string.
    METHODS nav_for_cell
      IMPORTING iv_row TYPE i
                iv_col TYPE string.
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

    " ZBC_FM_SPLIT_FIND where-used haritasi (enhancement icindeki cagrilar icin)
    build_where_used_map( ).

    LOOP AT lt_hdr INTO DATA(ls_hdr).
      " beklenen: kaynak exit/form icindeki dinamik PERFORM imzasi
      find_perform_sig( EXPORTING iv_prog  = CONV #( ls_hdr-sprog )
                                  iv_form  = CONV #( ls_hdr-sform )
                        IMPORTING ev_found = DATA(lv_pfound)
                                  ev_kind  = DATA(lv_kind)
                                  ev_u     = DATA(lv_pu)
                                  ev_c     = DATA(lv_pc)
                                  ev_t     = DATA(lv_pt)
                                  ev_raw   = DATA(lv_raw) ).

      " gerceklesen: Z form formal parametreleri
      get_form_params( EXPORTING iv_prog  = CONV #( ls_hdr-dprog )
                                 iv_form  = CONV #( ls_hdr-dform )
                       IMPORTING et_param = DATA(lt_z)
                                 ev_found = DATA(lv_zfound) ).

      DATA(lv_zu) = REDUCE i( INIT x = 0 FOR p IN lt_z WHERE ( kind = 'USING' )    NEXT x = x + 1 ).
      DATA(lv_zc) = REDUCE i( INIT x = 0 FOR p IN lt_z WHERE ( kind = 'CHANGING' ) NEXT x = x + 1 ).
      DATA(lv_zt) = REDUCE i( INIT x = 0 FOR p IN lt_z WHERE ( kind = 'TABLES' )   NEXT x = x + 1 ).

      DATA(ls_res) = VALUE ty_result(
        sprog    = ls_hdr-sprog
        sform    = ls_hdr-sform
        src_kind = lv_kind
        dprog    = ls_hdr-dprog
        dform    = ls_hdr-dform
        perf_u   = lv_pu
        perf_c   = lv_pc
        perf_t   = lv_pt
        z_u      = lv_zu
        z_c      = lv_zc
        z_t      = lv_zt
        perf_raw = lv_raw
        z_sig    = build_human( lt_z ) ).

      DATA(lv_ok) = abap_false.
      IF lv_zfound = abap_false.
        ls_res-status = 'ZSPLIT FORM YOK'.
        ls_res-detail = 'Z kopya form bulunamadi'.

      ELSEIF lv_pfound = abap_true.
        " --- PERFORM modu: sform govdesindeki dinamik PERFORM ---
        ls_res-mode = 'PERFORM'.
        IF lv_pu = lv_zu AND lv_pc = lv_zc AND lv_pt = lv_zt.
          ls_res-status = 'ESLESIYOR'.
          lv_ok = abap_true.
        ELSE.
          ls_res-status = 'PARAMETRE UYUSMUYOR'.
          ls_res-detail = |PERFORM[U={ lv_pu } C={ lv_pc } T={ lv_pt }]| &&
                          | <> Zform[U={ lv_zu } C={ lv_zc } T={ lv_zt }]|.
        ENDIF.

      ELSEIF lv_kind = 'FM'.
        " --- FM arayuzu modu: PERFORM yok, kaynak bir function module ---
        DATA(lt_fm) = get_fm_interface( CONV #( ls_hdr-sform ) ).
        IF lt_fm IS NOT INITIAL.
          ls_res-mode = 'FM'.
          compare_fm( EXPORTING it_fm     = lt_fm
                                it_z      = lt_z
                      IMPORTING ev_status = ls_res-status
                                ev_detail = ls_res-detail ).
          IF ls_res-status = 'ESLESIYOR'.
            lv_ok = abap_true.
          ENDIF.
        ELSE.
          ls_res-status = 'PERFORM BULUNAMADI'.
          ls_res-detail = 'Dinamik PERFORM yok, FM arayuzu da okunamadi'.
        ENDIF.

      ELSEIF lv_kind = 'METHOD'.
        " --- METHOD arayuzu modu: PERFORM yok, kaynak bir SE24 sinif metodu ---
        DATA(lt_meth) = get_method_interface( iv_class  = ls_hdr-sprog
                                              iv_method = CONV #( ls_hdr-sform ) ).
        IF lt_meth IS NOT INITIAL.
          ls_res-mode = 'METHOD'.
          compare_fm( EXPORTING it_fm     = lt_meth
                                it_z      = lt_z
                      IMPORTING ev_status = ls_res-status
                                ev_detail = ls_res-detail ).
          IF ls_res-status = 'ESLESIYOR'.
            lv_ok = abap_true.
          ENDIF.
        ELSE.
          ls_res-status = 'PERFORM BULUNAMADI'.
          ls_res-detail = 'Dinamik PERFORM yok, metot arayuzu da okunamadi'.
        ENDIF.

      ELSE.
        " --- FORM ama govdesinde PERFORM yok -> where-used (program) fallback ---
        READ TABLE mt_wu INTO DATA(ls_wu) WITH KEY prog = CONV programm( ls_hdr-sprog ).
        IF sy-subrc = 0 AND ls_wu-found = abap_true AND ls_wu-ambiguous = abap_true.
          ls_res-status = 'ENHANCEMENT BELIRSIZ'.
          ls_res-detail = 'where-used: programda birden fazla farkli PERFORM imzasi - manuel kontrol'.
        ELSEIF sy-subrc = 0 AND ls_wu-found = abap_true.
          ls_res-mode = 'PERFORM'.
          ls_res-perf_u = ls_wu-u. ls_res-perf_c = ls_wu-c. ls_res-perf_t = ls_wu-t.
          ls_res-perf_raw = |where-used PERFORM: U={ ls_wu-u } C={ ls_wu-c } T={ ls_wu-t }|.
          IF ls_wu-u = lv_zu AND ls_wu-c = lv_zc AND ls_wu-t = lv_zt.
            ls_res-status = 'ESLESIYOR'.
            lv_ok = abap_true.
          ELSE.
            ls_res-status = 'PARAMETRE UYUSMUYOR'.
            ls_res-detail = |PERFORM[U={ ls_wu-u } C={ ls_wu-c } T={ ls_wu-t }]| &&
                            | <> Zform[U={ lv_zu } C={ lv_zc } T={ lv_zt }]|.
          ENDIF.
        ELSE.
          ls_res-status = 'PERFORM BULUNAMADI'.
          ls_res-detail = 'Kaynaktaki dinamik PERFORM okunamadi (enhancement icinde olabilir)'.
        ENDIF.
      ENDIF.

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

  METHOD read_src.
    READ TABLE mt_src INTO DATA(ls) WITH KEY prog = iv_prog.
    IF sy-subrc = 0.
      rt = ls-src.
      RETURN.
    ENDIF.

    " Once enhancement'lar inline gomulu kaynagi dene (SAPMV45A gibi form
    " icindeki ZBC_FM_SPLIT_FIND enhancement'lari boylece form-bazli yakalanir),
    " olmazsa ham READ REPORT.
    rt = read_enhanced( iv_prog ).
    IF rt IS INITIAL.
      READ REPORT iv_prog INTO rt.
    ENDIF.

    INSERT VALUE #( prog = iv_prog src = rt ) INTO TABLE mt_src.
  ENDMETHOD.

  METHOD read_enhanced.
    " CL_WB_PGEDITOR=>READ_SOURCE enhancement'lari satir arasina gomer.
    " API tipinden bagimsiz kalmak icin dinamik cagrilir; hata olursa
    " bir daha denenmez ve READ REPORT'a dusulur.
    IF mv_ed_fail = abap_true.
      RETURN.
    ENDIF.

    TRY.
        IF mo_editor IS NOT BOUND.
          CREATE OBJECT mo_editor TYPE ('CL_WB_PGEDITOR')
            EXPORTING p_is_in_adjustment_mode = abap_false.
        ENDIF.

        DATA lr_tab TYPE REF TO data.
        CREATE DATA lr_tab TYPE ('SEDI_SOURCE').
        ASSIGN lr_tab->* TO FIELD-SYMBOL(<tab>).

        CALL METHOD mo_editor->('READ_SOURCE')
          EXPORTING
            source_name            = iv_prog
            with_impl_enhancements = abap_true
          IMPORTING
            source_tab             = <tab>
          EXCEPTIONS
            OTHERS                 = 1.
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.

        LOOP AT <tab> ASSIGNING FIELD-SYMBOL(<ln>).
          DATA lv_line TYPE string.
          lv_line = <ln>.
          APPEND lv_line TO rt.
        ENDLOOP.

      CATCH cx_root.
        mv_ed_fail = abap_true.       " API yok/uyumsuz -> bir daha deneme
        CLEAR rt.
    ENDTRY.
  ENDMETHOD.

  METHOD strip_comment.
    DATA(lv_c) = condense( iv_line ).
    IF lv_c IS INITIAL OR lv_c(1) = '*'.
      rv = ''.
      RETURN.
    ENDIF.
    SPLIT iv_line AT '"' INTO rv DATA(lv_rest).
  ENDMETHOD.

  METHOD words.
    DATA(lv) = to_upper( condense( strip_comment( iv_line ) ) ).
    SPLIT lv AT ` ` INTO TABLE rt.
    DELETE rt WHERE table_line IS INITIAL.
  ENDMETHOD.

  METHOD word_at.
    rv = VALUE #( it_w[ iv_idx ] OPTIONAL ).
    REPLACE ALL OCCURRENCES OF '.' IN rv WITH ''.
    REPLACE ALL OCCURRENCES OF ',' IN rv WITH ''.
  ENDMETHOD.

  METHOD read_stmt.
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

  METHOD get_form_params.
    DATA(lv_form_u) = to_upper( condense( iv_form ) ).
    READ TABLE mt_fcache INTO DATA(ls_c) WITH KEY prog = iv_prog form = lv_form_u.
    IF sy-subrc = 0.
      et_param = ls_c-params.
      ev_found = ls_c-found.
      RETURN.
    ENDIF.

    CLEAR: et_param, ev_found.
    LOOP AT get_includes( iv_prog ) INTO DATA(lv_inc).
      DATA(lt_src) = read_src( lv_inc ).
      LOOP AT lt_src INTO DATA(lv_line).
        DATA(lv_idx) = sy-tabix.
        DATA(lt_w)   = words( lv_line ).
        IF word_at( it_w = lt_w iv_idx = 1 ) = 'FORM'
           AND word_at( it_w = lt_w iv_idx = 2 ) = lv_form_u.
          et_param = parse_header( read_stmt( it_src = lt_src iv_start = lv_idx ) ).
          ev_found = abap_true.
          EXIT.
        ENDIF.
      ENDLOOP.
      IF ev_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    INSERT VALUE #( prog = iv_prog form = lv_form_u found = ev_found params = et_param )
           INTO TABLE mt_fcache.
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
          ENDIF.
          lv_i = lv_i + 4.
        ELSE.
          IF lv_i + 1 <= lv_n.
            lv_type = lt_w[ lv_i + 1 ].
          ENDIF.
          lv_i = lv_i + 2.
        ENDIF.
        IF rt_param IS NOT INITIAL AND lv_type IS NOT INITIAL.
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

      DATA(lv_name) = lv_w.
      IF lv_name CP 'VALUE(*'.
        REPLACE ALL OCCURRENCES OF 'VALUE(' IN lv_name WITH ``.
        REPLACE ALL OCCURRENCES OF ')'      IN lv_name WITH ``.
      ENDIF.
      IF lv_name IS NOT INITIAL AND lv_kind IS NOT INITIAL.
        APPEND VALUE #( kind = lv_kind name = lv_name ) TO rt_param.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD build_human.
    LOOP AT it_param INTO DATA(ls).
      DATA(lv_t) = COND string( WHEN ls-type IS NOT INITIAL THEN | { ls-typing } { ls-type }| ELSE `` ).
      rv = |{ rv }{ ls-kind } { ls-name }{ lv_t } / |.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_fm_prog.
    CLEAR: ev_is_fm, ev_prog.
    DATA lv_func TYPE rs38l_fnam.
    lv_func = to_upper( condense( iv_form ) ).
    SELECT SINGLE pname FROM tfdir INTO @DATA(lv_pname) WHERE funcname = @lv_func.
    IF sy-subrc = 0.
      ev_is_fm = abap_true.
      ev_prog  = lv_pname.
    ENDIF.
  ENDMETHOD.

  METHOD collect_unit_source.
    CLEAR: et_src, ev_found.
    DATA(lv_form_u) = to_upper( condense( iv_form ) ).
    DATA(lv_end)    = |END{ iv_keyword }|.
    DATA lt_worklist TYPE string_table.
    DATA lt_visited  TYPE string_table.

    " 1) <iv_keyword> <iv_form> govdesini bul (FUNCTION ya da FORM)
    LOOP AT get_includes( iv_prog ) INTO DATA(lv_inc).
      DATA(lt_src)    = read_src( lv_inc ).
      DATA(lv_in_unit) = abap_false.
      LOOP AT lt_src INTO DATA(lv_line).
        DATA(lt_w) = words( lv_line ).
        DATA(lv_w1) = word_at( it_w = lt_w iv_idx = 1 ).
        DATA(lv_w2) = word_at( it_w = lt_w iv_idx = 2 ).

        IF lv_in_unit = abap_false.
          IF lv_w1 = iv_keyword AND lv_w2 = lv_form_u.
            lv_in_unit = abap_true.
            ev_found   = abap_true.
            APPEND lv_line TO et_src.
          ENDIF.
        ELSE.
          IF lv_w1 = lv_end.
            EXIT.
          ENDIF.
          APPEND lv_line TO et_src.
          IF lv_w1 = 'INCLUDE' AND lv_w2 IS NOT INITIAL AND lv_w2 <> 'STRUCTURE'.
            APPEND lv_w2 TO lt_worklist.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF ev_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF ev_found = abap_false.
      RETURN.
    ENDIF.

    " 2) govdedeki INCLUDE'lari (ic ice) recursive ekle
    WHILE lt_worklist IS NOT INITIAL.
      DATA(lv_cur) = lt_worklist[ 1 ].
      DELETE lt_worklist INDEX 1.
      IF line_exists( lt_visited[ table_line = lv_cur ] ).
        CONTINUE.
      ENDIF.
      APPEND lv_cur TO lt_visited.

      DATA(lt_isrc) = read_src( CONV programm( lv_cur ) ).
      LOOP AT lt_isrc INTO DATA(lv_iline).
        APPEND lv_iline TO et_src.
        DATA(lt_iw) = words( lv_iline ).
        IF word_at( it_w = lt_iw iv_idx = 1 ) = 'INCLUDE'.
          DATA(lv_iw2) = word_at( it_w = lt_iw iv_idx = 2 ).
          IF lv_iw2 IS NOT INITIAL AND lv_iw2 <> 'STRUCTURE'.
            APPEND lv_iw2 TO lt_worklist.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDWHILE.
  ENDMETHOD.

  METHOD find_perform_sig.
    DATA(lv_form_u) = to_upper( condense( iv_form ) ).
    READ TABLE mt_pcache INTO DATA(ls_c) WITH KEY prog = iv_prog form = lv_form_u.
    IF sy-subrc = 0.
      ev_found = ls_c-found. ev_kind = ls_c-kind.
      ev_u = ls_c-u. ev_c = ls_c-c. ev_t = ls_c-t. ev_raw = ls_c-raw.
      RETURN.
    ENDIF.

    CLEAR: ev_found, ev_kind, ev_u, ev_c, ev_t, ev_raw.

    " Kaynagi sinifla (sprog/sform):
    "  * sprog bir SINIF ise -> METHOD (SE24 class method)
    "  * sform TFDIR'de FM ise -> FM (FM'in gercek function-grup PNAME'inde aranir)
    "  * aksi halde -> FORM (sprog icinde); bulunamazsa FM kabul edilir.
    get_fm_prog( EXPORTING iv_form  = iv_form
                 IMPORTING ev_is_fm = DATA(lv_is_fm)
                           ev_prog  = DATA(lv_fm_prog) ).

    DATA lt_comb TYPE string_table.
    DATA lv_unit TYPE abap_bool.

    IF is_class( iv_prog ) = abap_true.
      ev_kind = 'METHOD'.
      lt_comb = get_method_source( iv_class = iv_prog iv_method = iv_form ).
      lv_unit = xsdbool( lt_comb IS NOT INITIAL ).
    ELSEIF lv_is_fm = abap_true.
      ev_kind = 'FM'.
      collect_unit_source( EXPORTING iv_prog    = lv_fm_prog
                                     iv_form    = iv_form
                                     iv_keyword = 'FUNCTION'
                           IMPORTING et_src     = lt_comb
                                     ev_found   = lv_unit ).
    ELSE.
      collect_unit_source( EXPORTING iv_prog    = iv_prog
                                     iv_form    = iv_form
                                     iv_keyword = 'FORM'
                           IMPORTING et_src     = lt_comb
                                     ev_found   = lv_unit ).
      ev_kind = COND #( WHEN lv_unit = abap_true THEN 'FORM' ELSE 'FM' ).
    ENDIF.

    IF lv_unit = abap_true.
      scan_perform( EXPORTING it_src   = lt_comb
                    IMPORTING ev_found = ev_found
                              ev_u     = ev_u
                              ev_c     = ev_c
                              ev_t     = ev_t
                              ev_raw   = ev_raw ).
    ENDIF.

    INSERT VALUE #( prog = iv_prog form = lv_form_u found = ev_found
                    kind = ev_kind u = ev_u c = ev_c t = ev_t raw = ev_raw )
           INTO TABLE mt_pcache.
  ENDMETHOD.

  METHOD parse_perform_counts.
    CLEAR: ev_u, ev_c, ev_t.
    SPLIT iv_stmt AT ` ` INTO TABLE DATA(lt_w).
    DELETE lt_w WHERE table_line IS INITIAL.

    DATA lv_sec TYPE c LENGTH 1.
    LOOP AT lt_w INTO DATA(lv_w).
      CASE lv_w.
        WHEN 'TABLES'.   lv_sec = 'T'.
        WHEN 'USING'.    lv_sec = 'U'.
        WHEN 'CHANGING'. lv_sec = 'C'.
        WHEN 'IF'.       EXIT.            " IF FOUND
        WHEN '(' OR ')'.
          " atla
        WHEN OTHERS.
          CASE lv_sec.
            WHEN 'U'. ev_u = ev_u + 1.
            WHEN 'C'. ev_c = ev_c + 1.
            WHEN 'T'. ev_t = ev_t + 1.
          ENDCASE.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD scan_perform.
    CLEAR: ev_found, ev_u, ev_c, ev_t, ev_raw.
    DATA(lv_from) = COND i( WHEN iv_from > 1 THEN iv_from ELSE 1 ).
    IF lv_from > lines( it_src ).
      RETURN.
    ENDIF.
    LOOP AT it_src FROM lv_from INTO DATA(lv_line).
      DATA(lv_idx) = sy-tabix.
      IF word_at( it_w = words( lv_line ) iv_idx = 1 ) = 'PERFORM'.
        DATA(lv_stmt) = read_stmt( it_src = it_src iv_start = lv_idx ).
        IF lv_stmt CS 'IN PROGRAM'.
          parse_perform_counts( EXPORTING iv_stmt = lv_stmt
                                IMPORTING ev_u    = ev_u
                                          ev_c    = ev_c
                                          ev_t    = ev_t ).
          ev_found = abap_true.
          ev_raw   = lv_stmt.
          RETURN.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_wu.
    IF iv_prog IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE mt_wu ASSIGNING FIELD-SYMBOL(<wu>) WITH KEY prog = iv_prog.
    IF sy-subrc <> 0.
      INSERT VALUE #( prog = iv_prog found = abap_true
                      u = iv_u c = iv_c t = iv_t ) INTO TABLE mt_wu.
    ELSEIF <wu>-u <> iv_u OR <wu>-c <> iv_c OR <wu>-t <> iv_t.
      <wu>-ambiguous = abap_true.
    ENDIF.
  ENDMETHOD.

  METHOD build_where_used_map.
    " ZBC_FM_SPLIT_FIND where-used (enhancement dahil tum cagri yerleri).
    " Her cagri yerindeki include okunup dinamik PERFORM imzasi cikarilir,
    " ana programa (ENCL_OBJEC) ve include'a (PROGRAM) gore haritalanir.
    IF mv_wu_done = abap_true.
      RETURN.
    ENDIF.
    mv_wu_done = abap_true.

    DATA lt_find   TYPE STANDARD TABLE OF string.
    DATA lt_founds TYPE STANDARD TABLE OF rsfindlst.
    APPEND 'ZBC_FM_SPLIT_FIND' TO lt_find.

    CALL FUNCTION 'RS_EU_CROSSREF'
      EXPORTING
        i_find_obj_cls = 'FUNC'
        no_dialog      = 'X'
      TABLES
        i_findstrings  = lt_find
        o_founds       = lt_founds
      EXCEPTIONS
        OTHERS         = 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_founds INTO DATA(ls_f).
      DATA(lv_incl) = CONV programm(
        COND string( WHEN ls_f-program IS NOT INITIAL THEN ls_f-program ELSE ls_f-object ) ).
      IF lv_incl IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_from) = COND i( WHEN ls_f-object_row > 1 THEN ls_f-object_row ELSE 1 ).
      scan_perform( EXPORTING it_src   = read_src( lv_incl )
                              iv_from  = lv_from
                    IMPORTING ev_found = DATA(lv_f)
                              ev_u     = DATA(lv_u)
                              ev_c     = DATA(lv_c)
                              ev_t     = DATA(lv_t) ).
      IF lv_f = abap_false.
        scan_perform( EXPORTING it_src   = read_src( lv_incl )
                                iv_from  = 1
                      IMPORTING ev_found = lv_f
                                ev_u     = lv_u
                                ev_c     = lv_c
                                ev_t     = lv_t ).
      ENDIF.
      IF lv_f = abap_false.
        CONTINUE.
      ENDIF.

      add_wu( iv_prog = CONV programm( ls_f-encl_objec ) iv_u = lv_u iv_c = lv_c iv_t = lv_t ).
      add_wu( iv_prog = lv_incl                          iv_u = lv_u iv_c = lv_c iv_t = lv_t ).
    ENDLOOP.
  ENDMETHOD.

  METHOD get_fm_interface.
    " User-exit/FM kaynaginda dinamik PERFORM yoksa: FM'in parametre
    " arayuzu FUPARAREF'ten okunur (Z form bunlari ayni isimle kopyalar).
    DATA(lv_func_s) = to_upper( condense( iv_form ) ).
    READ TABLE mt_ficache INTO DATA(ls_c) WITH KEY func = lv_func_s.
    IF sy-subrc = 0.
      rt_param = ls_c-params.
      RETURN.
    ENDIF.

    DATA lv_func TYPE rs38l_fnam.
    lv_func = lv_func_s.
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
          CONTINUE.                               " exception vs.
        ENDIF.
        APPEND VALUE #( kind = lv_k
                        name = to_upper( CONV string( ls_fp-parameter ) )
                        type = to_upper( CONV string( ls_fp-structure ) ) ) TO rt_param.
      ENDLOOP.
    ENDIF.

    INSERT VALUE #( func = lv_func_s params = rt_param ) INTO TABLE mt_ficache.
  ENDMETHOD.

  METHOD is_class.
    SELECT SINGLE clsname FROM seoclass INTO @DATA(lv_dummy)
      WHERE clsname = @iv_prog.
    rv_yes = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD get_method_source.
    " Metot include'unu CL_OO_CLASSNAME_SERVICE ile bul, (enhanced) oku.
    DATA(lv_method_u) = to_upper( condense( iv_method ) ).

    DATA lt_inc TYPE seop_methods_w_include.
    CALL METHOD cl_oo_classname_service=>get_all_method_includes
      EXPORTING
        clsname            = CONV seoclsname( iv_class )
      RECEIVING
        result             = lt_inc
      EXCEPTIONS
        class_not_existing = 1
        OTHERS             = 2.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    READ TABLE lt_inc INTO DATA(ls_inc)
         WITH KEY cpdkey-cpdname = lv_method_u.
    IF sy-subrc = 0.
      rt = read_src( CONV programm( ls_inc-incname ) ).
    ENDIF.
  ENDMETHOD.

  METHOD get_method_interface.
    " SE24 metot parametre arayuzu (RTTI). Tip bos birakilir -> compare_fm
    " sadece ISIM bazli (parametre var/yok) kontrol eder.
    TRY.
        DATA(lo_obj) = CAST cl_abap_objectdescr(
          cl_abap_typedescr=>describe_by_name( CONV string( iv_class ) ) ).

        READ TABLE lo_obj->methods INTO DATA(ls_m)
             WITH KEY name = to_upper( condense( iv_method ) ).
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.

        LOOP AT ls_m-parameters INTO DATA(ls_p).
          DATA(lv_kind) = SWITCH string( ls_p-parm_kind
            WHEN cl_abap_objectdescr=>importing THEN 'IMPORTING'
            WHEN cl_abap_objectdescr=>exporting THEN 'EXPORTING'
            WHEN cl_abap_objectdescr=>changing  THEN 'CHANGING'
            WHEN cl_abap_objectdescr=>returning THEN 'RETURNING'
            ELSE space ).
          IF lv_kind IS INITIAL.
            CONTINUE.
          ENDIF.
          APPEND VALUE #( kind = lv_kind
                          name = to_upper( CONV string( ls_p-name ) ) ) TO rt_param.
        ENDLOOP.
      CATCH cx_root.
        CLEAR rt_param.
    ENDTRY.
  ENDMETHOD.

  METHOD compare_fm.
    " Z form parametrelerini (it_z) kaynak FM arayuzu (it_fm) ile ISIM bazli
    " karsilastir. Kind (USING/IMPORTING...) yok sayilir; enhancement FM
    " importing/exporting parametrelerini USING ile geciyor.
    DATA lt_issue   TYPE string_table.
    DATA lv_missing TYPE abap_bool.

    LOOP AT it_z INTO DATA(ls_z).
      READ TABLE it_fm INTO DATA(ls_s) WITH KEY name = ls_z-name.
      IF sy-subrc <> 0.
        APPEND |'{ ls_z-name }' kaynak FM arayuzunde yok| TO lt_issue.
        lv_missing = abap_true.
      ELSEIF ls_z-type IS NOT INITIAL AND ls_s-type IS NOT INITIAL
         AND ls_z-type <> ls_s-type.
        APPEND |'{ ls_z-name }' tip farkli: FM[{ ls_s-type }] <> Z[{ ls_z-type }]| TO lt_issue.
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
      MESSAGE 'Uyusmayan kayit bulunamadi (hepsi eslesiyor).' TYPE 'I'.
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
        lo_cols->get_column( 'MODE'     )->set_short_text( 'Mode' ).
        lo_cols->get_column( 'DPROG'    )->set_short_text( 'Z Prog' ).
        lo_cols->get_column( 'DFORM'    )->set_short_text( 'Z Form' ).
        lo_cols->get_column( 'STATUS'   )->set_short_text( 'Status' ).
        lo_cols->get_column( 'DETAIL'   )->set_short_text( 'Detail' ).
        lo_cols->get_column( 'PERF_U'   )->set_short_text( 'Perf U' ).
        lo_cols->get_column( 'PERF_C'   )->set_short_text( 'Perf C' ).
        lo_cols->get_column( 'PERF_T'   )->set_short_text( 'Perf T' ).
        lo_cols->get_column( 'Z_U'      )->set_short_text( 'Z U' ).
        lo_cols->get_column( 'Z_C'      )->set_short_text( 'Z C' ).
        lo_cols->get_column( 'Z_T'      )->set_short_text( 'Z T' ).
        lo_cols->get_column( 'PERF_RAW' )->set_short_text( 'PERFORM' ).
        lo_cols->get_column( 'PERF_RAW' )->set_long_text( 'PERFORM statement' ).
        lo_cols->get_column( 'Z_SIG'    )->set_short_text( 'Z Sig' ).
        lo_cols->get_column( 'Z_SIG'    )->set_long_text( 'Z-form signature' ).

        " hotspot + cift tiklama ile kaynaga git
        CAST cl_salv_column_table( lo_cols->get_column( 'SFORM' )
             )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_cols->get_column( 'DFORM' )
             )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        CAST cl_salv_column_table( lo_cols->get_column( 'DPROG' )
             )->set_cell_type( if_salv_c_cell_type=>hotspot ).
        DATA(lo_events) = lo_alv->get_event( ).
        SET HANDLER me->on_link_click   FOR lo_events.
        SET HANDLER me->on_double_click FOR lo_events.

        lo_alv->get_display_settings( )->set_list_header(
          |ZSPLIT dinamik PERFORM parametre kontrolu - { lines( mt_result ) } bulgu| ).

        lo_alv->display( ).

      CATCH cx_salv_msg INTO DATA(lx_msg).
        MESSAGE lx_msg->get_text( ) TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD on_link_click.
    nav_for_cell( iv_row = CONV i( row ) iv_col = CONV string( column ) ).
  ENDMETHOD.

  METHOD on_double_click.
    nav_for_cell( iv_row = CONV i( row ) iv_col = CONV string( column ) ).
  ENDMETHOD.

  METHOD nav_for_cell.
    DATA(ls) = VALUE #( mt_result[ iv_row ] OPTIONAL ).
    IF ls IS INITIAL.
      RETURN.
    ENDIF.

    CASE iv_col.
      WHEN 'SFORM' OR 'SPROG' OR 'SRC_KIND' OR 'MODE'.
        " kaynak: FM ise SE37, METHOD ise SE24 sinifi, FORM ise kaynak program
        IF ls-src_kind = 'FM'.
          navigate( iv_type = 'FUNC' iv_name = ls-sform ).
        ELSEIF ls-src_kind = 'METHOD'.
          navigate( iv_type = 'CLAS' iv_name = CONV string( ls-sprog ) ).
        ELSE.
          navigate( iv_type = 'PROG' iv_name = CONV string( ls-sprog ) ).
        ENDIF.
      WHEN OTHERS.
        " Z split program (duzeltilecek form)
        navigate( iv_type = 'PROG' iv_name = CONV string( ls-dprog ) ).
    ENDCASE.
  ENDMETHOD.

  METHOD navigate.
    IF iv_name IS INITIAL.
      RETURN.
    ENDIF.
    CALL FUNCTION 'RS_TOOL_ACCESS'
      EXPORTING
        operation   = 'SHOW'
        object_name = CONV trobj_name( iv_name )
        object_type = iv_type
      EXCEPTIONS
        OTHERS      = 1.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_app( )->run( ).
