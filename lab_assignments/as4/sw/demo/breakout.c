/*
 * breakout.c - CG3207 Assignment 4 demo program: Breakout on the Pmod OLED (96 x 64).
 *
 * Controls
 *   BTNL / BTNR   move the paddle (polled every frame)
 *   BTNC          launch the ball / pause / restart after game over (push-button INTERRUPT)
 *   SW0           1 = CPU without forwarding (interlocks instead)       } written to CPU_CTRL
 *   SW1           1 = CPU without branch prediction                     } every frame
 *   SW14          autoplay: the paddle follows the ball (for comparing the modes hands-free)
 *   SW15          7-segment: 0 = cycles taken to compute + draw the last frame, 1 = score
 * Outputs
 *   OLED          the game, redrawn completely every frame into the back buffer, then presented
 *   7-segment     cycles per frame (decimal) or score
 *   LED[7:0]      LED7 paused, LED6..LED4 lives left, LED1/LED0 = SW1/SW0 (enhancement off)
 *
 * The ball moves a fixed distance per frame, so a slower CPU makes a visibly slower game; the
 * 7-segment shows the exact cost in cycles, which does not depend on the clock frequency.
 * Flip SW0 / SW1 while it runs to see what forwarding and branch prediction are worth.
 *
 * What it relies on in the CPU
 *   - pipeline + hazard unit + branch prediction: the per-pixel drawing loop
 *   - lbu / sb (byte array of bricks), lhu (colour table), sh (16-bit pixels to OLED_DATA)
 *   - push-button interrupt, handler ending in mret (isr below; vector in crt0.s)
 *   - mul (score), divu / remu (decimal 7-segment display) on the MCycle unit
 *   - OLED v2 double buffering (present + wait for OLED_STATUS)
 *
 * Build: python3 ../build.py breakout.c        (in WSL / Linux, needs gcc-riscv64-unknown-elf)
 *
 * AI assistance declaration (CG3207 lab manual): written with Claude (Anthropic), Claude Opus 5.5, Nov 2026.
 */

#define MMIO_BASE       0xFFFF0000u
#define REG(off)        (*(volatile unsigned int *)(MMIO_BASE + (off)))
#define REG16(off)      (*(volatile unsigned short *)(MMIO_BASE + (off)))
#define OLED_COL        REG(0x20)
#define OLED_ROW        REG(0x24)
#define OLED_DATA16     REG16(0x28)     /* 16-bit colour mode: written with sh */
#define OLED_CTRL       REG(0x2C)
#define OLED_STATUS     REG(0x30)
#define LED             REG(0x60)
#define DIP             REG(0x64)
#define PB              REG(0x68)
#define SEVENSEG        REG(0x80)
#define CYCLECOUNT      REG(0xA0)
#define CPU_CTRL        REG(0x70)
#define INT_EN          REG(0x74)
#define INT_FLAGS       REG(0x78)

#define BTNR 1u                          /* PB[0] */
#define BTNC 2u                          /* PB[1] */
#define BTNL 4u                          /* PB[2] */

#define W 96
#define H 64
#define BRICK_ROWS 6
#define BRICK_COLS 12                    /* 8 pixels each: 7 brick + 1 gap */
#define BRICK_TOP 6                      /* 4 pixel rows each: 3 brick + 1 gap */
#define BRICK_BOTTOM (BRICK_TOP + 4 * BRICK_ROWS)
#define PADDLE_Y 60
#define PADDLE_W 16
#define BALL 2
#define SUB 16                           /* ball position in 1/16 pixel */

#define RGB(r, g, b) ((unsigned short)((((r) >> 3) << 11) | (((g) >> 2) << 5) | ((b) >> 3)))

static const unsigned short row_colour[BRICK_ROWS] = {
    RGB(255, 40, 40), RGB(255, 140, 0), RGB(255, 230, 0),
    RGB(40, 220, 60), RGB(40, 160, 255), RGB(170, 80, 255)
};
static const unsigned short bg_colour[H / 8] = {          /* a dark gradient, one colour per 8 rows */
    RGB(0, 0, 40), RGB(0, 0, 36), RGB(0, 0, 32), RGB(0, 0, 28),
    RGB(0, 0, 24), RGB(0, 0, 20), RGB(0, 0, 16), RGB(0, 0, 12)
};

