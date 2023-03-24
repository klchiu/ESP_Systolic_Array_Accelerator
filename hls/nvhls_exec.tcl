# Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License")
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source $env(ROOT)/hls/run_hls_global_setup.tcl

namespace eval nvhls {
    proc run {} {

        # Get all input variables set from Makefile
        global env
        set USER_VARS {TOP_NAME CLK_PERIOD SRC_PATH SEARCH_PATH HLS_CATAPULT RUN_SCVERIFY COMPILER_FLAGS SYSTEMC_DESIGN RUN_CDESIGN_CHECKER}
        
        echo "***USER SETTINGS***"
        foreach var $USER_VARS {
            if [info exists env($var)] {
                echo "$var = $env($var)"
                set $var $env($var)
            } else { 
                echo "Warning: $var not set by user"
                set $var ""
            }
        }
        set BUP_BLOCKS {}
        #global BUP_BLOCKS
        options set Input/SearchPath ". $SEARCH_PATH"
        set rf $env(ROOT)
	options set /ComponentLibs/SearchPath "$rf/mem_bank" -append
	
	set_input_files $SRC_PATH $TOP_NAME $SYSTEMC_DESIGN
        set_compiler_flags $HLS_CATAPULT $COMPILER_FLAGS
        echo "***ZAIN USERCMD_PRE_ANALYZE***"
	usercmd_pre_analyze
	echo "***ZAIN ANALYZE***"
        go analyze
        echo "***ZAIN SETUP_LIBS***"	 
	setup_libs
        echo "***ZAIN SETUP_CLOCKS***"
	setup_clocks $CLK_PERIOD
        echo "***ZAIN SETUP_HEIR***"
	setup_hier $TOP_NAME
	echo "***ZAIN USERCMD_PRE_COMPILE***"           	
        usercmd_pre_compile
        echo "***ZAIN SET_BUP_BLOCKS***" 
	set_bup_blocks BUP_BLOCKS     
        echo "***ZAIN LOAD_BUP_BLOCKS_PRE***"
	load_bup_blocks_pre $BUP_BLOCKS 
        echo "****ZAIN GO_COMPILE***"
	go compile
	echo "***ZAIN RUN_DESIGN_CHECKER***"
        if { $RUN_CDESIGN_CHECKER eq "1" } { run_design_checker; exit }
        echo "***ZAIN GO LIBRARIES***"
	go libraries
        echo "***ZAIN LOAD_BUP_BLOCKS_POST***"
	load_bup_blocks_post $TOP_NAME $BUP_BLOCKS
        echo "***ZAIN GO ASSEMBLY***"
	go assembly
        echo "***ZAIN USERCMD_POST_ASSEMBLY***"
	usercmd_post_assembly
        echo "***ZAIN GO ARCHITECT***"
	go architect
        echo "***ZAIN USERCMD_POST_ARCHITECT***"
	usercmd_post_architect
        echo "***ZAIN PROJECT SAVE***"
	project save
        echo "***ZAIN GO ALLOCATE***"
	go allocate
        echo "***ZAIN GO SCHEDULE***"
	go schedule
        echo "***ZAIN GO DPFSM***"
	go dpfsm
        echo "***ZAIN PROJECT SAVE***"
	project save
        echo "***ZAIN GO EXTRACT***"
	go extract
        echo "***ZAIN PROJECT SAVE***"
	project save
        echo $RUN_SCVERIFY
        
        if { $RUN_SCVERIFY eq "1" } { 
          echo "run go switching, go power"
          #flow run /SCVerify/launch_make ./scverify/Verify_concat_sim_rtl_v_vcs.mk SIMTOOL=vcs sim INVOKE_ARGS= CCS_VCD_FILE=./default.fsdb CCS_VCD_TIMES=0,ns,end,ns USE_FSDB=true        
          go switching 
          flow run /PowerAnalysis/report_pre_pwropt_Verilog
          go power 
          flow run /PowerAnalysis/report_post_pwropt_Verilog
          project save
        }
        if { $RUN_SCVERIFY eq "2" } { 
          #flow run /SCVerify/launch_make ./scverify/Verify_concat_sim_rtl_v_vcs.mk SIMTOOL=vcs sim INVOKE_ARGS= CCS_VCD_FILE=./default.fsdb CCS_VCD_TIMES=0,ns,end,ns USE_FSDB=true        
          go switching 
          flow run /PowerAnalysis/report_pre_pwropt_Verilog
          project save
        }
        if { $RUN_SCVERIFY eq "3" } { 
          #flow run /SCVerify/launch_make ./scverify/Verify_concat_sim_rtl_v_vcs.mk SIMTOOL=vcs sim INVOKE_ARGS= CCS_VCD_FILE=./default.fsdb CCS_VCD_TIMES=0,ns,end,ns USE_FSDB=true        
          go switching 
          project save
        }
        exit
    }
  
