; evsites.asm - the world geometry of events (0.12): where a temporary camp or a caravan may start,
; the tent that camp gets, the route a free caravan walks, the road a camp's caravan takes, which
; site a folk belongs to, and the cell a stuck caravan hops to. events.asm decides and spawns; this
; module only reads the world (and, for the tent, edits it with world_set so a session replicates it).
; Coordinates: BODY*, cell arguments and the hop/ground cells are LOCAL (absolute - world_origin); the
; tent record, the route and road ends and the site centres are ABSOLUTE.
; The tent record keeps up to 64 placed blocks (x, y, z, id) so evs_remove_tent can take back exactly
; the cells that still hold what was placed. Main thread only (world_set, camp_main).
%include "common.inc"
default rel

global evs_ground, evs_find_camp_site, evs_build_tent, evs_remove_tent, evs_forget_tent
global evs_tent_placed, evs_find_route, evs_road_from, evs_site_of, evs_hop_cell

extern world_get, world_set, world_top_y, world_column_ready, world_origin_x, world_origin_z
extern block_flags, rng_next, sincos_deg, floor_i, gen_height
extern camp_main, roads_in_rect, sites, site_count

%define TENT_MAX        64
%define ROUTE_MIN_H     98                  ; every route sample stands at least 2 above the sea
%define ROUTE_STEP_H    3                   ; and differs from the one before by at most 3
%define ROAD_MIN2       (64 * 64)           ; a road a caravan takes: 64 .. 900 blocks long
%define ROAD_MAX2       (900 * 900)
%define SITE_CLEAR2     (64 * 64)           ; a temporary camp keeps 64 blocks from every village and camp

section .rodata
; the tent's roof by faction: Villagers, Bandits, Cult, Beastfolk, Stonekin
ev_tent_roof:   db WOOL, PLANKS, COAL_BLOCK, WOOL, SMOOTH_STONE
; the posts of the leader's canopy, of the supply canopy and of the two torch posts: (dx, dz) from the centre
tent_posts_lead:  db -4, -4,  0, -4,  -4, 0,  0, 0
tent_posts_sup:   db  2,  2,  4,  2,   2, 4,  4, 4
tent_posts_torch: db  3, -3, -3,  3

section .bss
alignb 4
tent_n:         resd 1                      ; blocks recorded
tent_rec:       resd TENT_MAX * 4           ; x, y, z (absolute), id

section .text

; ---- cells -----------------------------------------------------------------------------------------

; evs_ground(edi x, esi z) -> eax the ground y of the local cell column, or -1. The column must be
; ready and its top at most 250. A TALL_GRASS or SNOW_LAYER top counts as the block below it; the ground
; block must be solid and opaque, not BEDROCK or any leaves, and the cell above it not WATER or LAVA.
evs_ground:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    call    world_column_ready
    test    eax, eax
    jz      .no
    mov     edi, r12d
    mov     esi, r13d
    call    world_top_y
    test    eax, eax
    js      .no
    cmp     eax, 250
    jg      .no
    mov     ebx, eax
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    call    world_get
    cmp     eax, TALL_GRASS
    je      .below
    cmp     eax, SNOW_LAYER
    jne     .check
.below:
    dec     ebx
    js      .no
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    call    world_get
.check:
    cmp     eax, BEDROCK
    je      .no
    cmp     eax, LEAVES
    je      .no
    cmp     eax, PINE_LEAVES
    je      .no
    cmp     eax, BIRCH_LEAVES
    je      .no
    movzx   ecx, byte [block_flags + rax]
    and     ecx, FLAG_SOLID | FLAG_OPAQUE
    cmp     ecx, FLAG_SOLID | FLAG_OPAQUE
    jne     .no
    mov     edi, r12d
    lea     esi, [rbx + 1]
    mov     edx, r13d
    call    world_get
    cmp     eax, WATER
    je      .no
    cmp     eax, LAVA
    je      .no
    mov     eax, ebx
    jmp     .out
