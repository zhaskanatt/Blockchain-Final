// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "./PredictionMarketV1.sol";
import "../tokens/OutcomeShareToken.sol";
import "../vault/FeeVault.sol";

/// @title MarketFactory
/// @notice Deploys PredictionMarketV1 proxies using both CREATE and CREATE2.
///
/// CREATE  — non-deterministic; address depends on factory nonce.
///           Use when you need a new market quickly and don't care about the address.
///
/// CREATE2 — deterministic; address depends only on (factory, salt, initcode).
///           Use when you need a known address before deployment (e.g. pre-fund,
///           pre-approve, or commit to the address in governance).
///
/// Both paths deploy a fully initialised ERC1967Proxy pointing at the same
/// PredictionMarketV1 implementation, then wire up OutcomeShareToken and FeeVault.

contract MarketFactory is Ownable {

    // ── Immutable infrastructure ──────────────────────────────────────────────

    /// @notice The singleton V1 implementation contract all proxies point at.
    address public immutable implementation;

    address public immutable collateral;
    address public immutable shareToken;
    address public immutable feeVault;

    // ── Tracking ──────────────────────────────────────────────────────────────

    /// @notice All markets deployed by this factory (both CREATE and CREATE2).
    address[] public allMarkets;

    /// @notice Whether a given address was deployed by this factory.
    mapping(address => bool) public isMarket;

    /// @notice salt → proxy address for CREATE2 deployments (0 = not deployed).
    mapping(bytes32 => address) public create2Market;

    // ── Events ────────────────────────────────────────────────────────────────

    event MarketDeployedCreate(
        address indexed market,
        uint256 indexed index
    );
    event MarketDeployedCreate2(
        address indexed market,
        bytes32 indexed salt,
        uint256 indexed index
    );

    // ── Errors ────────────────────────────────────────────────────────────────

    error SaltAlreadyUsed(bytes32 salt);
    error ZeroAddress();

    // ── Constructor ───────────────────────────────────────────────────────────

    constructor(
        address implementation_,
        address collateral_,
        address shareToken_,
        address feeVault_,
        address initialOwner_
    ) Ownable(initialOwner_) {
        if (implementation_ == address(0) ||
            collateral_      == address(0) ||
            shareToken_      == address(0) ||
            feeVault_        == address(0)) revert ZeroAddress();

        implementation = implementation_;
        collateral     = collateral_;
        shareToken     = shareToken_;
        feeVault       = feeVault_;
    }

    // ── CREATE deployment ─────────────────────────────────────────────────────

    /// @notice Deploy a new market proxy using the EVM CREATE opcode.
    ///         Address is non-deterministic (depends on factory nonce).
    /// @return market Address of the newly deployed proxy.
    function deployWithCreate(address marketOwner)
        external
        onlyOwner
        returns (address market)
    {
        bytes memory initData = _buildInitData(marketOwner);

        // `new ERC1967Proxy(...)` compiles to a CREATE opcode
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        market = address(proxy);

        _register(market);
        emit MarketDeployedCreate(market, allMarkets.length - 1);
    }

    // ── CREATE2 deployment ────────────────────────────────────────────────────

    /// @notice Deploy a new market proxy using the EVM CREATE2 opcode.
    ///         Address is fully deterministic: keccak256(0xff ++ factory ++ salt ++ keccak256(initcode)).
    /// @param  salt        Arbitrary 32-byte value chosen by the caller.
    /// @param  marketOwner Owner of the deployed market.
    /// @return market      Address of the newly deployed proxy.
    function deployWithCreate2(bytes32 salt, address marketOwner)
        external
        onlyOwner
        returns (address market)
    {
        if (create2Market[salt] != address(0)) revert SaltAlreadyUsed(salt);

        bytes memory initData = _buildInitData(marketOwner);

        // `new ERC1967Proxy{salt: salt}(...)` compiles to a CREATE2 opcode
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(implementation, initData);
        market = address(proxy);

        create2Market[salt] = market;
        _register(market);
        emit MarketDeployedCreate2(market, salt, allMarkets.length - 1);
    }

    // ── Address prediction (CREATE2 only) ─────────────────────────────────────

    /// @notice Compute the address a CREATE2 deployment WILL have, without deploying.
    /// @param  salt        The same salt that will be passed to deployWithCreate2.
    /// @param  marketOwner Owner that will be passed to the initializer.
    /// @return predicted   The deterministic proxy address.
    function predictCreate2Address(bytes32 salt, address marketOwner)
        external
        view
        returns (address predicted)
    {
        bytes memory initData  = _buildInitData(marketOwner);
        bytes memory proxyCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initData)
        );
        bytes32 initcodeHash = keccak256(proxyCode);

        predicted = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            initcodeHash
        )))));
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    function totalMarkets() external view returns (uint256) {
        return allMarkets.length;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    function _buildInitData(address marketOwner)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeCall(
            PredictionMarketV1.initialize,
            (collateral, shareToken, feeVault, marketOwner)
        );
    }

    function _register(address market) internal {
        allMarkets.push(market);
        isMarket[market] = true;
    }
}
