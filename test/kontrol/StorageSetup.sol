pragma solidity 0.8.26;

import "test/kontrol/DualGovernanceStorageSetup.sol";
import "test/kontrol/EscrowStorageSetup.sol";
import "test/kontrol/ProposalOperationsSetup.sol";
import "test/kontrol/StEthStorageSetup.sol";
import "test/kontrol/WithdrawalQueueStorageSetup.sol";

contract StorageSetup is
    DualGovernanceStorageSetup,
    EscrowStorageSetup,
    ProposalOperationsSetup,
    StEthStorageSetup,
    WithdrawalQueueStorageSetup
{}
