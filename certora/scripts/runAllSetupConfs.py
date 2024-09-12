import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('-M', '--batchMsg', metavar='M', type=str, nargs='?',
                    default='',
                    help='a message for all the jobs')

setup_confs = {
    "DualGovernance",
    "EmergencyActivationCommittee",
    "EmergencyExecutionCommittee",
    "EmergencyProtectedTimelock",
    "Escrow",
    "Executor",
    "ResealManager",
    "TiebreakerCore",
    "TiebreakerSubCommittee"
}

for name in setup_confs:
    args = parser.parse_args()
    script = f"certora/confs/{name}_sanity.conf"
    command = f"certoraRun {script} --msg \"{name} : {args.batchMsg}\""
    print(f"runing {command}")
    subprocess.run(command, shell=True)

