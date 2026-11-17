# Direct-Mapped Cache Controller -- Phase I targets
#
#   make sim         compile + run tb_cache_basic, dump sim/cache.vcd
#   make test_units  per-module self-check testbenches
#   make clean       remove sim/ artifacts
#
# Phase II will add: regress, crosscheck, results, synth.

RTL := rtl/addr_decode.v rtl/valid_ram.v rtl/tag_ram.v rtl/data_ram.v \
       rtl/cache_controller.v rtl/cache_top.v
MEM := tb/main_memory_model.v

.PHONY: sim test_units clean

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

# make regress, crosscheck, results, synth  -- Phase II targets, added later

clean:
	rm -rf sim