    proc set_input_files {SRC_PATH TOP_NAME SYSC} {
        if { $SYSC eq "1" } {
            set type SYSTEMC
            set ext h
        } else {
            set type C++
            set ext cpp
        }
        solution file add [list $SRC_PATH/$TOP_NAME/$TOP_NAME.$ext] -type $type
        solution file add [list $SRC_PATH/$TOP_NAME/testbench.cpp] -type $type -exclude true
    }

    proc set_compiler_flags {HLS_CATAPULT COMPILER_FLAGS} {
        if { $HLS_CATAPULT eq "1" } {
            set HLS_CATAPULT_FLAG "-DHLS_CATAPULT"
        } else {
            set HLS_CATAPULT_FLAG ""
        }
        set FLAG_STR ""
        foreach flag $COMPILER_FLAGS {
            append FLAG_STR "-D$flag "
        }
        options set Input/CompilerFlags "-D_SYNTHESIS_ $HLS_CATAPULT_FLAG $FLAG_STR"
    }

    proc setup_libs {} {
        # TODO Technology Library
        set FPGA_PART_NUM "xcvu9p-flga2104-2-e"
    	set FPGA_FAMILY "VIRTEX-uplus"
    	set FPGA_SPEED_GRADE "-2"

	solution library \
    		add mgc_Xilinx-$FPGA_FAMILY$FPGA_SPEED_GRADE\_beh -- \
    		-rtlsyntool Vivado \
    		-manufacturer Xilinx \
    		-family $FPGA_FAMILY \
    		-speed $FPGA_SPEED_GRADE \
    		-part $FPGA_PART_NUM

	solution library add DUAL_PORT_RBW
    }

    proc setup_clocks {period} {
        set name clk
        set CLK_PERIODby2 [expr $period/2]
        directive set -CLOCKS "$name \"-CLOCK_PERIOD $period -CLOCK_EDGE rising -CLOCK_UNCERTAINTY 0.0 -CLOCK_HIGH_TIME $CLK_PERIODby2 -RESET_SYNC_NAME rst -RESET_ASYNC_NAME arst_n -RESET_KIND sync -RESET_SYNC_ACTIVE high -RESET_ASYNC_ACTIVE low -ENABLE_NAME {} -ENABLE_ACTIVE high\"    "
        directive set -CLOCK_NAME $name
    }
    
    proc setup_hier {TOP_NAME} {
        directive set -DESIGN_HIERARCHY "$TOP_NAME"
    } 

    proc run_design_checker {} {
      flow run /CDesignChecker/write_options {{-abr -severity error } {-abw -severity error } {-acc -severity warning } {-acs -severity warning } {-aic -severity warning } {-aob -severity error } {-apt -severity info } {-cas -severity error } {-ccc -severity warning } {-cia -severity warning } {-cns -severity warning } {-cwb -severity warning } {-dbz -severity error } {-fxd -severity warning } {-ise -severity error } {-mxs -severity info } {-ovl -severity error } {-pdd -severity warning } {-rrt -severity error } {-stf -severity info } {-sud -severity warning } {-umr -severity error }}
      #flow run /CDesignChecker/write_options {-abr -abw -aic -aob -apt -cas -ccc -cia -cns -cwb -dbz -fxd -ise -mxs -osl -ovl -pdd -rrt -stf -sud -umr } {-abr -abw -cas -dbz -ise -umr }
      #flow run /CDesignChecker/launch_sleccpc_sh ./CDesignChecker/design_checker.sh
      flow run /CDesignChecker/launch_sleccpc_sh ./SLEC_CPC/slec_cpc.sh
    }
    
    proc set_bup_blocks {BUP_BLOCKS} {
      #global BUP_BLOCKS
      #set BUP_BLOCKS {}
    }
    proc load_bup_blocks_pre {BUP_BLOCKS} {
        echo "load_bup_blocks_pre  $BUP_BLOCKS"
        foreach bup_block $BUP_BLOCKS {
            echo "loading $bup_block"
            solution options set ComponentLibs/SearchPath [exec readlink -f ../${bup_block}/Catapult] -append
            solution library add "\[Block\] ${bup_block}.v1"
        }
    }

    proc load_bup_blocks_post {TOP_NAME BUP_BLOCKS} {
        foreach bup_block $BUP_BLOCKS {
            directive set /${TOP_NAME}/${bup_block} -MAP_TO_MODULE "\[Block\] ${bup_block}.v1"
        }
    }

    proc usercmd_pre_analyze {} {}
    proc usercmd_pre_compile {} {}
    proc usercmd_post_assembly {} {}
    proc usercmd_post_architect {} {}
}
