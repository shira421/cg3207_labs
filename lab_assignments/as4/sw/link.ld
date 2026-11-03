/* CG3207 Assignment 4 linker script.
   IROM (instructions only) at 0x00400000, DMEM (constants, variables, stack) at 0x10010000,
   matching IROM_BASE / DMEM_BASE in Wrapper.v. Constant data (.rodata) goes to DMEM, because the
   CPU can only load data from DMEM and MMIO, not from IROM. */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IROM (rx)  : ORIGIN = 0x00400000, LENGTH = 4K   /* IROM_DEPTH_BITS = 12 */
    DMEM (rwx) : ORIGIN = 0x10010000, LENGTH = 4K   /* DMEM_DEPTH_BITS = 12 */
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.init))     /* crt0: reset jump and interrupt vector, must be first */
        *(.text .text.*)
    } > IROM

    .data :
    {
        *(.rodata .rodata.* .srodata .srodata.*)
        *(.data .data.* .sdata .sdata.*)
        *(.sbss .sbss.* .bss .bss.* COMMON)
        . = ALIGN(4);
    } > DMEM

    __global_pointer$ = ADDR(.data) + 0x800;
    __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    __data_end = .;

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.note*) *(.eh_frame*) }
}
