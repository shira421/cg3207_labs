# Start here

Use this package with as4.xpr in this repository.

1. Add tb_all_enhancements.v and tb_system_enhancements.v as SIMULATION sources.
2. Keep TOP as the synthesis top.
3. Set tb_all_enhancements as simulation top and launch Behavioural Simulation.
4. In the simulation Tcl Console:

   set demo_view branch
   source {C:/your/extracted/path/all_waves.tcl}

5. Require the final console PASS. The script runs the full short test.
6. Read SHOW_AND_EXPLAIN.md for every feature's signals, expected result,
   PC locations, screenshot guidance and a suggested explanation.
7. For another view, set demo_view to pipeline, forwarding, hazards, multiply,
   mulsr, branch, memory, interrupt or live, then source the script again.
8. For actual Wrapper integration, set tb_system_enhancements as simulation top,
   relaunch Behavioural Simulation and source system_waves.tcl.

Validation: both testbenches print PASS in Icarus Verilog against the repository RTL (see the
table at the top of SHOW_AND_EXPLAIN.md). Run them in Vivado too, and use your own PASS and
counters as the evidence you present.

Without Vivado:  cd sim/enhancement_tests && ./run_icarus.sh

No application memory files or RTL need editing.
This package covers the seven CPU enhancements and adds Wrapper interface checks.
Board clock timing, power-on initialization and the complete OLED controller remain
separate system tests, as explained in SHOW_AND_EXPLAIN.md.

