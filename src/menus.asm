; menus.asm - the non-gameplay screens built on the ui.asm toolkit: title, world list,
; create / rename / delete world, pause, death and the loading screen.
; Every screen_*() runs once per frame after ui_begin and acts on ui_input. Coordinates are
; GUI units (ui_w x ui_h). A screen that changes state returns at once, so one click never
; reaches two widgets. screen_create and screen_rename reset their fields when app_entered
; is set (and clear it); the other screens just clear it.
%include "common.inc"
default rel

global screen_title, screen_worlds, screen_create, screen_rename
global screen_delete, screen_pause, screen_death, screen_loading

extern ui_w, ui_h, ui_mx, ui_my, ui_focus
extern ui_rect, ui_frame, ui_panel
extern ui_text, ui_text_width, ui_text_centered, ui_button, ui_textfield
extern ui_input, surv, world_list, world_count
extern app_entered, app_settings_parent, app_selected
extern app_message, app_message_timer
extern app_goto, app_play_world, app_create_world, app_quit_to_title
extern app_respawn, app_request_quit
extern saves_scan, saves_delete, saves_rename, fmt_ago
extern str_append, str_copy, str_eq, parse_u32, fnv1a

%define WHITE   0xFFFFFFFF
%define GREY    RGBA(160, 160, 160, 255)
%define RED     RGBA(255, 85, 85, 255)

; ---- drawing macros (xbase / ybase are 64-bit registers holding a GUI coordinate) ------
%macro TXTC 7                           ; str, xbase, xoff, ybase, yoff, rgba, scale (centred)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, %7
    call    ui_text_centered
%endmacro
%macro TXTCA 6                          ; str, xbase, xoff, y, rgba, scale (centred, absolute y)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    mov     r8d, %6
    call    ui_text_centered
%endmacro
%macro TXTL 6                           ; str, xbase, xoff, y, rgba, scale (left aligned)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    mov     r8d, %6
    call    ui_text
%endmacro
%macro BTN 7                            ; label, xbase, xoff, ybase, yoff, w, enabled -> eax clicked
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    lea     edx, [%4 + %5]
    mov     ecx, %6
    mov     r8d, %7
    call    ui_button
%endmacro
%macro BTNA 6                           ; label, xbase, xoff, y, w, enabled (absolute y)
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    mov     r8d, %6
    call    ui_button
%endmacro
%macro FIELD 5                          ; textfield, xbase, xoff, y, w -> eax 1 on Enter
    lea     rdi, [%1]
    lea     esi, [%2 + %3]
    mov     edx, %4
    mov     ecx, %5
    call    ui_textfield
%endmacro
%macro ENTER_FRAME 1                    ; frame with %1 bytes of locals (%1 = 8 mod 16)
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, %1
%endmacro
%macro LEAVE_FRAME 1
    add     rsp, %1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro
%macro GOTO 1                           ; leave the screen for state %1
    mov     edi, %1
    call    goto
%endmacro

section .rodata
align 4
f_msg_time:     dd 5.0
f_zero:         dd 0.0

t_title:        db "ASSEMBLYCRAFT", 0
t_subtitle:     db "x86-64 assembly edition", 0
t_version:      db "AssemblyCraft 0.5", 0
t_singleplayer: db "Singleplayer", 0
t_settings:     db "Settings...", 0
t_quit:         db "Quit Game", 0

t_select:       db "Select World", 0
t_no_worlds:    db "No worlds yet", 0
t_unreadable:   db "(unreadable)", 0
t_play:         db "Play Selected World", 0
t_create_btn:   db "Create New World", 0
t_rename_btn:   db "Rename", 0
t_delete_btn:   db "Delete", 0
t_cancel:       db "Cancel", 0
s_survival:     db "Survival", 0
s_creative:     db "Creative", 0
s_creative_old: db "Creative (old format)", 0
s_seed:         db " - seed ", 0
s_dash:         db " - ", 0