.no:
    mov     eax, -1
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_hop_cell(xmm0 x, xmm1 z, xmm2 dirx, xmm3 dirz, rdi out dd[2]) -> eax ground y, or -1: the first
; cell with ground (evs_ground) 4 .. 48 blocks from (x, z) along the direction, stepping 1 block at a
; time; out = its local cell x, z. -1 leaves out alone.
; Frame: [rsp] x, [rsp+4] z, [rsp+8] dirx, [rsp+12] dirz, [rsp+16] the cell z.
evs_hop_cell:
    push    rbx
    push    r12
    push    r13
    sub     rsp, 32
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    movss   [rsp + 12], xmm3
    mov     r12, rdi
    mov     ebx, 4
.step:
    cvtsi2ss xmm2, ebx
    movss   xmm0, [rsp + 8]
    mulss   xmm0, xmm2
    addss   xmm0, [rsp]
    call    floor_i
    mov     r13d, eax
    cvtsi2ss xmm2, ebx
    movss   xmm0, [rsp + 12]
    mulss   xmm0, xmm2
    addss   xmm0, [rsp + 4]
    call    floor_i
    mov     [rsp + 16], eax
    mov     edi, r13d
    mov     esi, eax
    call    evs_ground
    test    eax, eax
    jns     .found
    inc     ebx
    cmp     ebx, 48
    jle     .step
    mov     eax, -1
    jmp     .out
.found:
    mov     [r12], r13d
    mov     ecx, [rsp + 16]
    mov     [r12 + 4], ecx
.out:
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- the camp site ---------------------------------------------------------------------------------

; evs_flat(edi cx, esi cz) -> eax the highest ground y of the 9 x 9 cells x, z in [-4, 4] round (cx, cz),
; or -1 when one of them has no ground (evs_ground) or the grounds span more than 1
; Frame: [rsp] the column's dx.
evs_flat:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, 0x7fffffff            ; lowest ground
    mov     r15d, -1                    ; highest
    mov     ebx, -4
.z:
    mov     dword [rsp], -4
.x:
    mov     edi, [rsp]
    add     edi, r12d
    lea     esi, [rbx + r13]
    call    evs_ground
    test    eax, eax
    js      .bad
    cmp     eax, r14d
    cmovl   r14d, eax
    cmp     eax, r15d
    cmovg   r15d, eax
    inc     dword [rsp]
    cmp     dword [rsp], 4
    jle     .x
    inc     ebx
    cmp     ebx, 4
    jle     .z
    mov     eax, r15d
    sub     eax, r14d
    cmp     eax, 1
    jg      .bad
    mov     eax, r15d
    jmp     .out
.bad:
    mov     eax, -1
.out:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_clear_of_sites(edi cx, esi cz) -> eax 1 when no cached village or camp (sites[], local) lies
; within 64 blocks of the cell (leaf)
evs_clear_of_sites:
    lea     rcx, [sites]
    mov     edx, [site_count]
.site:
    test    edx, edx
    jz      .yes
    mov     eax, [rcx + SITE.kind]
    cmp     eax, SITE_VILLAGE
    je      .near
    cmp     eax, SITE_CAMP
    jne     .next
.near:
    mov     eax, [rcx + SITE.x]
    sub     eax, edi
    imul    eax, eax
    mov     r8d, [rcx + SITE.z]
    sub     r8d, esi
    imul    r8d, r8d
    add     eax, r8d
    cmp     eax, SITE_CLEAR2
    jl      .no
