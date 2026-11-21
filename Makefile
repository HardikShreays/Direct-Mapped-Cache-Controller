# Direct-Mapped Cache Controller
#
# Phase I:
#   make sim         compile + run tb_cache_basic, dump sim/cache.vcd
#   make test_units  per-module self-check testbenches
# Phase II:
#   make test_params directed tests at several cache geometries (Gate A)
#   make trace       run tb_cache_trace on one trace (+TRACE=loop)
#   make crosscheck  RTL counters vs scripts/cache_model.py, must match exactly
#   make regress     everything: REGRESSION PASS on success (Gate B)
#   make results     regenerate results/*.csv and results/*.png (Gate C)
#   make synth       yosys synthesis log (Gate D)
#   make clean       remove sim/ artifacts

RTL := rtl/addr_decode.v rtl/valid_ram.v rtl/tag_ram.v rtl/data_ram.v \
       rtl/cache_controller.v rtl/cache_top.v
MEM := tb/main_memory_model.v
TRACES := sequential random loop stride matmul

.PHONY: sim test_units test_params trace crosscheck regress results synth clean

sim:
	@mkdir -p sim
	iverilog -g2012 -o sim/a.out $(RTL) $(MEM) tb/tb_cache_basic.v
	vvp sim/a.out

test_units:
	@mkdir -p sim
	@iverilog -g2012 -o sim/ut_addr_decode rtl/addr_decode.v  tb/tb_addr_decode.v && vvp sim/ut_addr_decode
	@iverilog -g2012 -o sim/ut_tag_ram      rtl/tag_ram.v     tb/tb_tag_ram.v     && vvp sim/ut_tag_ram
	@iverilog -g2012 -o sim/ut_valid_ram    rtl/valid_ram.v   tb/tb_valid_ram.v   && vvp sim/ut_valid_ram
	@iverilog -g2012 -o sim/ut_data_ram     rtl/data_ram.v    tb/tb_data_ram.v    && vvp sim/ut_data_ram

test_params:
	@mkdir -p sim
	@iverilog -g2012 -o sim/ut_params_1k16 $(RTL) $(MEM) tb/tb_cache_params.v && \
	 vvp sim/ut_params_1k16
	@iverilog -g2012 -Ptb_cache_params.CACHE_BYTES=2048 -Ptb_cache_params.BLOCK_BYTES=32 \
	 -o sim/ut_params_2k32 $(RTL) $(MEM) tb/tb_cache_params.v && vvp sim/ut_params_2k32

trace:
	@mkdir -p sim
	iverilog -g2012 -o sim/tb_trace $(RTL) $(MEM) tb/tb_cache_trace.v
	vvp sim/tb_trace +trace=traces/$(TRACE).trace

crosscheck:
	python3 scripts/crosscheck.py

regress:
	python3 scripts/regress.py

results:
	python3 scripts/run_results.py

synth:
	@if command -v yosys >/dev/null 2>&1; then \
	  mkdir -p results; \
	  yosys -p "read_verilog rtl/addr_decode.v rtl/valid_ram.v rtl/tag_ram.v rtl/data_ram.v rtl/cache_controller.v rtl/cache_top.v; synth -top cache_top; stat" | tee results/synth_yosys.log; \
	else \
	  echo "yosys not installed -- see results/synth_yosys.log note"; exit 1; \
	fi

clean:
	rm -rf sim