t_create_title: db "Create New World", 0
t_world_name:   db "World Name", 0
t_seed_label:   db "Seed for the world generator", 0
t_seed_hint:    db "Leave blank for a random seed", 0
t_mode_surv:    db "Game Mode: Survival", 0
t_mode_creat:   db "Game Mode: Creative", 0
t_desc_surv:    db "Gather resources, craft tools, stay alive", 0
t_desc_creat:   db "Unlimited blocks, flying, no damage", 0
s_new_world:    db "New World", 0

t_rename_title: db "Rename World", 0

t_delete_ask:   db "Are you sure you want to delete this world?", 0
s_quote:        db "'", 0
s_lost:         db "' will be lost forever! (A long time!)", 0

t_game_menu:    db "Game Menu", 0
t_back:         db "Back to Game", 0
t_save_quit:    db "Save and Quit to Title", 0

t_died:         db "You died!", 0
t_respawn:      db "Respawn", 0
t_title_screen: db "Title Screen", 0
c_none:         db 0
c_fall:         db "You fell from a high place", 0
c_zombie:       db "You were slain by a Zombie", 0
c_starve:       db "You starved to death", 0
c_suffocate:    db "You suffocated in a wall", 0
c_skeleton:     db "You were shot by a Skeleton", 0
c_explosion:    db "You blew up", 0
c_spider:       db "You were slain by a Spider", 0
c_fire:         db "You burned to death", 0

m_rename_fail:  db "Could not rename the world", 0
m_delete_fail:  db "Could not delete the world", 0

align 8
death_causes:   dq c_none, c_fall, c_zombie, c_starve, c_suffocate
                dq c_skeleton, c_explosion, c_spider, c_fire

section .bss
alignb 8
tf_name:        resb TEXTFIELD_size     ; create-world name
tf_seed:        resb TEXTFIELD_size     ; create-world seed
tf_rename:      resb TEXTFIELD_size
name_buf:       resb 40                 ; trimmed copy of a name field
file_keep:      resb 64                 ; file name of the entry being renamed
line_buf:       resb 160
create_mode:    resd 1                  ; MODE_SURVIVAL / MODE_CREATIVE
list_scroll:    resd 1                  ; first visible row of the world list

section .text

; ---- helpers ---------------------------------------------------------------------------

; goto(edi state): drop text focus, then app_goto
goto:
    mov     qword [ui_focus], 0
    jmp     app_goto

; set_message(rdi zstr): red message on the world list for 5 seconds
set_message:
    push    rax                         ; align
    mov     rsi, rdi
    lea     rdi, [app_message]
    mov     edx, 127
    call    str_copy
    movss   xmm0, [f_msg_time]
    movss   [app_message_timer], xmm0
    pop     rax
    ret

; u32_to_str(edi value, rsi buf) -> rax past the last digit (no NUL)
u32_to_str:
    mov     eax, edi
    sub     rsp, 24
    xor     ecx, ecx
    mov     r8d, 10
.digits:
    xor     edx, edx
    div     r8
    add     dl, '0'
    mov     [rsp + rcx], dl
    inc     ecx
    test    rax, rax
    jnz     .digits
.copy:
    dec     ecx
    mov     dl, [rsp + rcx]
    mov     [rsi], dl
    inc     rsi
    test    ecx, ecx
    jnz     .copy
    add     rsp, 24
    mov     rax, rsi
    ret

; trim_copy(rdi dst, rsi TEXTFIELD*) -> eax length: the text without leading/trailing
; spaces, NUL terminated into dst (at most 33 bytes)
trim_copy:
    mov     ecx, [rsi + TEXTFIELD.len]
    cmp     ecx, 32
    jbe     .len_ok
    mov     ecx, 32
.len_ok:
    xor     edx, edx                    ; start
.lead:
    cmp     edx, ecx
    jae     .trail
    cmp     byte [rsi + rdx], ' '
    jne     .trail
    inc     edx
    jmp     .lead
.trail:
    cmp     ecx, edx
    jbe     .copy
    cmp     byte [rsi + rcx - 1], ' '
    jne     .copy
    dec     ecx
    jmp     .trail
.copy:
    mov     eax, ecx
    sub     eax, edx                    ; result length
    xor     r8d, r8d
