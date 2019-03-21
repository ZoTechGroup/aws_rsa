# Building sw part only of AWS FPGA-accelerated application
g++ -O3 -DNDEBUG -std=c++0x -W -Wall -Wno-unknown-pragmas -Wno-unused-label -Wno-extra\
    -pthread -lpthread -lgmp -lOpenCL -DMAX_RSA_BITS=2048 -DUSE_OPENCL -I$XILINX_VIVADO/include -o test_rsa_hls\
    ../../src/rsa_test_aws.cpp\
    ../../src/rsa_gmp.cpp\
    ../../src/rsa_pow.cpp\
    ../../src/rsa_seq.cpp\
    ../../src/rsa_int.cpp\
    ../../src/rsa.cpp
