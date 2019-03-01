ZoTech FPGA-based RSA accelerator
http://zotechgroup.com/


Please check ZoTech GitHub repository (https://github.com/ZoTechGroup/aws_rsa) to get the latest examples
and documentation.


############
# Overview 

The ZoTech FPGA-based RSA accelerator speeds-up the Montgomery multiplication operation - the most heavily
used operation in RSA algorithms. The accelerator supports a maximum key length of 2048 bits. This enables
a performance of 25,000 RSA signs per second with a key length of 2048 bits on F1 Amazon instance instead
of 4,500 signs that is achivable with SW-only implementation of the RSA sign algorithm on the same F1.

The interface to the ZoTech FPGA-based RSA accelerator is implemented as an OpenSSL engine shared library
ZoTech_AWS_RSA_Engine.so located in /opt directory. The engine replaces
int BN_mod_exp(BIGNUM *r, BIGNUM *a, const BIGNUM *p, const BIGNUM *m, BN_CTX *ctx). The FPGA-based
accelerator is invoked automatically each time when OpenSSL performs RSA cryptographic operation which
uses BN_mod_exp(). The AMI already contains a compiled and installed OpenSSL v1.1.1a
(the sources are located in /opt/openssl).

The RSA_Sign_Demo.cpp located in /home/centos/src/project_data on AMI and on the ZoTech GitHub repository
(https://github.com/ZoTechGroup/aws_rsa) demonstrates how to work with the ZoTech FPGA-based RSA
accelerator through the OpenSSL engine interface.

* To compile this example, run 'make'. Then the RSA_Sign_Demo executable will be created
* To run the RSA_Sign_Demo please execute the following steps:
    * sudo sh
    * ./run.sh -hw

The application performs calculations and shows performance measuremens as below:

    Overal statistic:
    
    Total time              : 11.83 sec
    Average time per sign   : 39.42 us
    Average sign per second : 25368
    
    Engine statistic:

    Total multiplication performed      : 600000
    Total time spent by FPGA            : 8.96 sec
    Average time per one multiplication : 14.93 us
    Average FPGA load                   : 99.5 %

If you would like to compare the speed with the pure SW implementation, use '-sw' argument instead '-hw'


#################################################
# How to use HW accelerator in your application 

To use the ZoTech FPGA-based RSA accelerator as it is, your application should be OpenSSL-based. In case
you have a more efficient implementation of RSA, you can replace OpenSSL's functions with your own
implementation and call BN_mod_exp() each time you need to invoke HW accelerator to perform
multiplication.

The best performance can be achieved by combining multithread mode with OpenSSL's ASYNC_JOB:
the application creates threads and each thread creates some number of ASYNC_JOBs. Recommended number of
threads is <number of CPU on F1 instance> - 2


** Important note: ZoTech FPGA-based RSA accelerator supports multithreading, but doesn't support
                   multiprocessing. This means that your application can create some number of threads
                   with ASYNC_JOBs and call BN_mod_exp() from these threads and ASYNC_JOBs but can't use
                   'fork' to duplicate the process


1. Load engine
============== 

To load the ZoTech_AWS_RSA_Engine shared library use OpenSSL's "dynamic" engine designated to load and
link external OpenSSL engines. Do the following steps:

  * ENGINE *e = ENGINE_by_id("dynamic");                                      - create instance of 
                                                                                dynamic engine 

  * ENGINE_ctrl_cmd_string(e, "SO_PATH", "/opt/Zotech_AWS_RSA_Engine.so", 0); - set path to 
                                                                                ZoTech_AWS_RSA_Engine

  * ENGINE_ctrl_cmd_string(e, "ID"     , "zotech_aws_rsa_kernel", 0);         - set ID to 
                                                                                ZoTech_AWS_RSA_Engine

  * ENGINE_ctrl_cmd_string(e, "LOAD"   , NULL                   , 0);         - load ZoTech_AWS_RSA_Engine

  * ENGINE_init(e)                                                            - initialize 
                                                                                ZoTech_AWS_RSA_Engine

  * ENGINE_set_default_RSA(e)                                                 - set ZoTech_AWS_RSA_Engine
                                                                                as the default engine for
                                                                                all RSA operation

The complete code example is available in RSA_Sign_Demo.cpp in function main().

2. Use ASYNC_JOBs
=================

OpenSSL ASYNC_JOB permits the optimization of resource utilization by switching between jobs when one 
needs to wait for data for processing or event. A thread starts ASYNC_JOB and then the job is running it 
reaches a point when it needs to wait. At this point the job will pause and the control will return to
the thread. A thread could continue to perform its own work and at some point restarts the job as shown
in the illustration in file Async_Job.png

The BN_mod_exp() implementation in ZoTech_AWS_RSA_Engine provides the best performance when it is 
called from ASYNC_JOB. After BN_mod_exp() forwards the data to the FPGA for computation, it pauses the job
and the next job in the same thread can call BN_mod_exp() with its data. Others threads are able to 
perform the same operations in parallel. This process is illustrated in file FPGA.png

In order to run the RSA using FPGA, define job's functions to perform the desired type of cryptographic 
operations. For example, in RSA_Sign_Demo.cpp ASYNC_JOB to perform signing is defined as:

    int Sign_Job(void *arg)
    {
      sign_job_arg *a = (sign_job_arg *)arg;
    
      unsigned int sign_len = KEY_BYTE_SIZE;
    
      RSA_sign(NID_sha256, a->hash, SHA256_DIGEST_LENGTH, a->sign,  &sign_len, a->key);
    
      return 1;
    }
    

Start and restart jobs in a loop until all jobs complete the desired cryptographic operations. For example:


    while(1)
      {
        int nj = 0;               // Number of completed jobs

        for(int k = 0; k < job_qnt; k++)
          {
            if( job_stat[k] == ASYNC_FINISH )      // If job completed then count it and don't start again
              { nj++; continue; }
                                                   // ASYNC_start_job() start or restart job depending on 
                                                   // current job status

            job_stat[k] = ASYNC_start_job(&job[k], wctx, &retvalue[k], Sign_Job, (void *)&job_arg[k], 
                                                                                    sizeof(sign_job_arg));
          }

        if( nj == job_qnt )
          break;
      }

3. Get statistics from engine
=============================

ZoTech_AWS_RSA_Engine collects information which is useful for performance calculations and during the
application optimization process. The engine implements a standard OpenSSL engine interface to collect
this information. Commands are defined in RSA_Sign_Demo.h as the following enum:

    enum aws_rsa_engine_cmd
      {
        ZTE_CMD_TOTAL_MULT_QNT = ENGINE_CMD_BASE,
        ZTE_CMD_TOTAL_TIME,
        ZTE_CMD_AVERAGE_TIME,
        ZTE_CMD_AVERAGE_LOAD
      };

The ENGINE_CMD_BASE is an OpenSSL constant.

| Command | Description |
|-|-|
|ZTE_CMD_TOTAL_MULT_QNT| Return total number of multiplication performed by engine|
|ZTE_CMD_TOTAL_TIME| Return total time spent by FPGA in seconds|
|ZTE_CMD_AVERAGE_TIME| Return average time spent per one multiplication in microseconds |
|ZTE_CMD_AVERAGE_LOAD| Return average FPGA load in percent|

All values returned by the engine have type double. To access them, use the following code

    double p;

    if( ENGINE_ctrl(e, ZTE_CMD_TOTAL_MULT_QNT, sizeof(double), &p, NULL) )  
      printf("Total multiplication performed      : %d\n"       , (int)p );

    if( ENGINE_ctrl(e, ZTE_CMD_TOTAL_TIME    , sizeof(double), &p, NULL) )  
      printf("Total time spent by FPGA            : %3.2f sec\n", p );

    if( ENGINE_ctrl(e, ZTE_CMD_AVERAGE_TIME  , sizeof(double), &p, NULL) )  
      printf("Average time per one multiplication : %3.2f us\n" , p );

    if( ENGINE_ctrl(e, ZTE_CMD_AVERAGE_LOAD  , sizeof(double), &p, NULL) )
      printf("Average FPGA load                   : %3.1f %%\n" , p*100.0 );

-------------------

For more information please visit <http://zotechgroup.com>
or contact by email <info@zotechgroup.com>
