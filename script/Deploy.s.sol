// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/tokens/GovernanceToken.sol";
import "../src/tokens/OutcomeShareToken.sol";
import "../src/governance/PredictionGovernor.sol";
import "../src/governance/Treasury.sol";
import "../src/market/PredictionMarketV1.sol";
import "../src/market/MarketFactory.sol";
import "../src/oracle/OracleResolver.sol";
import "../src/vault/FeeVault.sol";
import "../src/mocks/MockERC20.sol";

contract Deploy is Script {
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint256 public constant STALENESS_THRESHOLD = 1 hours;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address priceFeed = vm.envOr("PRICE_FEED", address(0));

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 collateral = new MockERC20("Mock USDC", "mUSDC", 18);

        GovernanceToken govToken = new GovernanceToken(deployer);

        address[] memory proposers = new address[](0);

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        PredictionGovernor governor = new PredictionGovernor(IVotes(address(govToken)), timelock);

        Treasury treasury = new Treasury(address(timelock));

        OutcomeShareToken outcomeToken = new OutcomeShareToken(deployer);

        FeeVault feeVault = new FeeVault(address(collateral), deployer);

        PredictionMarketV1 implementation = new PredictionMarketV1();

        MarketFactory factory = new MarketFactory(
            address(implementation), address(collateral), address(outcomeToken), address(feeVault), deployer
        );

        outcomeToken.grantRole(outcomeToken.MINTER_ROLE(), address(factory));
        outcomeToken.grantRole(outcomeToken.DEFAULT_ADMIN_ROLE(), address(timelock));
        outcomeToken.revokeRole(outcomeToken.DEFAULT_ADMIN_ROLE(), deployer);

        OracleResolver oracle;

        if (priceFeed != address(0)) {
            oracle = new OracleResolver(priceFeed, STALENESS_THRESHOLD, address(timelock));
        }

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));

        govToken.transferOwnership(address(timelock));
        feeVault.transferOwnership(address(timelock));
        factory.transferOwnership(address(timelock));

        timelock.revokeRole(adminRole, deployer);

        vm.stopBroadcast();

        console2.log("========== DEPLOYMENT ADDRESSES ==========");
        console2.log("Deployer:", deployer);
        console2.log("Collateral:", address(collateral));
        console2.log("GovernanceToken:", address(govToken));
        console2.log("Timelock:", address(timelock));
        console2.log("Governor:", address(governor));
        console2.log("Treasury:", address(treasury));
        console2.log("OutcomeShareToken:", address(outcomeToken));
        console2.log("FeeVault:", address(feeVault));
        console2.log("MarketImplementation:", address(implementation));
        console2.log("MarketFactory:", address(factory));

        if (priceFeed != address(0)) {
            console2.log("OracleResolver:", address(oracle));
        } else {
            console2.log("OracleResolver: not deployed, PRICE_FEED not set");
        }
    }
}