static unsigned char bricks[BRICK_ROWS][BRICK_COLS];      /* 1 = still there */
static int bricks_left;
static int ball_x, ball_y, vel_x, vel_y;                  /* in 1/16 pixel */
static int paddle_x;
static int lives, score, level;
static unsigned int last_frame_cycles;

/* Shared with the interrupt handler */
static volatile int launched, paused, game_over, restart_req;

/* ------------------------------------------------------------------ interrupt */
/* BTNC press. GCC saves every register this uses and returns with mret. */
void __attribute__((interrupt("machine"))) isr(void)
{
    unsigned int f = INT_FLAGS;
    if (f & BTNC) {
        if (game_over)
            restart_req = 1;
        else if (!launched)
            launched = 1;
        else
            paused = !paused;
    }
    INT_FLAGS = f;                                        /* acknowledge */
}

/* ------------------------------------------------------------------ game */
static void reset_bricks(void)
{
    for (int r = 0; r < BRICK_ROWS; r++)
        for (int c = 0; c < BRICK_COLS; c++)
            bricks[r][c] = 1;
    bricks_left = BRICK_ROWS * BRICK_COLS;
}

static void serve(void)
{
    ball_x = (paddle_x + PADDLE_W / 2 - BALL / 2) * SUB;
    ball_y = (PADDLE_Y - BALL) * SUB;
    launched = 0;
    paused = 0;
    vel_x = (score & 1) ? 10 : -10;
    vel_y = -(14 + 2 * level);
}

static void new_game(void)
{
    lives = 3;
    score = 0;
    level = 0;
    game_over = 0;
    paddle_x = (W - PADDLE_W) / 2;   /* before serve(), which puts the ball on the paddle */
    reset_bricks();
    serve();
}

static void update(unsigned int pb, unsigned int dip)
{
    /* paddle */
    if (dip & 0x4000) {                                   /* autoplay */
        int target = (ball_x / SUB) + BALL / 2 - PADDLE_W / 2;
        if (paddle_x < target - 1) paddle_x += 2;
        else if (paddle_x > target + 1) paddle_x -= 2;
    } else {
        if (pb & BTNL) paddle_x -= 2;
        if (pb & BTNR) paddle_x += 2;
    }
    if (paddle_x < 0) paddle_x = 0;
    if (paddle_x > W - PADDLE_W) paddle_x = W - PADDLE_W;

    if (game_over || paused)
        return;
    if (!launched) {                                      /* ball sits on the paddle */
        ball_x = (paddle_x + PADDLE_W / 2 - BALL / 2) * SUB;
        ball_y = (PADDLE_Y - BALL) * SUB;
        if (dip & 0x4000)                                 /* autoplay serves by itself */
            launched = 1;
        return;
    }

    ball_x += vel_x;
    ball_y += vel_y;

    /* walls */
    if (ball_x < 0) { ball_x = 0; vel_x = -vel_x; }
    if (ball_x > (W - BALL) * SUB) { ball_x = (W - BALL) * SUB; vel_x = -vel_x; }
    if (ball_y < 0) { ball_y = 0; vel_y = -vel_y; }

    int bx = ball_x / SUB, by = ball_y / SUB;

    /* paddle: the bounce angle depends on where the ball hits it */
    if (vel_y > 0 && by + BALL >= PADDLE_Y && by <= PADDLE_Y + 1 &&
        bx + BALL > paddle_x && bx < paddle_x + PADDLE_W) {
        int off = (bx + BALL / 2) - (paddle_x + PADDLE_W / 2);   /* -9 .. 8 */
        vel_y = -vel_y;
        vel_x = off * 3;
        if (vel_x == 0) vel_x = 2;
        ball_y = (PADDLE_Y - BALL) * SUB;
    }

    /* bricks: test the ball's centre */
    int cx = bx + BALL / 2, cy = by + BALL / 2;
    if (cy >= BRICK_TOP && cy < BRICK_BOTTOM) {
        int r = (cy - BRICK_TOP) >> 2, c = cx >> 3;
        if (bricks[r][c]) {
            bricks[r][c] = 0;
            bricks_left--;
            vel_y = -vel_y;
            score += (BRICK_ROWS - r) * (level + 1) * 10;     /* mul */
            if (bricks_left == 0) {
                level++;
                reset_bricks();
                serve();
            }
        }
    }

    /* lost the ball */
    if (by >= H) {
        lives--;
        if (lives == 0)
            game_over = 1;
        else
            serve();
    }
}

