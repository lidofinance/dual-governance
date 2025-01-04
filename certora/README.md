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

# Run instructions
Ensure you have installed the Certora Prover. These specifications were tested with 
`certora-cli 7.17.2`. Launch each of the verification jobs from the root directory of the project with
`certoraRun certora/confs/DualGovernance.conf`
`certoraRun certora/confs/EmergencyProtectedTimelock.conf`
`certoraRun certora/confs/Escrow.conf`
`certoraRun certora/confs/Escrow_solvency.conf`
`certoraRun certora/confs/Escrow_validState.conf`

One of the rules in Escrow_solvency.conf `solvency_ETH` can have performance issues resulting in 
a timeout. As a workaround, it can be run separately by running 
`certoraRun certora/confs/Escrow_solvency.conf --rule solvency_ETH` in which case it should pass.