.next:
    add     rcx, SITE_size
    dec     edx
    jmp     .site
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; evs_find_camp_site(rdi BODY*, rsi out dd[3]) -> eax 1 and out = local cx, H, cz, or 0. Up to 24 tries,
; each a random bearing and a distance of 32 .. 56 blocks from the body; a try holds when no cached village
; or camp is within 64 blocks and the 9 x 9 cells round it have ground whose span is at most 1 (evs_flat);
; H is the highest of that ground.
; Frame: [rsp] sin, [rsp+4] cos, [rsp+8] the distance.
evs_find_camp_site:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, 24
.try:
    call    rng_next
    xor     edx, edx
    mov     ecx, 360
    div     ecx
    cvtsi2ss xmm0, edx
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    rng_next
    xor     edx, edx
    mov     ecx, 25
    div     ecx
    add     edx, 32
    cvtsi2ss xmm2, edx
    movss   [rsp + 8], xmm2
    movss   xmm0, [rsp + 4]
    mulss   xmm0, xmm2
    addss   xmm0, [rbx + BODY.x]
    call    floor_i
    mov     r14d, eax
    movss   xmm0, [rsp]
    mulss   xmm0, [rsp + 8]
    addss   xmm0, [rbx + BODY.z]
    call    floor_i
    mov     r15d, eax
    mov     edi, r14d
    mov     esi, r15d
    call    evs_clear_of_sites
    test    eax, eax
    jz      .next
    mov     edi, r14d
    mov     esi, r15d
    call    evs_flat
    test    eax, eax
    js      .next
    mov     [r12], r14d
    mov     [r12 + 4], eax
    mov     [r12 + 8], r15d
    mov     eax, 1
    jmp     .out
.next:
    dec     r13d
    jnz     .try
    xor     eax, eax
.out:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- the tent --------------------------------------------------------------------------------------

; evs_put(edi x, esi y, edx z, ecx id) -> eax 1 when the id was placed (local cell) and recorded: only a
; cell holding AIR, TALL_GRASS or SNOW_LAYER takes it, the record has room, and the cell reads back as id
evs_put:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, ecx
    cmp     dword [tent_n], TENT_MAX
    jae     .no
    call    world_get                   ; (edi, esi, edx still the cell)
    test    eax, eax
    jz      .free
    cmp     eax, TALL_GRASS
    je      .free
    cmp     eax, SNOW_LAYER
    jne     .no
.free:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, r15d
    call    world_set
    mov     esi, r13d                   ; (world_set clobbers esi and edx)
    mov     edx, r14d
    call    world_get                   ; unlit column or y out of range: nothing was placed
    cmp     eax, r15d
    jne     .no
    mov     eax, [tent_n]
    shl     eax, 4
    lea     rcx, [tent_rec]
    add     rcx, rax
    mov     eax, r12d
    add     eax, [world_origin_x]
    mov     [rcx], eax
    mov     [rcx + 4], r13d
    mov     eax, r14d
    add     eax, [world_origin_z]
    mov     [rcx + 8], eax
    mov     [rcx + 12], r15d
    inc     dword [tent_n]
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_post(edi x, esi z, edx top, ecx id): the column of id from its ground + 1 up to y = top (evs_put)
evs_post:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     r15d, ecx
    call    evs_ground
    test    eax, eax
    js      .out
    lea     ebx, [rax + 1]
.y:
    cmp     ebx, r14d
    jg      .out
    mov     edi, r12d
    mov     esi, ebx
    mov     edx, r13d
    mov     ecx, r15d
    call    evs_put
    inc     ebx
    jmp     .y
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_roof(edi x0, esi z0, edx x1, ecx z1, r8d y, r9d id): id over x0 .. x1, z0 .. z1 at height y (evs_put)
; Frame: [rsp] the id.
evs_roof:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8
    mov     r13d, edi
    mov     r12d, esi                   ; the row
    mov     r14d, edx
    mov     r15d, ecx
    mov     ebp, r8d
    mov     [rsp], r9d
.z:
    mov     ebx, r13d
.x:
    mov     edi, ebx
    mov     esi, ebp
    mov     edx, r12d
    mov     ecx, [rsp]
    call    evs_put
    inc     ebx
    cmp     ebx, r14d
    jle     .x
    inc     r12d
    cmp     r12d, r15d
    jle     .z
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; POSTS table, count, top: a FENCE post at every (dx, dz) of the table, up to y = H + top.
; (r12d = cx, r13d = H, r14d = cz; clobbers rbx, r15)
%macro POSTS 3
    lea     r15, [%1]
    mov     ebx, %2