/* ------------------------------------------------------------------ drawing */
/* Every pixel of the frame is computed and written, row by row: 6144 half-word stores to
   OLED_DATA in auto-advance mode, with a few decisions per pixel. This is the hot loop. */
static void draw(void)
{
    int bx = ball_x / SUB, by = ball_y / SUB;
    int ball_on = launched || !game_over;

    /* Start at (0,0): in auto-advance mode each write first steps to the next pixel, so
       pointing at the last pixel makes the first write wrap to the first one. */
    OLED_COL = W - 1;
    OLED_ROW = H - 1;

    for (int y = 0; y < H; y++) {
        unsigned short bg = bg_colour[y >> 3];
        int ball_row = ball_on && y >= by && y < by + BALL;

        if (y >= BRICK_TOP && y < BRICK_BOTTOM && ((y - BRICK_TOP) & 3) != 3) {
            const unsigned char *row = bricks[(y - BRICK_TOP) >> 2];
            unsigned short colour = row_colour[(y - BRICK_TOP) >> 2];
            for (int x = 0; x < W; x++) {
                unsigned short p = bg;
                if ((x & 7) != 7 && row[x >> 3])
                    p = colour;
                if (ball_row && x >= bx && x < bx + BALL)
                    p = RGB(255, 255, 255);
                OLED_DATA16 = p;
            }
        } else if (y >= PADDLE_Y && y < PADDLE_Y + 2) {
            unsigned short pc = game_over ? RGB(120, 120, 120) : RGB(230, 230, 230);
            for (int x = 0; x < W; x++) {
                unsigned short p = bg;
                if (x >= paddle_x && x < paddle_x + PADDLE_W)
                    p = pc;
                if (ball_row && x >= bx && x < bx + BALL)
                    p = RGB(255, 255, 255);
                OLED_DATA16 = p;
            }
        } else {
            for (int x = 0; x < W; x++) {
                unsigned short p = bg;
                if (ball_row && x >= bx && x < bx + BALL)
                    p = RGB(255, 255, 255);
                OLED_DATA16 = p;
            }
        }
    }
}

/* 7-segment shows hex digits, so convert to BCD for a decimal display (divu / remu). */
static unsigned int to_bcd(unsigned int v)
{
    unsigned int out = 0;
    for (int shift = 0; shift < 32; shift += 4) {
        out |= (v % 10) << shift;
        v /= 10;
    }
    return out;
}

/* ------------------------------------------------------------------ main */
int main(void)
{
    OLED_CTRL = 0x14;               /* 16-bit colour (5-6-5), auto-advance along the rows */
    OLED_DATA16 = 0;                /* one write so that auto-advance is armed (see draw) */
    INT_EN = BTNC;                  /* interrupt on BTNC presses only */
    new_game();

    for (;;) {
        unsigned int start = CYCLECOUNT;
        unsigned int dip = DIP;
        CPU_CTRL = dip & 3;         /* SW1, SW0: switch the enhancements off */

        if (restart_req) {
            restart_req = 0;
            new_game();
        }
        update(PB, dip);
        draw();
        last_frame_cycles = CYCLECOUNT - start;

        OLED_CTRL = 0x08;           /* present the frame we just drew */
        SEVENSEG = (dip & 0x8000) ? to_bcd(score) : to_bcd(last_frame_cycles);
        LED = (paused ? 0x80 : 0) | ((((1 << lives) - 1) << 4) & 0x70) | (dip & 3);
        while (OLED_STATUS & 1)     /* wait until it is safe to draw again */
            ;
    }
}