.byte:
    cmp     edx, ecx
    jae     .done
    mov     r9b, [rsi + rdx]
    mov     [rdi + r8], r9b
    inc     edx
    inc     r8d
    jmp     .byte
.done:
    mov     byte [rdi + r8], 0
    ret

; entry_ptr(edi idx) -> rax &world_list[idx]
entry_ptr:
    mov     eax, edi
    shl     rax, 7                      ; WORLDENTRY_size = 128
    lea     rdx, [world_list]
    add     rax, rdx
    ret

; build_info(rdi entry): line_buf = "<mode> - seed <n> - <time ago>"
build_info:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    lea     rdi, [line_buf]
    mov     eax, [rbx + WORLDENTRY.mode]
    lea     rsi, [s_survival]
    test    eax, eax
    jz      .mode
    lea     rsi, [s_creative]
    cmp     eax, 1
    je      .mode
    lea     rsi, [s_creative_old]
.mode:
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_seed]
    call    str_append
    mov     edi, [rbx + WORLDENTRY.seed]
    mov     rsi, rax
    call    u32_to_str
    mov     rdi, rax
    lea     rsi, [s_dash]
    call    str_append
    mov     rdi, rax
    mov     rsi, [rbx + WORLDENTRY.mtime]
    call    fmt_ago
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; sel_valid() -> eax 1 if app_selected indexes an existing world
sel_valid:
    mov     eax, [app_selected]
    test    eax, eax
    js      .no
    cmp     eax, [world_count]
    jge     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; ---- title -------------------------------------------------------------------------------

screen_title:
    ENTER_FRAME 8
    mov     dword [app_entered], 0
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    mov     eax, r13d
    shr     eax, 2
    mov     r14d, eax                   ; ui_h / 4
    mov     eax, r13d
    shr     eax, 1
    mov     r15d, eax                   ; ui_h / 2
    lea     rdi, [t_title]              ; scale 4, or 3 when it would not fit
    mov     esi, 4
    call    ui_text_width
    mov     ebx, 4
    mov     ecx, [ui_w]
    sub     ecx, 20
    cmp     eax, ecx
    jle     .scale_ok
    mov     ebx, 3
.scale_ok:
    TXTC    t_title, r12, 0, r14, -16, WHITE, ebx
    TXTC    t_subtitle, r12, 0, r14, 20, GREY, 1
    lea     rdi, [t_version]
    mov     esi, 2
    lea     edx, [r13 - 10]
    mov     ecx, GREY
    mov     r8d, 1
    call    ui_text
    BTN     t_singleplayer, r12, -100, r15, 0, 200, 1
    test    eax, eax
    jz      .not_single
    call    saves_scan
    mov     dword [app_selected], -1
    GOTO    ST_WORLDS
    jmp     .ret
.not_single:
    BTN     t_settings, r12, -100, r15, 24, 200, 1
    test    eax, eax
    jz      .not_settings
    mov     dword [app_settings_parent], ST_TITLE
    GOTO    ST_SETTINGS
    jmp     .ret
.not_settings:
    BTN     t_quit, r12, -100, r15, 48, 200, 1
    test    eax, eax
    jz      .ret
    call    app_request_quit
.ret:
    LEAVE_FRAME 8

; ---- world list ----------------------------------------------------------------------------

screen_worlds:
    ENTER_FRAME 40                      ; [rsp] entry, [rsp+8] row y
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    cmp     dword [app_entered], 0
    je      .entered
    mov     dword [app_entered], 0
    mov     dword [list_scroll], 0
.entered:
    mov     eax, [app_selected]         ; a selection past the end is stale
    cmp     eax, [world_count]
    jl      .sel_ok
    mov     dword [app_selected], -1
