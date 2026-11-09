; theme.inc: grimoire UI palette. Include after common.inc in every UI file.
; The texgen art (tiles NINE0.., sil, compass) uses the same RGB values.

%define WHITE           0xFFFFFFFF

%define C_INK           RGBA(58, 38, 24, 255)       ; text on parchment, no shadow
%define C_INK_SOFT      RGBA(110, 84, 58, 255)      ; secondary / disabled text on parchment
%define C_RUBRIC        RGBA(150, 32, 28, 255)      ; headings and highlights on parchment
%define C_GOLD          RGBA(214, 170, 70, 255)     ; gold rules, lit web edges, reachable ring
%define C_GOLD_TEXT     RGBA(255, 214, 110, 255)    ; gold text on dark surfaces
%define C_CREAM         RGBA(244, 232, 200, 255)    ; light text on dark surfaces
%define C_UMBER         RGBA(46, 30, 20, 235)       ; flat dark surface
%define C_DIM           RGBA(20, 12, 6, 140)        ; dimmer behind books and pages
%define C_HOVER         RGBA(255, 236, 170, 70)     ; hover wash on cells and rows
%define C_LOCKED        RGBA(110, 84, 58, 200)      ; locked web edges
%define C_MANA          RGBA(70, 110, 230, 255)
%define C_STAMINA       RGBA(226, 184, 60, 255)
%define C_STAMINA_LOW   RGBA(200, 60, 40, 255)      ; stamina below 25
%define C_XP            RGBA(120, 200, 70, 255)
%define C_BLOOD         RGBA(200, 40, 40, 255)      ; boss bar fill