%%post:
    movsx   edi, byte [r15]
    add     edi, r12d
    movsx   esi, byte [r15 + 1]
    add     esi, r14d
    lea     edx, [r13 + %3]
    mov     ecx, FENCE
    call    evs_post
    add     r15, 2
    dec     ebx
    jnz     %%post
%endmacro

; evs_build_tent(edi cx, esi H, edx cz, ecx faction) -> eax the blocks placed. The tent of a temporary
; camp, over the footprint x, z in [cx-4, cx+4] with its ground at most H (evs_find_camp_site): the
; leader's canopy (posts at the corners of x, z in [-4, 0], roof at H + 3), the supply canopy (posts and
; roof over x, z in [2, 4], roof at H + 2) and two torch posts. Only cells holding AIR, TALL_GRASS or
; SNOW_LAYER change; every placed block is recorded (the old record is forgotten first). The roof's
; material is ev_tent_roof[faction].
; Frame: [rsp] the roof id.
evs_build_tent:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    cmp     ecx, 4
    jbe     .known
    xor     ecx, ecx
.known:
    lea     rax, [ev_tent_roof]
    movzx   eax, byte [rax + rcx]
    mov     [rsp], eax
    call    evs_forget_tent
    POSTS   tent_posts_lead, 4, 2
    lea     edi, [r12 - 4]
    lea     esi, [r14 - 4]
    mov     edx, r12d
    mov     ecx, r14d
    lea     r8d, [r13 + 3]
    mov     r9d, [rsp]
    call    evs_roof
    POSTS   tent_posts_sup, 4, 1
    lea     edi, [r12 + 2]
    lea     esi, [r14 + 2]
    lea     edx, [r12 + 4]
    lea     ecx, [r14 + 4]
    lea     r8d, [r13 + 2]
    mov     r9d, [rsp]
    call    evs_roof
    POSTS   tent_posts_torch, 2, 1
    lea     r15, [tent_posts_torch]     ; a torch on top of each post that stands
    mov     ebx, 2
.torch:
    movsx   edi, byte [r15]
    add     edi, r12d
    movsx   esi, byte [r15 + 1]
    add     esi, r14d
    mov     [rsp + 4], edi
    mov     [rsp + 8], esi
    lea     esi, [r13 + 1]
    mov     edx, [rsp + 8]
    call    world_get
    cmp     eax, FENCE
    jne     .torch_next
    mov     edi, [rsp + 4]
    lea     esi, [r13 + 2]
    mov     edx, [rsp + 8]
    mov     ecx, TORCH
    call    evs_put
.torch_next:
    add     r15, 2
    dec     ebx
    jnz     .torch
    mov     eax, [tent_n]
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_remove_tent() -> eax the blocks removed: every recorded cell that still holds the recorded id
; becomes AIR (a cell changed since stays as it is); then the record is forgotten
evs_remove_tent:
    push    rbx
    push    r12
    push    r13
    xor     r12d, r12d
    xor     ebx, ebx
.rec:
    cmp     ebx, [tent_n]
    jae     .done
    mov     eax, ebx
    shl     eax, 4
    lea     r13, [tent_rec]
    add     r13, rax
    mov     edi, [r13]
    sub     edi, [world_origin_x]
    mov     esi, [r13 + 4]
    mov     edx, [r13 + 8]
    sub     edx, [world_origin_z]
    call    world_get
    cmp     eax, [r13 + 12]
    jne     .next
    xor     ecx, ecx                    ; (edi, esi, edx survive world_get)
    call    world_set
    inc     r12d
.next:
    inc     ebx
    jmp     .rec
.done:
    mov     dword [tent_n], 0
    mov     eax, r12d
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_forget_tent(): drop the record, leave the blocks (leaf)
evs_forget_tent:
    mov     dword [tent_n], 0
    ret