.sel_ok:
    lea     eax, [r13 - 96]             ; list spans y 32 .. ui_h-64, rows 36 high
    cdq
    mov     ecx, 36
    idiv    ecx
    mov     r14d, 1
    cmp     eax, r14d
    cmovg   r14d, eax                   ; visible rows (>= 1)
    mov     eax, [world_count]
    sub     eax, r14d
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx                    ; max scroll
    mov     ecx, [list_scroll]
    sub     ecx, [ui_input + UIINPUT.scroll]
    cmp     ecx, eax
    cmovg   ecx, eax
    test    ecx, ecx
    cmovs   ecx, edx
    mov     [list_scroll], ecx
    TXTCA   t_select, r12, 0, 12, WHITE, 1
    movss   xmm0, [app_message_timer]
    ucomiss xmm0, [f_zero]
    jbe     .no_message
    TXTCA   app_message, r12, 0, 22, RED, 1
.no_message:
    lea     edi, [r12 - 150]
    mov     esi, 32
    mov     edx, 300
    lea     ecx, [r13 - 96]
    call    ui_panel
    cmp     dword [world_count], 0
    jne     .have_rows
    lea     eax, [r13 - 32]
    shr     eax, 1
    sub     eax, 4
    TXTCA   t_no_worlds, r12, 0, eax, GREY, 1
.have_rows:
    mov     ebx, [list_scroll]
    lea     eax, [rbx + r14]
    mov     ecx, [world_count]
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     r15d, eax                   ; one past the last visible row
.row:
    cmp     ebx, r15d
    jge     .rows_done
    mov     edi, ebx
    call    entry_ptr
    mov     [rsp], rax
    mov     eax, ebx
    sub     eax, [list_scroll]
    imul    eax, eax, 36
    add     eax, 32
    mov     [rsp + 8], eax              ; row y
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .no_click
    mov     ecx, [ui_mx]                ; inside x in [cx-150, cx+150), y in [ry, ry+36)?
    lea     edx, [r12 - 150]
    sub     ecx, edx
    cmp     ecx, 300
    jae     .no_click
    mov     ecx, [ui_my]
    sub     ecx, eax
    cmp     ecx, 36
    jae     .no_click
    mov     [app_selected], ebx
    cmp     dword [ui_input + UIINPUT.double_click], 0
    je      .no_click
    mov     rdx, [rsp]
    cmp     dword [rdx + WORLDENTRY.valid], 0
    je      .no_click
    mov     edi, ebx
    call    app_play_world
    jmp     .ret
.no_click:
    cmp     ebx, [app_selected]
    jne     .unselected
    lea     edi, [r12 - 150]
    mov     esi, [rsp + 8]
    mov     edx, 300
    mov     ecx, 36
    mov     r8d, RGBA(255, 255, 255, 38)
    call    ui_rect
    lea     edi, [r12 - 150]
    mov     esi, [rsp + 8]
    mov     edx, 300
    mov     ecx, 36
    mov     r8d, WHITE
    call    ui_frame
.unselected:
    mov     rdi, [rsp]
    add     rdi, WORLDENTRY.name
    lea     esi, [r12 - 146]
    mov     edx, [rsp + 8]
    add     edx, 4
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    mov     rdi, [rsp]
    cmp     dword [rdi + WORLDENTRY.valid], 0
    je      .invalid
    call    build_info
    lea     rdi, [line_buf]
    mov     ecx, GREY
    jmp     .info
.invalid:
    lea     rdi, [t_unreadable]
    mov     ecx, RED
.info:
    lea     esi, [r12 - 146]
    mov     edx, [rsp + 8]
    add     edx, 16
    mov     r8d, 1
    call    ui_text
    inc     ebx
    jmp     .row
.rows_done:
    xor     r14d, r14d                  ; play enabled: a valid selection
    xor     r15d, r15d                  ; rename enabled: a valid v2 world
    xor     ebx, ebx                    ; delete enabled: any selection
    call    sel_valid
    test    eax, eax
    jz      .buttons
    mov     ebx, 1
    mov     edi, [app_selected]
    call    entry_ptr
    cmp     dword [rax + WORLDENTRY.valid], 0
    je      .buttons
    mov     r14d, 1
    cmp     dword [rax + WORLDENTRY.mode], 1
    setbe   r15b
    movzx   r15d, r15b
