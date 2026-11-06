/*
 * fractal.c - CG3207 Assignment 4 demo: a real-time Mandelbrot / Julia explorer on the Pmod OLED.
 *
 * Fly around the Mandelbrot set by tilting the board, zoom with the buttons, and press BTNC to
 * jump into the Julia set of the point under the crosshair, which then morphs as its c orbits
 * that point (tilt to steer it). Colours cycle every frame.
 *
 * Every pixel is up to max_iter iterations of  z = z^2 + c  in fixed point (Q7.25), i.e. three
 * multiplies per iteration - so the speed of the multiplier decides the frame rate. That is
 * what the Assignment 4 multiply unit is for:
 *   - a fully pipelined multiplier (one multiply per cycle, result ready like a load's) instead of
 *     the 33-cycle MCycle that froze the pipeline, and
 *   - mulsr rd, rs1, rs2, k = (rs1 * rs2) >> k, a fixed-point multiply in ONE instruction,
 *     instead of mul + mulh + srli + slli + or.
 *
 * Switches (read every frame, so they can be flipped while it runs)
 *   SW0   CPU: no forwarding (interlocks instead)          }
 *   SW1   CPU: no branch prediction                         }  CPU_CTRL - the hardware itself
 *   SW2   CPU: slow multiplier (Assignment 3 MCycle, 33 cycles, stalls the pipeline)  }
 *   SW3   software: plain RV32IM code (mul + mulh + shifts) instead of mulsr
 *   SW7-4 max iterations = 32 + 16 * SW[7:4]
 *   SW12  flip the up/down tilt direction, SW13 flip left/right
 *         (tilt is measured from how the board was held at start-up: press BTND to set "level" again)
 *   SW15  7-segment: 0 = cycles per frame, 1 = cycles per iteration (both in decimal)
 * Buttons
 *   BTNR / BTNL  zoom in / out (held)
 *   BTNC         Mandelbrot <-> Julia  (push-button INTERRUPT; handler ends in mret)
 *   BTND reset, BTNU pause (TOP)
 * Outputs
 *   OLED   the fractal, drawn into the back buffer and presented every frame (v2 double buffering)
 *   7-seg  cycles per frame / per iteration, measured with the cycle counter
 *   LEDs   LED3-0 = SW3-0 (what is switched off), LED6 toggles every frame, LED7 = Julia mode.
 *          At boot: LED0 = main reached, LED1 = first frame drawn, LED2 = first present done
 *          (if the board stops there, the LEDs say how far it got).
 *
 * Build: python3 ../build.py fractal.c        (in WSL / Linux, needs gcc-riscv64-unknown-elf)
 *
 * AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
 */

#include "fractal_tables.h"

#define MMIO_BASE       0xFFFF0000u
#define REG(off)        (*(volatile unsigned int *)(MMIO_BASE + (off)))
#define REG16(off)      (*(volatile unsigned short *)(MMIO_BASE + (off)))
#define OLED_COL        REG(0x20)
#define OLED_ROW        REG(0x24)
#define OLED_DATA16     REG16(0x28)     /* 16-bit colour mode: written with sh */
#define OLED_CTRL       REG(0x2C)
#define OLED_STATUS     REG(0x30)
#define ACCEL           REG(0x40)
#define LED             REG(0x60)
#define DIP             REG(0x64)
#define PB              REG(0x68)
#define SEVENSEG        REG(0x80)
#define CYCLECOUNT      REG(0xA0)
#define CPU_CTRL        REG(0x70)
#define INT_EN          REG(0x74)
#define INT_FLAGS       REG(0x78)

#define BTNR 1u
#define BTNC 2u
#define BTNL 4u

#ifndef BENCH
#define W 96                            /* the frame */
#define H 64
#define SUB 1
#else                                   /* simulation benchmark: every 4th pixel each way, same view */
#define W 24
#define H 16
#define SUB 4
#endif

/* ---------------------------------------------------------------- fixed point, Q7.25 */
/* 7 integer bits: before the escape test, |z| can reach ~6.5 and z^2 ~42, so Q4.28 would overflow. */
#define FRAC 25
#define FX(x) ((int)((x) * (double)(1 << FRAC)))        /* compile-time constants only */
#define ESCAPE (4u << FRAC)                              /* |z|^2 >= 4 */

