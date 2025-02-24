# Overview and Directory Structure
This directory contains formal verification specifications for the Certora
Prover and written in the Certora Verification Language (CVL). The subdirectory
contents are as follows:
 * confs -- contains configuration files to run the verification jobs
 * harness -- contains test harnesses to help with verification, and mock 
   versions of ERC20 contracts that are relevant to but not part of this solidity project
 * mutation -- contains mutation tests that we used to gain further assurance 
   about our specifications
 * helpers -- contains a mock WithdrawalQueue and two simple contracts that inherit from Escrow
   to alow us to model multiple distinct Escrow addresses
*  specs -- contains our formal verification specifications
*  scripts -- contains a pythons cript to run simplify running some of the Escrow rules

# Run instructions
Ensure you have installed the Certora Prover. These specifications were tested with 
`certora-cli 7.24.0`. Launch each of the verification jobs from the root directory of the project with
`python certora/scripts/runEverything.py`

Many of the spec files can also be run separately with `certoraRun certora/confs/{conf_name}.conf`

The rules for Escrow.spec and EscrowSolvency.spec need to be split into more runs. The python scripts
handles this splitting. For the `solvency_ETH` rule in `Escrow_solvency_ETH.spec` both signatures of
`claimNext` will timeout when run together with all other methods. However these pass when run separately.
The python run script also handles running verification for those methods separately.