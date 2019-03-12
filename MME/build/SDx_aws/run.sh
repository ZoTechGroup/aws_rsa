# Running FPGA-accelerated application with warning, it should be run with root rights

if [ $USER != "root" ]; then
    echo "ERROR: FPGA-accelerated application should be run with root rights: sudo sh"
else
	source /opt/Xilinx/SDx/2017.4.rte.dyn/setup.sh 
    ./test_rsa_hls
fi