.buttons:
    BTN     t_play, r12, -155, r13, -52, 150, r14d
    test    eax, eax
    jz      .not_play
    mov     edi, [app_selected]
    call    app_play_world
    jmp     .ret
.not_play:
    BTN     t_create_btn, r12, 5, r13, -52, 150, 1
    test    eax, eax
    jz      .not_create
    GOTO    ST_CREATE
    jmp     .ret
.not_create:
    BTN     t_rename_btn, r12, -155, r13, -28, 72, r15d
    test    eax, eax
    jz      .not_rename
    GOTO    ST_RENAME
    jmp     .ret
.not_rename:
    BTN     t_delete_btn, r12, -79, r13, -28, 72, ebx
    test    eax, eax
    jz      .not_delete
    GOTO    ST_DELETE
    jmp     .ret
.not_delete:
    BTN     t_cancel, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    GOTO    ST_TITLE
.ret:
    LEAVE_FRAME 40

; ---- create world --------------------------------------------------------------------------

screen_create:
    ENTER_FRAME 8                       ; [rsp] seed text length, [rsp+4] seed
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    cmp     dword [app_entered], 0
    je      .fields_ready
    mov     dword [app_entered], 0
    lea     rdi, [tf_name + TEXTFIELD.buf]
    lea     rsi, [s_new_world]
    mov     edx, 32
    call    str_copy
    lea     rcx, [tf_name + TEXTFIELD.buf]
    sub     rax, rcx
    mov     [tf_name + TEXTFIELD.len], eax
    mov     dword [tf_name + TEXTFIELD.max], 32
    mov     byte [tf_seed + TEXTFIELD.buf], 0
    mov     dword [tf_seed + TEXTFIELD.len], 0
    mov     dword [tf_seed + TEXTFIELD.max], 32
    mov     dword [create_mode], MODE_SURVIVAL
    lea     rax, [tf_name]
    mov     [ui_focus], rax
.fields_ready:
    TXTCA   t_create_title, r12, 0, 12, WHITE, 1
    TXTL    t_world_name, r12, -100, 44, GREY, 1
    FIELD   tf_name, r12, -100, 56, 200
    mov     r15d, eax                   ; Enter pressed in the name field
    TXTL    t_seed_label, r12, -100, 88, GREY, 1
    FIELD   tf_seed, r12, -100, 100, 200
    TXTL    t_seed_hint, r12, -100, 124, GREY, 1
    lea     rdi, [name_buf]             ; create needs a non-blank name
    lea     rsi, [tf_name]
    call    trim_copy
    xor     ebx, ebx
    test    eax, eax
    setnz   bl
    lea     rdi, [t_mode_surv]
    lea     rax, [t_mode_creat]
    cmp     dword [create_mode], MODE_SURVIVAL
    cmovne  rdi, rax
    lea     esi, [r12 - 100]
    mov     edx, 140
    mov     ecx, 200
    mov     r8d, 1
    call    ui_button
    test    eax, eax
    jz      .mode_kept
    xor     dword [create_mode], 1
.mode_kept:
    lea     rdi, [t_desc_surv]
    lea     rax, [t_desc_creat]
    cmp     dword [create_mode], MODE_SURVIVAL
    cmovne  rdi, rax
    mov     esi, r12d
    mov     edx, 166
    mov     ecx, GREY
    mov     r8d, 1
    call    ui_text_centered
    BTN     t_create_btn, r12, -155, r13, -28, 150, ebx
    test    eax, eax
    jnz     .do_create
    test    r15d, r15d
    jz      .not_enter
    test    ebx, ebx
    jnz     .do_create
.not_enter:
    BTN     t_cancel, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    GOTO    ST_WORLDS
    jmp     .ret
.do_create:
    mov     ecx, [tf_seed + TEXTFIELD.len]
    cmp     ecx, 32
    jbe     .seed_len_ok
    mov     ecx, 32
.seed_len_ok:
    mov     [rsp], ecx
    lea     rax, [tf_seed + TEXTFIELD.buf]
    mov     byte [rax + rcx], 0
    test    ecx, ecx
    jnz     .seed_text
    rdtsc                               ; blank: random seed
    mov     [rsp + 4], eax
    jmp     .seed_done
