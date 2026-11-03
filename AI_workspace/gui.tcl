# Prefer the bench's saved waveform layout. Resolve from this script, not cwd.
set wave_config [file normalize [file join [file dirname [info script]] .. bottleneck bench tb_core tb_core.wcfg]]
if {[file exists $wave_config]} {
    open_wave_config $wave_config
    puts "Wave configuration loaded: $wave_config"
} else {
    puts "No tb_core.wcfg found; using default interface waves."
    add_wave /tb_core/clk /tb_core/nrst
    add_wave /tb_core/iv /tb_core/ir /tb_core/il
    add_wave /tb_core/ov /tb_core/ordy /tb_core/iteration
    add_wave /tb_core/idata /tb_core/odata
}
# Keep recording all signals and leave the GUI open at $finish.
log_wave -r /tb_core/*
run all
