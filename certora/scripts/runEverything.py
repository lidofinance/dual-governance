import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('-M', '--batchMsg', metavar='M', type=str, nargs='?',
                    default='',
                    help='a message for all the jobs')
args = parser.parse_args()

escrow_rules = [
    "E_State_1_rageQuitFinalState",
    "E_KP_5_rageQuitStarter",
    "E_KP_3_rageQuitNolockUnlock",
    "E_KP_4_unlockMinTime",
    "W2_2_batchesQueueCloseFinalState",
    "W2_2_batchesQueueCloseNoChange",
    "E_KP_1_rageQuitSupportValue",
    "stateTransition_unstethRecord"
]

simple_conf_files = [
    "AdminExecutorRule",
    "DualGovernance",
    "EmergencyProtectedTimelock",
    "EPT_cancelling",
    "EPT_emergency_activation",
    "EPT_emergency_config",
    "EPT_emergency_deactivation",
    "EPT_general_config_state",
    "EPT_general_mechanics",
    "Escrow_frontrunning",
    "Escrow_solvency_batchesQueue",
    "Escrow_validState",
    "TimelockedGovernance"
]

project_contracts = [
    'DummyWithdrawalQueue', 'DummyStETH', 'DummyWstETH', 'Escrow', 'ImmutableDualGovernanceConfigProvider', 'DualGovernance'
]


def run_escrow_separate_rules():
    for rule in escrow_rules:
        script = f"certora/confs/Escrow.conf"
        command = f"certoraRun {script} --msg \" Escrow solo {rule} {args.batchMsg}\" --rule \"{rule}\" --parametric_contracts \"Escrow\""
        print(f"runing {command}")
        subprocess.run(command, shell=True)

def run_escrow_separate_rules_and_contracts():
    for contract in project_contracts:
        for rule in escrow_rules:
            script = f"certora/confs/Escrow.conf"
            command = f"certoraRun {script} --msg \" Escrow {contract} {rule} {args.batchMsg}\" --rule \"{rule}\" --parametric_contracts \"{contract}\""
            print(f"runing {command}")
            subprocess.run(command, shell=True)

def run_escrow_separate_rules_all_contracts():
    for rule in escrow_rules:
        script = f"certora/confs/Escrow.conf"
        command = f"certoraRun {script} --msg \" Escrow all {rule} {args.batchMsg}\" --rule \"{rule}\""
        print(f"runing {command}")
        subprocess.run(command, shell=True)

def run_escrow_solvency_eth():
    solvency_run_options  = [
        f"--msg \"Escrow Solvency Most : {args.batchMsg}\"", # all solvency runs except for 2 methods for ETH_solvency
        f"--msg \"Escrow Solvency_ETH claimNext1 : {args.batchMsg}\" --method \"claimNextWithdrawalsBatch(uint256)\" --rule \"solvency_ETH\" --prover_args \"-split false\" --smt_timeout 7200",
        f"--msg \"Escrow Solvency_ETH claimNext2 : {args.batchMsg}\" --method \"claimNextWithdrawalsBatch(uint256,uint256[])\" --rule \"solvency_ETH\" --prover_args \"-split false\" --smt_timeout 7200"
    ]
    for opts in solvency_run_options:
        script = f"certora/confs/Escrow_solvency_ETH.conf"
        command = f"certoraRun {script} {opts}"
        print(f"runing {command}")
        subprocess.run(command, shell=True)

def run_simple_confs():
    for conf in simple_conf_files:
        script = f"certora/confs/{conf}.conf"
        command = f"certoraRun {script} --msg \"{conf} : {args.batchMsg}\""
        print(f"running {command}")
        subprocess.run(command, shell=True)

# This is sufficient to cover all the escrow basic rules
run_escrow_separate_rules_all_contracts()
# This will cover all the solvency runs. Just two methods of just Solvency_ETH
# need to be rerun separately with specific options for performance reasons
run_escrow_solvency_eth()
run_simple_confs()