.seed_text:
    lea     rdi, [tf_seed + TEXTFIELD.buf]
    lea     rsi, [rsp + 4]
    call    parse_u32
    test    eax, eax
    jnz     .seed_done
    lea     rdi, [tf_seed + TEXTFIELD.buf]
    mov     esi, [rsp]
    call    fnv1a
    mov     [rsp + 4], eax
.seed_done:
    mov     qword [ui_focus], 0
    lea     rdi, [name_buf]
    mov     esi, [create_mode]
    mov     edx, [rsp + 4]
    call    app_create_world
.ret:
    LEAVE_FRAME 8

; ---- rename world --------------------------------------------------------------------------

screen_rename:
    ENTER_FRAME 8
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    call    sel_valid
    test    eax, eax
    jnz     .selected
    mov     dword [app_entered], 0
    GOTO    ST_WORLDS
    jmp     .ret
.selected:
    cmp     dword [app_entered], 0
    je      .field_ready
    mov     dword [app_entered], 0
    mov     edi, [app_selected]
    call    entry_ptr
    lea     rsi, [rax + WORLDENTRY.name]
    lea     rdi, [tf_rename + TEXTFIELD.buf]
    mov     edx, 32
    call    str_copy
    lea     rcx, [tf_rename + TEXTFIELD.buf]
    sub     rax, rcx
    mov     [tf_rename + TEXTFIELD.len], eax
    mov     dword [tf_rename + TEXTFIELD.max], 32
    lea     rax, [tf_rename]
    mov     [ui_focus], rax
.field_ready:
    TXTCA   t_rename_title, r12, 0, 12, WHITE, 1
    TXTL    t_world_name, r12, -100, 44, GREY, 1
    FIELD   tf_rename, r12, -100, 56, 200
    mov     r15d, eax                   ; Enter pressed in the field
    lea     rdi, [name_buf]
    lea     rsi, [tf_rename]
    call    trim_copy
    xor     ebx, ebx
    test    eax, eax
    setnz   bl
    BTN     t_rename_btn, r12, -155, r13, -28, 150, ebx
    test    eax, eax
    jnz     .do_rename
    test    r15d, r15d
    jz      .not_enter
    test    ebx, ebx
    jnz     .do_rename
.not_enter:
    BTN     t_cancel, r12, 5, r13, -28, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    GOTO    ST_WORLDS
    jmp     .ret
.do_rename:
    mov     edi, [app_selected]
    call    entry_ptr
    lea     rdi, [file_keep]            ; the rescan re-sorts the list: remember the file
    mov     rsi, rax
    mov     edx, 63
    call    str_copy
    mov     edi, [app_selected]
    lea     rsi, [name_buf]
    call    saves_rename
    mov     ebx, eax
    call    saves_scan
    mov     dword [app_selected], -1
    xor     r14d, r14d
.find:
    cmp     r14d, [world_count]
    jge     .found
    mov     edi, r14d
    call    entry_ptr
    mov     rdi, rax
    lea     rsi, [file_keep]
    call    str_eq
    test    eax, eax
    jnz     .match
    inc     r14d
    jmp     .find
.match:
    mov     [app_selected], r14d
.found:
    test    ebx, ebx
    jz      .renamed
    lea     rdi, [m_rename_fail]
    call    set_message
.renamed:
    GOTO    ST_WORLDS
.ret:
    LEAVE_FRAME 8

; ---- delete world --------------------------------------------------------------------------

screen_delete:
    ENTER_FRAME 8
    mov     dword [app_entered], 0
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     r13d, [ui_h]
    mov     eax, r13d
    shr     eax, 1
    mov     r14d, eax                   ; ui_h / 2
    call    sel_valid
    test    eax, eax
    jnz     .selected
    GOTO    ST_WORLDS
    jmp     .ret
