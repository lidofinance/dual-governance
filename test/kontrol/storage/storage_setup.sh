forge inspect DualGovernance storage > test/kontrol/storage/DualGovernance.json
forge inspect Escrow storage > test/kontrol/storage/Escrow.json
forge inspect StETHModel storage > test/kontrol/storage/StETHModel.json
forge inspect WithdrawalQueueModel storage > test/kontrol/storage/WithdrawalQueueModel.json
forge inspect EmergencyProtectedTimelock storage > test/kontrol/storage/EmergencyProtectedTimelock.json

python3 test/kontrol/storage/storage_setup.py test/kontrol/storage/DualGovernance.json 0.8.26 DualGovernance > test/kontrol/storage/DualGovernanceStorageConstants.sol
python3 test/kontrol/storage/storage_setup.py test/kontrol/storage/Escrow.json 0.8.26 Escrow > test/kontrol/storage/EscrowStorageConstants.sol
python3 test/kontrol/storage/storage_setup.py test/kontrol/storage/StETHModel.json 0.8.26 StETH > test/kontrol/storage/StETHStorageConstants.sol
python3 test/kontrol/storage/storage_setup.py test/kontrol/storage/WithdrawalQueueModel.json 0.8.26 WithdrawalQueue > test/kontrol/storage/WithdrawalQueueStorageConstants.sol
python3 test/kontrol/storage/storage_setup.py test/kontrol/storage/EmergencyProtectedTimelock.json 0.8.26 EmergencyProtectedTimelock > test/kontrol/storage/EmergencyProtectedTimelockStorageConstants.sol