/* mulsr rd, rs1, rs2, k  (custom-0 opcode): rd = (rs1 * rs2) >> k, signed */
#define MULSR(k, a, b) ({ int r_; __asm__(".insn r 0x0b, 0, %3, %0, %1, %2" : "=r"(r_) : "r"(a), "r"(b), "i"(k)); r_; })
/* the same thing in plain RV32IM: mul + mulh + srli + slli + or */
#define MULSHIFT(k, a, b) ((int)(((long long)(a) * (long long)(b)) >> (k)))

/* Escape-time iteration, written once with each kind of multiply. Returns iterations used. */
#define ESCAPE_FN(name, MUL)                                                        \
static inline __attribute__((always_inline))                                       \
int name(int zx, int zy, int cx, int cy, int max_iter)                             \
{                                                                                  \
    int n = max_iter;                                                              \
    do {                                                                           \
        int x2 = MUL(FRAC, zx, zx);                                                \
        int y2 = MUL(FRAC, zy, zy);                                                \
        int xy2 = MUL(FRAC - 1, zx, zy);           /* 2*zx*zy: one less shift */   \
        if ((unsigned)x2 + (unsigned)y2 >= ESCAPE)                                 \
            break;                                                                 \
        zx = x2 - y2 + cx;                                                         \
        zy = xy2 + cy;                                                             \
    } while (--n);                                                                 \
    return max_iter - n;                                                           \
}
ESCAPE_FN(escape_mulsr, MULSR)
ESCAPE_FN(escape_plain, MULSHIFT)

/* ---------------------------------------------------------------- state */
static volatile int julia;              /* toggled by the BTNC interrupt */
static int centre_x = FX(-0.6), centre_y = FX(0.0), step = FX(3.0 / 96);    /* Mandelbrot view */
static int julia_step = FX(3.2 / 96);
static int jc_x, jc_y;                  /* Julia: the point c orbits */
static unsigned int phase;              /* colour cycling and the Julia orbit */
static unsigned int total_iters;        /* iterations in the last frame */

void __attribute__((interrupt("machine"))) isr(void)
{
    unsigned int f = INT_FLAGS;
    if (f & BTNC) {
        if (!julia) {                   /* jump into the Julia set of the crosshair point */
            jc_x = centre_x;
            jc_y = centre_y;
        }
        julia = !julia;
    }
    INT_FLAGS = f;                      /* acknowledge */
}

/* ---------------------------------------------------------------- one frame */
#define RENDER_FN(name, ESC)                                                       \
static void name(int max_iter)                                                     \
{                                                                                  \
    int jul = julia;                                                               \
    int s = jul ? julia_step : step;                                               \
    int x0 = (jul ? 0 : centre_x) - (W / 2) * s * SUB;                             \
    int y = (jul ? 0 : centre_y) - (H / 2) * s * SUB;                              \
    s *= SUB;                                                                      \
    int cx = jc_x + orbit_x[phase & 63], cy = jc_y + orbit_y[phase & 63];          \
    unsigned int iters = 0;                                                        \
    for (int py = 0; py < H; py++, y += s) {                                       \
        int x = x0;                                                                \
        for (int px = 0; px < W; px++, x += s) {                                   \
            int n = jul ? ESC(x, y, cx, cy, max_iter) : ESC(0, 0, x, y, max_iter); \
            iters += n;                                                            \
            unsigned short c = (n == max_iter) ? 0 : palette[((n << 2) + (phase << 1)) & 63]; \
            if (!jul && ((px == W / 2 && (unsigned)(py - H / 2 + 3) < 7) ||        \
                         (py == H / 2 && (unsigned)(px - W / 2 + 3) < 7)))         \
                c = 0xFFFF;                                     /* crosshair */    \
            OLED_DATA16 = c;                                                       \
        }                                                                          \
    }                                                                              \
    total_iters = iters;                                                           \
}
RENDER_FN(render_mulsr, escape_mulsr)
RENDER_FN(render_plain, escape_plain)

/* ---------------------------------------------------------------- controls */
static unsigned int accel_level;        /* the reading at start-up = "level" (sensor offset, uneven table) */

static int tilt(unsigned int now, unsigned int level)   /* 8-bit signed reading vs level, with a dead zone */
{
    int v = (signed char)now - (signed char)level;
    if (v > 6) return v - 6;
    if (v < -6) return v + 6;
    return 0;
}

