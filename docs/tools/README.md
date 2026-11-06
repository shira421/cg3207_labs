# docs/tools

Scripts that draw the pictures in `docs/media`. Python 3 with matplotlib and Pillow
(`pip install matplotlib pillow`).

| Script | Draws | Input |
|---|---|---|
| `render_frames.py` | Fractal frames (PNG) and the GIFs | The demo's `AA_IROM.mem` / `AA_DMEM.mem`, run on the reference model `lab_assignments/as4/sim/iss.py`. Its frames are pixel-identical to the ones `sim/tb_cpu.v +frames` writes from the RTL, but it runs about 100× faster |
| `make_figures.py` | `pipeline_timing.png`, `performance.png`, and with `--vcd` the three `wave_*.png` | A VCD of `tb_all_enhancements` (the commands are in the script's header) |
| `datapath_svg.py` | `pipeline_datapath.svg` | — |
| `vcd.py` | — | Small VCD reader used by `make_figures.py` |

The GIFs in the READMEs:

```sh
cd lab_assignments/as4/sw
python3 build.py demo/fractal.c --out /tmp/zoom  --no-install --cflags=-DPICTURE=3   # seahorse valley
python3 build.py demo/fractal.c --out /tmp/julia --no-install --cflags=-DPICTURE=1   # Julia set
cd ../../../docs/tools
python3 render_frames.py /tmp/zoom  /tmp/zoom/png  --frames 80 --dip 0x40 --hold-btnr --gif ../media/mandelbrot_zoom.gif
python3 render_frames.py /tmp/julia /tmp/julia/png --frames 64 --gif ../media/julia_orbit.gif
```

`--no-install` keeps the Vivado project's `.mem` files unchanged. `PICTURE` only sets the starting
view; the code is otherwise the program in the bitstream. `--dip 0x40` sets SW6 (96 iterations, for
more detail when zoomed in) and `--hold-btnr` holds the zoom button down.
