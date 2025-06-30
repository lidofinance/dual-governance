// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library RolesTracker {
    struct Context {
        address[] grantedTo;
        address[] revokedFrom;
    }

    function addGrantedTo(Context memory self, address grantedTo) internal pure {
        address[] memory prevGrantedTo = self.grantedTo;
        uint256 prevGrantedToCount = self.grantedTo.length;

        self.grantedTo = new address[](prevGrantedToCount + 1);
        _copyAddressesArray({origin: prevGrantedTo, destination: self.grantedTo});

        self.grantedTo[prevGrantedToCount] = grantedTo;
    }

    function addRevokedFrom(Context memory self, address revokedFrom) internal pure {
        address[] memory prevRevokedFrom = self.revokedFrom;
        uint256 prevRevokedFromCount = self.revokedFrom.length;

        self.revokedFrom = new address[](prevRevokedFromCount + 1);
        _copyAddressesArray({origin: prevRevokedFrom, destination: self.revokedFrom});

        self.revokedFrom[prevRevokedFromCount] = revokedFrom;
    }

    function _copyAddressesArray(address[] memory origin, address[] memory destination) private pure {
        for (uint256 i = 0; i < origin.length; ++i) {
            destination[i] = origin[i];
        }
    }
}
