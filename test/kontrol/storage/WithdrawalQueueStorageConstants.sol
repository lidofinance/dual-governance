pragma solidity 0.8.26;

library WithdrawalQueueStorageConstants {
    uint256 public constant STORAGE_OWNERS_SLOT = 2;
    uint256 public constant STORAGE_OWNERS_OFFSET = 0;
    uint256 public constant STORAGE_OWNERS_SIZE = 32;
    uint256 public constant STORAGE_BALANCES_SLOT = 3;
    uint256 public constant STORAGE_BALANCES_OFFSET = 0;
    uint256 public constant STORAGE_BALANCES_SIZE = 32;
    uint256 public constant STORAGE_TOKENAPPROVALS_SLOT = 4;
    uint256 public constant STORAGE_TOKENAPPROVALS_OFFSET = 0;
    uint256 public constant STORAGE_TOKENAPPROVALS_SIZE = 32;
    uint256 public constant STORAGE_OPERATORAPPROVALS_SLOT = 5;
    uint256 public constant STORAGE_OPERATORAPPROVALS_OFFSET = 0;
    uint256 public constant STORAGE_OPERATORAPPROVALS_SIZE = 32;
    uint256 public constant STORAGE_LASTREQUESTID_SLOT = 6;
    uint256 public constant STORAGE_LASTREQUESTID_OFFSET = 0;
    uint256 public constant STORAGE_LASTREQUESTID_SIZE = 32;
    uint256 public constant STORAGE_LASTFINALIZEDREQUESTID_SLOT = 7;
    uint256 public constant STORAGE_LASTFINALIZEDREQUESTID_OFFSET = 0;
    uint256 public constant STORAGE_LASTFINALIZEDREQUESTID_SIZE = 32;
    uint256 public constant STORAGE_LOCKEDETHERAMOUNT_SLOT = 8;
    uint256 public constant STORAGE_LOCKEDETHERAMOUNT_OFFSET = 0;
    uint256 public constant STORAGE_LOCKEDETHERAMOUNT_SIZE = 32;
    uint256 public constant STORAGE_REQUESTS_SLOT = 9;
    uint256 public constant STORAGE_REQUESTS_OFFSET = 0;
    uint256 public constant STORAGE_REQUESTS_SIZE = 32;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_SIZE = 160;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSTETH_SLOT = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSTETH_OFFSET = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSTETH_SIZE = 32;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSHARES_SLOT = 1;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSHARES_OFFSET = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_AMOUNTOFSHARES_SIZE = 32;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_SLOT = 2;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_OFFSET = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_OWNER_SIZE = 20;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_TIMESTAMP_SLOT = 3;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_TIMESTAMP_OFFSET = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_TIMESTAMP_SIZE = 32;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISFINALIZED_SLOT = 4;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISFINALIZED_OFFSET = 0;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISFINALIZED_SIZE = 1;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_SLOT = 4;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_OFFSET = 1;
    uint256 public constant STRUCT_WITHDRAWALQUEUEMODEL_WITHDRAWALREQUEST_ISCLAIMED_SIZE = 1;
}
