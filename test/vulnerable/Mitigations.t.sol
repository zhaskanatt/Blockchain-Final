// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/vulnerable/SecureRewardPool.sol";
import "../../src/vulnerable/SecureTreasury.sol";

// ══════════════════════════════════════════════════════════════════════════════
//  CASE STUDY #1 — Reentrancy mitigation tests
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Same attacker logic as in Exploits.t.sol, now targeting SecureRewardPool.
contract ReentrancyAttackerOnSecure {
    SecureRewardPool public pool;
    uint256 public reentrancyAttempts;

    constructor(SecureRewardPool pool_) {
        pool = pool_;
    }

    function attack() external payable {
        require(msg.value > 0, "send ETH");
        pool.deposit{value: msg.value}();
        pool.claim();
    }

    receive() external payable {
        reentrancyAttempts++;
        // Attempt re-entry — this MUST revert on the secure contract
        if (address(pool).balance > 0) {
            try pool.claim() {
                // Should never reach here
            } catch {
                // Expected: revert due to nonReentrant or zero balance
            }
        }
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract ReentrancyMitigationTest is Test {
    SecureRewardPool         internal pool;
    ReentrancyAttackerOnSecure internal attacker;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");

    uint256 internal constant POOL_SEED     = 10 ether;
    uint256 internal constant ATTACK_AMOUNT =  1 ether;

    function setUp() public {
        pool     = new SecureRewardPool();
        attacker = new ReentrancyAttackerOnSecure(pool);

        // Seed the pool with legitimate users
        vm.deal(alice, POOL_SEED / 2);
        vm.deal(bob,   POOL_SEED / 2);

        vm.prank(alice);
        pool.deposit{value: POOL_SEED / 2}();

        vm.prank(bob);
        pool.deposit{value: POOL_SEED / 2}();
    }

    // ── Mitigation: reentrancy attack is BLOCKED ──────────────────────────────

    /// @notice Attacker gains zero — deposit and claim cancel out exactly.
    ///         The test funds attack() via {value:}; no vm.deal so there is no
    ///         double-funding of the attacker's ETH balance.
    function test_mitigation_reentrancy_cannotStealMoreThanDeposited() public {
        // Give the TEST CONTRACT the ETH to forward into attack()
        vm.deal(address(this), ATTACK_AMOUNT);

        uint256 poolBefore = pool.poolBalance(); // 10 ETH (seed)

        attacker.attack{value: ATTACK_AMOUNT}();

        uint256 poolAfter     = pool.poolBalance();
        uint256 attackerAfter = address(attacker).balance;

        emit log_named_uint("Pool balance before (ETH wei)",    poolBefore);
        emit log_named_uint("Pool balance after  (ETH wei)",    poolAfter);
        emit log_named_uint("Attacker balance after (ETH wei)", attackerAfter);
        emit log_named_uint("Re-entry attempts",                 attacker.reentrancyAttempts());

        // Secure: deposit + claim cancel out — pool is unchanged
        assertEq(poolAfter, poolBefore,
                 "mitigation: pool balance must be unchanged by a failed attack");

        // Attacker recovered exactly what the test sent in — zero profit
        assertEq(attackerAfter, ATTACK_AMOUNT,
                 "mitigation: attacker ends with only what was sent in, no extra profit");
    }

    /// @notice Legitimate users can still claim after a failed attack attempt.
    function test_mitigation_reentrancy_legitimateUsersUnaffected() public {
        vm.deal(address(attacker), ATTACK_AMOUNT);
        attacker.attack{value: ATTACK_AMOUNT}();

        // Alice claims her legitimate share
        uint256 aliceBalBefore = alice.balance;
        vm.prank(alice);
        pool.claim();

        assertEq(alice.balance - aliceBalBefore, POOL_SEED / 2,
                 "mitigation: alice must receive her full reward");
        assertEq(pool.rewards(alice), 0,
                 "mitigation: alice reward zeroed after claim");
    }

    /// @notice Direct re-entry attempt on SecureRewardPool reverts.
    function test_mitigation_reentrancy_directReentryReverts() public {
        // Deploy a simple re-entrant caller
        ReentrantCaller caller = new ReentrantCaller(pool);
        vm.deal(address(caller), 1 ether);

        // The re-entry must revert (either ReentrancyGuardTransient or zero balance)
        vm.expectRevert();
        caller.attack{value: 1 ether}();
    }

    /// @notice Balance is always zeroed before transfer (CEI proof).
    ///         Uses a fresh address to avoid setUp's 5 ETH pre-deposit for alice.
    function test_mitigation_reentrancy_balanceZeroedBeforeTransfer() public {
        address freshUser = makeAddr("freshUser");
        vm.deal(freshUser, 1 ether);

        vm.prank(freshUser);
        pool.deposit{value: 1 ether}();

        // Fresh user has exactly 1 ETH reward
        assertEq(pool.rewards(freshUser), 1 ether, "CEI: pre-claim balance must be 1 ETH");

        // After claim, rewards mapping must be 0 (CEI zeroed it before the transfer)
        vm.prank(freshUser);
        pool.claim();

        assertEq(pool.rewards(freshUser), 0, "CEI: balance must be zeroed after claim");
        assertEq(freshUser.balance, 1 ether,  "CEI: user must receive their ETH back");
    }

    // ── Fuzz: attacker never extracts more than deposited ────────────────────

    function testFuzz_mitigation_attackerGainBoundedByDeposit(uint96 amount) public {
        vm.assume(amount >= 1 ether && amount <= 100 ether);
        // Fund only the test contract — no vm.deal to the attacker to avoid double-funding
        vm.deal(address(this), amount);

        uint256 poolBefore = pool.poolBalance();
        attacker.attack{value: amount}();

        // Pool must be unchanged: deposit and legitimate claim cancel out
        assertEq(pool.poolBalance(), poolBefore,
                 "fuzz mitigation: pool balance must not decrease from attack");

        // Attacker ends with exactly the amount sent in — zero extra profit
        assertEq(address(attacker).balance, amount,
                 "fuzz mitigation: attacker recovers deposit but gains nothing extra");
    }
}

/// @dev Helper: tries to re-enter claim() from receive().
contract ReentrantCaller {
    SecureRewardPool pool;
    constructor(SecureRewardPool p) { pool = p; }
    function attack() external payable {
        pool.deposit{value: msg.value}();
        pool.claim();
    }
    receive() external payable {
        pool.claim(); // must revert
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  CASE STUDY #2 — tx.origin access-control mitigation tests
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Same phishing contract logic, now targeting SecureTreasury.
contract PhishingContractOnSecure {
    SecureTreasury public treasury;
    address        public attacker;

    constructor(SecureTreasury treasury_, address attacker_) {
        treasury = treasury_;
        attacker = attacker_;
    }

    function claimRewards() external {
        uint256 bal = address(treasury).balance;
        // msg.sender == this contract — onlyOwner will reject it
        treasury.withdraw(payable(attacker), bal);
    }
}

contract AccessControlMitigationTest is Test {
    SecureTreasury             internal treasury;
    PhishingContractOnSecure   internal phishing;

    address internal admin       = makeAddr("admin");
    address internal attackerEOA = makeAddr("attackerEOA");

    uint256 internal constant TREASURY_BALANCE = 5 ether;

    function setUp() public {
        vm.prank(admin);
        treasury = new SecureTreasury(admin);

        // Fund the treasury (owner funds it)
        vm.deal(admin, TREASURY_BALANCE);
        vm.prank(admin);
        treasury.fund{value: TREASURY_BALANCE}();

        vm.prank(attackerEOA);
        phishing = new PhishingContractOnSecure(treasury, attackerEOA);
    }

    // ── Mitigation: phishing attack is BLOCKED ────────────────────────────────

    /// @notice Even when admin's EOA initiates the tx, the phishing
    ///         contract (msg.sender) is rejected by onlyOwner.
    function test_mitigation_txOrigin_phishingAttackReverts() public {
        uint256 treasuryBefore = address(treasury).balance;

        // Admin is tricked into calling the phishing contract (tx.origin == admin)
        vm.prank(admin, admin);
        vm.expectRevert(); // OwnableUnauthorizedAccount(phishingContract)
        phishing.claimRewards();

        // Treasury untouched
        assertEq(address(treasury).balance, treasuryBefore,
                 "mitigation: treasury must not lose funds");
        assertEq(attackerEOA.balance, 0,
                 "mitigation: attacker must receive nothing");
    }

    /// @notice Direct call from admin (msg.sender == owner) still works.
    function test_mitigation_txOrigin_directOwnerWithdrawSucceeds() public {
        uint256 adminBefore = admin.balance;

        vm.prank(admin);
        treasury.withdraw(payable(admin), 1 ether);

        assertEq(admin.balance - adminBefore, 1 ether,
                 "mitigation: legitimate owner withdrawal must succeed");
        assertEq(address(treasury).balance, TREASURY_BALANCE - 1 ether);
    }

    /// @notice Any non-owner address is rejected, whether EOA or contract.
    function test_mitigation_txOrigin_nonOwnerDirectCallReverts() public {
        vm.prank(attackerEOA);
        vm.expectRevert();
        treasury.withdraw(payable(attackerEOA), 1 ether);
    }

    /// @notice Attacker cannot fund with tx.origin trick either.
    function test_mitigation_txOrigin_nonOwnerFundReverts() public {
        vm.deal(attackerEOA, 1 ether);
        vm.prank(attackerEOA);
        vm.expectRevert();
        treasury.fund{value: 1 ether}();
    }

    /// @notice Treasury balance is invariant to any phishing attempts.
    function test_mitigation_txOrigin_balanceInvariantUnderPhishing() public {
        uint256 balanceBefore = address(treasury).balance;

        // Multiple phishing attempts from different callers — all revert
        address[] memory thieves = new address[](3);
        thieves[0] = makeAddr("thief1");
        thieves[1] = makeAddr("thief2");
        thieves[2] = attackerEOA;

        for (uint256 i; i < thieves.length; i++) {
            PhishingContractOnSecure p = new PhishingContractOnSecure(treasury, thieves[i]);
            vm.prank(admin, admin); // admin is tx.origin — but msg.sender is phishing contract
            try p.claimRewards() {} catch {}
        }

        assertEq(address(treasury).balance, balanceBefore,
                 "mitigation: repeated phishing must not change balance");
    }

    // ── Fuzz: any non-owner caller is always rejected ─────────────────────────

    function testFuzz_mitigation_onlyOwnerCanWithdraw(address caller, uint96 amount) public {
        vm.assume(caller != admin && caller != address(0));
        amount = uint96(bound(amount, 1, TREASURY_BALANCE));

        vm.prank(caller, caller);
        vm.expectRevert();
        treasury.withdraw(payable(caller), amount);
    }
}