; evs_tent_placed() -> eax the recorded blocks (leaf)
evs_tent_placed:
    mov     eax, [tent_n]
    ret

; ---- routes and roads ------------------------------------------------------------------------------

; evs_find_route(edi ax, esi az, rdx out dd[2]) -> eax 1 and out = the absolute destination, 162 .. 238 blocks
; from the absolute start, or 0. From a random bearing b0 the 8 bearings b0 + i * 45 degrees are tried, each
; with its own distance D = 162 + rng % 77: the cell (round(cos * D), round(sin * D)) away. The route is
; sampled with gen_height (pure terrain height) at N = (floor(L) + 7) / 8 points, L the true length: point k
; stands k / N of the way along (integer interpolation, truncated). Every sample must be at least 98 and
; differ from the one before it (the first from the start's own height) by at most 3.
; Frame: [rsp+8] sin, [rsp+12] cos, [rsp+16] dx, [rsp+20] dz, [rsp+24] N, [rsp+28] the previous height.
evs_find_route:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 40
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rdx
    call    rng_next
    xor     edx, edx
    mov     ecx, 8
    div     ecx
    mov     ebp, edx                    ; the first bearing
    xor     r15d, r15d
.bearing:
    lea     eax, [rbp + r15]
    and     eax, 7
    imul    eax, eax, 45
    cvtsi2ss xmm0, eax
    call    sincos_deg
    movss   [rsp + 8], xmm0
    movss   [rsp + 12], xmm1
    call    rng_next
    xor     edx, edx
    mov     ecx, 77
    div     ecx
    add     edx, 162
    cvtsi2ss xmm2, edx
    movss   xmm0, [rsp + 12]
    mulss   xmm0, xmm2
    cvtss2si eax, xmm0
    mov     [rsp + 16], eax
    movss   xmm0, [rsp + 8]
    mulss   xmm0, xmm2
    cvtss2si eax, xmm0
    mov     [rsp + 20], eax
    mov     eax, [rsp + 16]
    imul    eax, eax
    mov     ecx, [rsp + 20]
    imul    ecx, ecx
    add     eax, ecx
    cvtsi2ss xmm0, eax
    sqrtss  xmm0, xmm0
    cvttss2si eax, xmm0                 ; floor(L)
    add     eax, 7
    shr     eax, 3
    mov     [rsp + 24], eax
    mov     edi, r12d
    mov     esi, r13d
    call    gen_height
    mov     [rsp + 28], eax
    mov     ebx, 1
.sample:
    cmp     ebx, [rsp + 24]
    jg      .found
    mov     eax, [rsp + 16]
    imul    eax, ebx
    cdq
    idiv    dword [rsp + 24]
    add     eax, r12d
    mov     edi, eax
    mov     eax, [rsp + 20]
    imul    eax, ebx
    cdq
    idiv    dword [rsp + 24]
    add     eax, r13d
    mov     esi, eax
    call    gen_height
    cmp     eax, ROUTE_MIN_H
    jl      .next
    mov     ecx, eax
    sub     ecx, [rsp + 28]
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx                    ; |step|
    cmp     ecx, ROUTE_STEP_H
    jg      .next
    mov     [rsp + 28], eax
    inc     ebx
    jmp     .sample
.found:
    mov     eax, r12d
    add     eax, [rsp + 16]
    mov     [r14], eax
    mov     eax, r13d
    add     eax, [rsp + 20]
    mov     [r14 + 4], eax
    mov     eax, 1
    jmp     .out
.next:
    inc     r15d
    cmp     r15d, 8
    jb      .bearing
    xor     eax, eax
.out:
    add     rsp, 40
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; evs_road_from(edi cax, esi caz, rdx out dd[2]) -> eax 1 and out = the absolute other end of a road at
; the absolute camp centre (cax, caz), or 0. The roads of the super-regions the rectangle round the centre
; touches (roads_in_rect on camp_main) are taken in that order: the first one with the centre as its A
; or B end and a length of 64 .. 900 blocks gives the end at its other side.
; Frame: [rsp .. +288) the roads.
evs_road_from:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 288
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    lea     rdi, [camp_main]
    lea     esi, [rbx - 8]
    lea     edx, [r12 - 8]
    lea     ecx, [rbx + 8]
    lea     r8d, [r12 + 8]
    mov     r9, rsp
    call    roads_in_rect
    mov     r14d, eax
    mov     r15, rsp
.road:
    test    r14d, r14d
    jz      .none
    cmp     [r15 + ROADEDGE.ax], ebx
    jne     .at_b
    cmp     [r15 + ROADEDGE.az], r12d
    jne     .at_b
    mov     eax, [r15 + ROADEDGE.bx]
    mov     edx, [r15 + ROADEDGE.bz]
    jmp     .length
.at_b:
    cmp     [r15 + ROADEDGE.bx], ebx
    jne     .next
    cmp     [r15 + ROADEDGE.bz], r12d
    jne     .next
    mov     eax, [r15 + ROADEDGE.ax]
    mov     edx, [r15 + ROADEDGE.az]
.length:
    mov     ecx, eax
    sub     ecx, ebx
    imul    ecx, ecx
    mov     esi, edx
    sub     esi, r12d
    imul    esi, esi
    add     ecx, esi                    ; the squared length
    cmp     ecx, ROAD_MIN2
    jb      .next
    cmp     ecx, ROAD_MAX2
    ja      .next
    mov     [r13], eax
    mov     [r13 + 4], edx
    mov     eax, 1
    jmp     .out
.next:
    add     r15, ROADEDGE_size
    dec     r14d
    jmp     .road
.none:
    xor     eax, eax
.out:
    add     rsp, 288
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---- sites -----------------------------------------------------------------------------------------

; evs_site_of(rdi mob, rsi out dd[2]) -> eax EVK_SITE, EVK_ROAD or 0: the absolute centre of the site a
; folk belongs to, from its home (the site's cell + the folk slot of structures.asm; floor(home) + origin).
; Only a MOB_FOLK with patrol 0 counts, by role and faction:
;   LEADER of the Villagers (village slot -6, 0) -> EVK_SITE, centre home + (6, 0)
;   LEADER of a camp's faction (camp slot -5, -6) -> EVK_SITE, centre home + (5, 6)
;   TRADER of a camp's faction (camp slot 5, -6)  -> EVK_ROAD, centre home + (-5, 6)
; Anything else gives 0 and leaves out alone.
evs_site_of:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    cmp     dword [rdi + MOB.type], MOB_FOLK
    jne     .no
    cmp     dword [rdi + MOB.patrol], 0
    jne     .no
    movzx   eax, byte [rdi + MOB.faction]
    movzx   ecx, byte [rdi + MOB.role]
    mov     rbx, rdi
    mov     r12, rsi
    cmp     ecx, ROLE_LEADER
    je      .leader
    cmp     ecx, ROLE_TRADER
    jne     .no
    lea     edx, [rax - 1]
    cmp     edx, 3
    ja      .no                         ; a village's trader is not a caravan's
    mov     r13d, -5
    mov     r14d, 6
    mov     r15d, EVK_ROAD
    jmp     .centre
.leader:
    mov     r15d, EVK_SITE
    test    eax, eax
    jnz     .camp
    mov     r13d, 6
    xor     r14d, r14d
    jmp     .centre
.camp:
    lea     edx, [rax - 1]
    cmp     edx, 3
    ja      .no
    mov     r13d, 5
    mov     r14d, 6
.centre:
    movss   xmm0, [rbx + MOB.home_x]
    call    floor_i
    add     eax, [world_origin_x]
    add     eax, r13d
    mov     [r12], eax
    movss   xmm0, [rbx + MOB.home_z]
    call    floor_i
    add     eax, [world_origin_z]
    add     eax, r14d
    mov     [r12 + 4], eax
    mov     eax, r15d
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
