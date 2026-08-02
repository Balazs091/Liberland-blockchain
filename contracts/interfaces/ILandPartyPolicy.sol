// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LandTypes} from "../types/LandTypes.sol";

/// @title ILandPartyPolicy
/// @notice Replaceable rules for resolving stable cadastral parties to current authorized signers.
interface ILandPartyPolicy {
    error InvalidCompanyRegistry(address registryAddress);
    error InvalidIdentityRegistry(address registryAddress);
    error InvalidOfficeRegistry(address registryAddress);

    /// @notice Returns the stable identity registry used by this policy version.
    function identityRegistry() external view returns (address registryAddress);

    /// @notice Returns the stable company registry used by this policy version.
    function companyRegistry() external view returns (address registryAddress);

    /// @notice Returns the stable office registry used by this policy version.
    function officeRegistry() external view returns (address registryAddress);

    /// @notice Returns the namespace for identity-registry persons.
    function personNamespace() external pure returns (bytes32 namespace);

    /// @notice Returns the namespace for company-registry companies.
    function companyNamespace() external pure returns (bytes32 namespace);

    /// @notice Returns the namespace for office-registry public offices.
    function officeNamespace() external pure returns (bytes32 namespace);

    /// @notice Computes the stable lookup key for a namespaced party.
    function partyKey(LandTypes.PartyRef calldata party) external pure returns (bytes32 key);

    /// @notice Reports whether the referenced party currently exists in its source registry.
    function partyExists(LandTypes.PartyRef calldata party) external view returns (bool exists);

    /// @notice Reports whether the referenced party may currently acquire land under this policy version.
    function canAcquireLand(LandTypes.PartyRef calldata party) external view returns (bool eligible);

    /// @notice Reports whether `signer` currently has authority to act for `party`.
    function isAuthorizedSigner(LandTypes.PartyRef calldata party, address signer)
        external
        view
        returns (bool authorized);
}