static void controls(unsigned int dip, unsigned int pb)
{
    unsigned int a = ACCEL;             /* <temp, X, Y, Z> */
    /* As the board is held: the sensor's X axis is forward / back (positive = tilted forward,
       checked on the board), its Y axis is left / right. SW12 / SW13 flip either one. */
    int fwd  = tilt(a >> 16, accel_level >> 16);
    int side = tilt(a >> 8, accel_level >> 8);
    if (dip & 0x1000) fwd = -fwd;
    if (dip & 0x2000) side = -side;
    int *s = julia ? &julia_step : &step;

    /* tilt forward: the picture moves up (the view centre moves down the screen, +y);
       tilt right: the picture moves right (the view centre moves left, -x) */
    if (julia) {                        /* tilt steers the Julia constant: the set morphs */
        jc_x -= side * 1024;
        jc_y += fwd * 1024;
    } else {                            /* tilt flies around the Mandelbrot set */
        centre_x -= side * (*s >> 3);
        centre_y += fwd * (*s >> 3);
        if (centre_x > FX(1.5)) centre_x = FX(1.5);
        if (centre_x < FX(-2.5)) centre_x = FX(-2.5);
        if (centre_y > FX(1.5)) centre_y = FX(1.5);
        if (centre_y < FX(-1.5)) centre_y = FX(-1.5);
    }
    if ((pb & BTNR) && *s > 64)         /* zoom in 1/16 per frame */
        *s -= *s >> 4;
    if ((pb & BTNL) && *s < FX(4.0 / 96))
        *s += (*s >> 4) + 1;
}

static unsigned int to_bcd(unsigned int v)  /* the 7-seg shows hex digits: show decimal instead */
{
    unsigned int out = 0;
    for (int shift = 0; shift < 32; shift += 4) {
        out |= (v % 10) << shift;
        v /= 10;
    }
    return out;
}

/* ---------------------------------------------------------------- main */
int main(void)
{
    LED = 0x01;                         /* boot self-test: main reached */
    OLED_CTRL = 0x14;                   /* 16-bit colour (5-6-5), auto-advance along the rows */
    OLED_DATA16 = 0;                    /* arm auto-advance */
    INT_EN = BTNC;
    accel_level = ACCEL;                /* level reference (taken again after the first frame) */
    unsigned int frames = 0;
#ifdef PICTURE                          /* for the docs: Julia set (1), zoomed in (2), zoom flight (3) */
    if (PICTURE == 1) { julia = 1; jc_x = FX(-0.822); jc_y = FX(0.156); }   /* c = -0.8 + 0.156i at phase 0 */
    else if (PICTURE == 2) { centre_x = FX(-0.7453); centre_y = FX(0.1127); step = FX(3.0 / 96 / 8); }  /* seahorse valley */
    else { centre_x = FX(-0.7453); centre_y = FX(0.1127); }  /* (3) full view on seahorse valley: hold BTNR to zoom */
#endif

    for (;;) {
        unsigned int dip = DIP;
        CPU_CTRL = dip & 7;             /* SW2-0: switch the hardware enhancements off */
        controls(dip, PB);
        int max_iter = 32 + 16 * ((dip >> 4) & 15);

        unsigned int start = CYCLECOUNT;
        OLED_COL = W - 1;               /* the next write wraps to pixel (0, 0) */
        OLED_ROW = H - 1;
        if (dip & 8)
            render_plain(max_iter);     /* SW3: plain RV32IM multiplies */
        else
            render_mulsr(max_iter);
        unsigned int cycles = CYCLECOUNT - start;

        if (frames == 0) LED = 0x03;    /* boot self-test: first frame drawn */
        OLED_CTRL = 0x08;               /* present */
        SEVENSEG = to_bcd((dip & 0x8000) ? cycles / (total_iters ? total_iters : 1) : cycles);
        while (OLED_STATUS & 1)         /* wait until the swap has happened */
            ;
        if (frames == 0)                /* calibrate: whatever the board reads now counts as level */
            accel_level = ACCEL;
        frames++;
        phase++;
        LED = (julia ? 0x80 : 0) | ((frames & 1) << 6) | (dip & 15) | (frames == 1 ? 0x04 : 0);
    }
}