.selected:
    TXTC    t_delete_ask, r12, 0, r14, -40, WHITE, 1
    mov     edi, [app_selected]
    call    entry_ptr
    mov     rbx, rax
    lea     rdi, [line_buf]
    lea     rsi, [s_quote]
    call    str_append
    mov     rdi, rax
    lea     rsi, [rbx + WORLDENTRY.name]
    call    str_append
    mov     rdi, rax
    lea     rsi, [s_lost]
    call    str_append
    mov     byte [rax], 0
    lea     rdi, [line_buf]
    mov     esi, r12d
    lea     edx, [r14 - 24]
    mov     ecx, GREY
    mov     r8d, 1
    call    ui_text_centered
    BTN     t_delete_btn, r12, -155, r14, 10, 150, 1
    test    eax, eax
    jnz     .do_delete
    BTN     t_cancel, r12, 5, r14, 10, 150, 1
    test    eax, eax
    jnz     .back
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.back:
    GOTO    ST_WORLDS
    jmp     .ret
.do_delete:
    mov     edi, [app_selected]
    call    saves_delete
    mov     ebx, eax
    call    saves_scan
    mov     dword [app_selected], -1
    test    ebx, ebx
    jz      .deleted
    lea     rdi, [m_delete_fail]
    call    set_message
.deleted:
    GOTO    ST_WORLDS
.ret:
    LEAVE_FRAME 8

; ---- pause ---------------------------------------------------------------------------------

screen_pause:
    ENTER_FRAME 8
    mov     dword [app_entered], 0
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     eax, [ui_h]
    shr     eax, 2
    mov     r14d, eax                   ; ui_h / 4
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(0, 0, 0, 128)
    call    ui_rect
    TXTC    t_game_menu, r12, 0, r14, 0, WHITE, 1
    BTN     t_back, r12, -100, r14, 24, 200, 1
    test    eax, eax
    jnz     .resume
    BTN     t_settings, r12, -100, r14, 48, 200, 1
    test    eax, eax
    jz      .not_settings
    mov     dword [app_settings_parent], ST_PAUSED
    GOTO    ST_SETTINGS
    jmp     .ret
.not_settings:
    BTN     t_save_quit, r12, -100, r14, 72, 200, 1
    test    eax, eax
    jz      .not_quit
    call    app_quit_to_title
    jmp     .ret
.not_quit:
    cmp     dword [ui_input + UIINPUT.escape], 0
    je      .ret
.resume:
    GOTO    ST_PLAYING
.ret:
    LEAVE_FRAME 8

; ---- death ---------------------------------------------------------------------------------

screen_death:
    ENTER_FRAME 8
    mov     dword [app_entered], 0
    mov     eax, [ui_w]
    shr     eax, 1
    mov     r12d, eax                   ; cx
    mov     eax, [ui_h]
    shr     eax, 2
    mov     r14d, eax                   ; ui_h / 4
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(150, 0, 0, 115)
    call    ui_rect
    TXTC    t_died, r12, 0, r14, 0, WHITE, 2
    mov     eax, [surv + SURVIVAL.death_cause]
    xor ecx, ecx
    cmp     eax, CAUSE_FIRE             ; unknown causes show no line
    cmova   eax, ecx
    lea     rdx, [death_causes]
    mov     rdi, [rdx + rax*8]
    mov     esi, r12d
    lea     edx, [r14 + 24]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text_centered
    BTN     t_respawn, r12, -100, r14, 48, 200, 1
    test    eax, eax
    jz      .not_respawn
    xor     edi, edi
    call    app_respawn
    jmp     .ret
.not_respawn:
    BTN     t_title_screen, r12, -100, r14, 72, 200, 1
    test    eax, eax
    jz      .ret
    mov     edi, 1
    call    app_respawn
.ret:
    LEAVE_FRAME 8

; ---- loading -------------------------------------------------------------------------------

; screen_loading(rdi text): opaque dark screen with the text in the middle
screen_loading:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, RGBA(16, 16, 16, 255)
    call    ui_rect
    mov     rdi, rbx
    mov     esi, [ui_w]
    shr     esi, 1
    mov     edx, [ui_h]
    shr     edx, 1
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text_centered
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
