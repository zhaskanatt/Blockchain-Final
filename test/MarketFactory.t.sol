// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/market/MarketFactory.sol";
import "../src/market/PredictionMarketV1.sol";
import "../src/tokens/OutcomeShareToken.sol";
import "../src/vault/FeeVault.sol";
import "../src/mocks/MockERC20.sol";

contract MarketFactoryTest is Test {

    MarketFactory      internal factory;
    PredictionMarketV1 internal impl;
    MockERC20          internal usdc;
    OutcomeShareToken  internal shareToken;
    FeeVault           internal vault;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");

    bytes32 internal constant SALT_A = keccak256("market.A");
    bytes32 internal constant SALT_B = keccak256("market.B");

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC", 6);

        vm.prank(owner);
        shareToken = new OutcomeShareToken(owner);

        vm.prank(owner);
        vault = new FeeVault(address(usdc), owner);

        impl = new PredictionMarketV1();

        vm.prank(owner);
        factory = new MarketFactory(
            address(impl),
            address(usdc),
            address(shareToken),
            address(vault),
            owner
        );
    }

    // ── Unit: construction ────────────────────────────────────────────────────

    function test_implementation() public view {
        assertEq(factory.implementation(), address(impl));
    }

    function test_collateral() public view {
        assertEq(factory.collateral(), address(usdc));
    }

    function test_initialTotalMarkets() public view {
        assertEq(factory.totalMarkets(), 0);
    }

    // ── Unit: CREATE deployment ───────────────────────────────────────────────

    function test_deployWithCreate_returnsNonZeroAddress() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate(owner);
        assertNotEq(mkt, address(0));
    }

    function test_deployWithCreate_registeredInAllMarkets() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate(owner);
        assertEq(factory.allMarkets(0), mkt);
        assertEq(factory.totalMarkets(), 1);
    }

    function test_deployWithCreate_isMarketFlag() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate(owner);
        assertTrue(factory.isMarket(mkt));
    }

    function test_deployWithCreate_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, false); // just check it fires
        emit MarketFactory.MarketDeployedCreate(address(0), 0);
        factory.deployWithCreate(owner);
    }

    function test_deployWithCreate_isInitialized() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate(owner);
        PredictionMarketV1 market = PredictionMarketV1(mkt);
        assertEq(market.owner(), owner);
        assertEq(address(market.collateral()), address(usdc));
    }

    function test_deployWithCreate_twiceGivesDifferentAddresses() public {
        vm.prank(owner);
        address mkt1 = factory.deployWithCreate(owner);
        vm.prank(owner);
        address mkt2 = factory.deployWithCreate(owner);
        assertNotEq(mkt1, mkt2);
        assertEq(factory.totalMarkets(), 2);
    }

    function test_deployWithCreate_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployWithCreate(alice);
    }

    // ── Unit: CREATE2 deployment ──────────────────────────────────────────────

    function test_deployWithCreate2_returnsNonZeroAddress() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate2(SALT_A, owner);
        assertNotEq(mkt, address(0));
    }

    function test_deployWithCreate2_registeredInAllMarkets() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate2(SALT_A, owner);
        assertEq(factory.allMarkets(0), mkt);
        assertTrue(factory.isMarket(mkt));
    }

    function test_deployWithCreate2_saltMappingSet() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate2(SALT_A, owner);
        assertEq(factory.create2Market(SALT_A), mkt);
    }

    function test_deployWithCreate2_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, true, false, false);
        emit MarketFactory.MarketDeployedCreate2(address(0), SALT_A, 0);
        factory.deployWithCreate2(SALT_A, owner);
    }

    function test_deployWithCreate2_isInitialized() public {
        vm.prank(owner);
        address mkt = factory.deployWithCreate2(SALT_A, owner);
        PredictionMarketV1 market = PredictionMarketV1(mkt);
        assertEq(market.owner(), owner);
        assertEq(address(market.collateral()), address(usdc));
    }

    function test_deployWithCreate2_duplicateSaltReverts() public {
        vm.prank(owner);
        factory.deployWithCreate2(SALT_A, owner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MarketFactory.SaltAlreadyUsed.selector, SALT_A));
        factory.deployWithCreate2(SALT_A, owner);
    }

    function test_deployWithCreate2_differentSaltsGiveDifferentAddresses() public {
        vm.prank(owner);
        address mktA = factory.deployWithCreate2(SALT_A, owner);
        vm.prank(owner);
        address mktB = factory.deployWithCreate2(SALT_B, owner);
        assertNotEq(mktA, mktB);
    }

    function test_deployWithCreate2_nonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        factory.deployWithCreate2(SALT_A, alice);
    }

    // ── Unit: CREATE vs CREATE2 produce different addresses ───────────────────

    function test_createAndCreate2_addressesDiffer() public {
        vm.prank(owner);
        address mktCreate  = factory.deployWithCreate(owner);
        vm.prank(owner);
        address mktCreate2 = factory.deployWithCreate2(SALT_A, owner);
        assertNotEq(mktCreate, mktCreate2);
    }

    // ── Unit: address prediction ──────────────────────────────────────────────

    function test_predictCreate2Address_matchesActual() public {
        address predicted = factory.predictCreate2Address(SALT_A, owner);

        vm.prank(owner);
        address actual = factory.deployWithCreate2(SALT_A, owner);

        assertEq(predicted, actual);
    }

    function test_predictCreate2Address_differentSalts() public view {
        address addrA = factory.predictCreate2Address(SALT_A, owner);
        address addrB = factory.predictCreate2Address(SALT_B, owner);
        assertNotEq(addrA, addrB);
    }

    function test_predictCreate2Address_deterministicBeforeDeployment() public view {
        // Calling predict twice with same args gives same result (pure)
        address p1 = factory.predictCreate2Address(SALT_A, owner);
        address p2 = factory.predictCreate2Address(SALT_A, owner);
        assertEq(p1, p2);
    }

    // ── Fuzz: CREATE2 address is always deterministic ─────────────────────────

    function testFuzz_predictCreate2_alwaysMatchesDeployment(bytes32 salt) public {
        address predicted = factory.predictCreate2Address(salt, owner);

        // Only deploy if salt not already used
        if (factory.create2Market(salt) == address(0)) {
            vm.prank(owner);
            address actual = factory.deployWithCreate2(salt, owner);
            assertEq(predicted, actual);
        }
    }

    // ── Fuzz: every CREATE deployment has a unique address ────────────────────

    function testFuzz_createDeploymentsAreUnique(uint8 count) public {
        count = uint8(bound(count, 2, 10));
        address[] memory addrs = new address[](count);

        for (uint256 i; i < count; i++) {
            vm.prank(owner);
            addrs[i] = factory.deployWithCreate(owner);
        }

        // All addresses must be unique
        for (uint256 i; i < count; i++) {
            for (uint256 j = i + 1; j < count; j++) {
                assertNotEq(addrs[i], addrs[j]);
            }
        }
    }
}
