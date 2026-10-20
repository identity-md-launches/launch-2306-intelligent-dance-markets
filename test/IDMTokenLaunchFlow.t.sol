// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IDMToken} from "../src/IDMToken.sol";

/// @notice Stands in for the IdentityMD ProjectFactory: deploys the token with CREATE2 from its
/// creation code, as the launch does, so the constructor's `msg.sender` is this contract.
contract FactoryStub {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "constructor failed");
    }

    function move(IDMToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice The launch's flows, as the floor checks them: the whole supply minted to the factory, the
/// swarm's 10% arriving whole and claimable whole, the 70% pool share and the 20% remainder moving
/// exactly, no supply growth from anyone afterwards, and no privileged hand on a holder's balance.
contract IDMTokenLaunchFlowTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 7_000;
    uint256 internal constant REMAINDER_BPS = 2_000;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL_MANAGER = address(0x9001);
    address internal constant REMAINDER_TO = 0xff3E8d9bA776662Ca6Ed1420EE366AFB436d2684;
    address internal constant CLAIMANT = address(0xC1A1);
    address internal constant HOLDER = address(0x401D);
    address internal constant OTHER = address(0x07E5);
    address internal constant ATTACKER = address(0xBEEF);

    FactoryStub internal factory;
    IDMToken internal token;

    function setUp() public {
        factory = new FactoryStub();
        bytes32 salt = bytes32(uint256(1));
        bytes memory code = type(IDMToken).creationCode;
        address predicted = vm.computeCreate2Address(salt, keccak256(code), address(factory));
        token = IDMToken(factory.deploy(code, salt));
        assertEq(address(token), predicted, "CREATE2 address is predictable from the creation code");
    }

    function test_creationCodeTakesNoConstructorArguments() public {
        // The manifest gives constructorArgs: [] for this token. The bare creation code deploys.
        bytes memory code = type(IDMToken).creationCode;
        address deployed = factory.deploy(code, bytes32(uint256(2)));
        assertGt(deployed.code.length, 0);
        assertLe(deployed.code.length, 24_576, "runtime exceeds EIP-170");
        assertEq(IDMToken(deployed).balanceOf(address(factory)), SUPPLY);
    }

    function test_mintsTheWholeSupplyToTheFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.decimals(), 18);
    }

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "the swarm's share arrived short");

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm, "a claim arrived short");
        assertEq(token.balanceOf(DISTRIBUTOR), 0, "the distributor kept something back");
        assertEq(token.totalSupply(), SUPPLY, "the launch flows changed the supply");
    }

    function test_launchSplitMovesExactlyAndSumsToTheSupply() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = (SUPPLY * REMAINDER_BPS) / 10_000;
        assertEq(swarm + pool + remainder, SUPPLY, "10 + 70 + 20 is the whole supply");

        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertTrue(factory.move(token, POOL_MANAGER, pool));
        assertTrue(factory.move(token, REMAINDER_TO, remainder));

        assertEq(token.balanceOf(DISTRIBUTOR), 100_000_000 ether);
        assertEq(token.balanceOf(POOL_MANAGER), 700_000_000 ether);
        assertEq(token.balanceOf(REMAINDER_TO), 200_000_000 ether);
        assertEq(token.balanceOf(address(factory)), 0, "the factory paid everything out");
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_poolManagerCanPayOutAndTakeBackExactly() public {
        // A trader buys from and sells into the PoolManager; both legs move exactly what they say.
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        factory.move(token, POOL_MANAGER, pool);

        address trader = makeAddr("trader");
        uint256 bought = 12_345 ether;
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);

        vm.prank(trader);
        assertTrue(token.transfer(POOL_MANAGER, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
    }

    function test_noCommonAdminCallIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);
            vm.prank(ATTACKER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(factory));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(ATTACKER), 0, signatures[i]);
        }
    }

    function test_noPrivilegedHandMovesOrFreezesAHolder() public {
        factory.move(token, HOLDER, SUPPLY / 1_000);
        uint256 held = token.balanceOf(HOLDER);
        assertGt(held, 0);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], HOLDER, true);
            vm.prank(address(factory));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }

        // The factory, the most plausibly trusted address, cannot pull without an allowance.
        vm.prank(address(factory));
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, HOLDER, factory, 1));
        assertFalse(moved, "the deployer pulled from a holder without an allowance");
        assertEq(token.balanceOf(HOLDER), held, "a privileged call moved the holder's balance");

        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, held / 2), "the holder can no longer transfer");
        assertEq(token.balanceOf(OTHER), held / 2);
        assertEq(token.balanceOf(HOLDER), held - held / 2);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "the token has no runtime code");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F); // skip PUSH immediates
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    function testFuzz_anyHolderMovesExactlyWhatItSends(uint256 amount, uint256 sent) public {
        amount = bound(amount, 1, SUPPLY);
        sent = bound(sent, 0, amount);
        factory.move(token, HOLDER, amount);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, sent));
        assertEq(token.balanceOf(OTHER), sent);
        assertEq(token.balanceOf(HOLDER), amount - sent);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
