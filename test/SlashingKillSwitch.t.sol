// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../src/AvsOperatorManager.sol";
import "./TestSetup.sol";

/// @notice Target with a no-op fallback so forwarded calls succeed when the kill switch lets them through.
contract Acceptor {
    fallback() external payable {}
    receive() external payable {}
}

contract SlashingKillSwitchTest is TestSetup {

    // Simple AVS-specific selector: legacyRegister(address avs, uint256 something) — AVS at offset 0.
    bytes4 constant LEGACY_REGISTER = bytes4(keccak256("legacyRegister(address,uint256)"));

    address constant AVS_A = address(uint160(0xA11CE));
    address constant AVS_B = address(uint160(0xB0B));

    Acceptor acceptor;
    address pauserOnly;
    address randomUser;

    function setUp() public override {
        super.setUp();

        acceptor = new Acceptor();
        pauserOnly = vm.addr(0xCAFE);
        randomUser = vm.addr(0xBEEF);

        // pauserOnly holds OPERATING_MULTISIG but not the admin role.
        vm.prank(admin);
        roleRegistry.grantRole(roleRegistry.OPERATING_MULTISIG(), pauserOnly);
    }

    function _seedSelectorAndAllow(uint256 operatorId, address target, bytes4 selector, uint16 offset) internal {
        vm.startPrank(admin);
        avsOperatorManager.addSlashingRegistrationSelector(selector, offset);
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, target, selector, true);
        vm.stopPrank();
    }

    function test_unwatchedSelector_passesThrough() public {
        uint256 operatorId = 1;
        bytes4 unwatched = bytes4(keccak256("doSomething(address,uint256)"));
        bytes memory args = abi.encode(AVS_A, uint256(123));

        vm.prank(admin);
        avsOperatorManager.updateAllowedOperatorCalls(operatorId, address(acceptor), unwatched, true);

        // global flag ON — irrelevant for unwatched selectors
        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistration();

        // Per-AVS block ON for AVS_A — also irrelevant for unwatched selectors
        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);

        vm.prank(admin);
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), unwatched, args);

        vm.prank(operatorOneRunner);
        avsOperatorManager.forwardOperatorCall(operatorId, address(acceptor), unwatched, args);
    }

    function test_globalFlag_blocksWatchedSelector_onAdminPath() public {
        uint256 operatorId = 1;
        _seedSelectorAndAllow(operatorId, address(acceptor), LEGACY_REGISTER, 0);

        bytes memory args = abi.encode(AVS_A, uint256(1));

        // Before kill switch: call goes through.
        vm.prank(admin);
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), LEGACY_REGISTER, args);

        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistration();

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.SlashingDisabledRegistrationBlocked.selector);
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), LEGACY_REGISTER, args);
    }

    function test_globalFlag_blocksWatchedSelector_onOperatorPath() public {
        uint256 operatorId = 1;
        _seedSelectorAndAllow(operatorId, address(acceptor), LEGACY_REGISTER, 0);

        bytes memory args = abi.encode(AVS_A, uint256(1));

        vm.prank(operatorOneRunner);
        avsOperatorManager.forwardOperatorCall(operatorId, address(acceptor), LEGACY_REGISTER, args);

        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistration();

        vm.prank(operatorOneRunner);
        vm.expectRevert(AvsOperatorManager.SlashingDisabledRegistrationBlocked.selector);
        avsOperatorManager.forwardOperatorCall(operatorId, address(acceptor), LEGACY_REGISTER, args);
    }

    function test_perAvsBlock_independentOfGlobalFlag() public {
        uint256 operatorId = 1;
        _seedSelectorAndAllow(operatorId, address(acceptor), LEGACY_REGISTER, 0);

        // Block AVS_A only. Global flag remains OFF.
        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);

        // Call to blocked AVS reverts.
        bytes memory argsBlocked = abi.encode(AVS_A, uint256(1));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AvsOperatorManager.SlashingDisabledForAvs.selector, AVS_A));
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), LEGACY_REGISTER, argsBlocked);

        // Call to a different AVS still works.
        bytes memory argsOk = abi.encode(AVS_B, uint256(1));
        vm.prank(admin);
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), LEGACY_REGISTER, argsOk);
    }

    function test_calldataTooShort_reverts() public {
        uint256 operatorId = 1;
        _seedSelectorAndAllow(operatorId, address(acceptor), LEGACY_REGISTER, 0);

        // Not enough bytes to decode an address word.
        bytes memory args = hex"deadbeef";

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.SlashingCalldataTooShort.selector);
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), LEGACY_REGISTER, args);
    }

    function test_disableSlashingRegistration_isOneWay() public {
        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistration();

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.SlashingAlreadyDisabled.selector);
        avsOperatorManager.disableSlashingRegistration();

        assertTrue(avsOperatorManager.slashingRegistrationDisabled());
    }

    function test_perAvsBlock_isOneWay() public {
        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.AvsAlreadyDisabled.selector);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);

        assertTrue(avsOperatorManager.isSlashingRegistrationDisabledForAvs(AVS_A));
    }

    function test_addSelector_isOneWay() public {
        vm.prank(admin);
        avsOperatorManager.addSlashingRegistrationSelector(LEGACY_REGISTER, 0);

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.SelectorAlreadyWatched.selector);
        avsOperatorManager.addSlashingRegistrationSelector(LEGACY_REGISTER, 32);
    }

    function test_pauser_canDisable_butNotAddSelectorOrAvs() public {
        vm.prank(pauserOnly);
        avsOperatorManager.disableSlashingRegistration();
        assertTrue(avsOperatorManager.slashingRegistrationDisabled());

        vm.prank(pauserOnly);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.addSlashingRegistrationSelector(LEGACY_REGISTER, 0);

        vm.prank(pauserOnly);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);
    }

    function test_admin_cannotFlipGlobalFlag_withoutPauserRole() public {
        vm.prank(admin);
        roleRegistry.revokeRole(roleRegistry.OPERATING_MULTISIG(), admin);

        vm.prank(admin);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.disableSlashingRegistration();
    }

    function test_randomUser_cannotDoAnything() public {
        vm.prank(randomUser);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.disableSlashingRegistration();

        vm.prank(randomUser);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.addSlashingRegistrationSelector(LEGACY_REGISTER, 0);

        vm.prank(randomUser);
        vm.expectRevert(AvsOperatorManager.IncorrectRole.selector);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_A);
    }

    function test_constructor_rejectsZeroRoleRegistry() public {
        vm.expectRevert(AvsOperatorManager.InvalidAddress.selector);
        new AvsOperatorManager(address(0));
    }

    function test_roleRegistry_isImmutable() public view {
        assertEq(address(avsOperatorManager.roleRegistry()), address(roleRegistry));
    }

    function test_avsArgOffset_nonZero() public {
        uint256 operatorId = 1;

        // Selector with avs at offset 32 (second word): registerSomething(uint256, address)
        bytes4 selectorAtOffset32 = bytes4(keccak256("registerSomething(uint256,address)"));

        _seedSelectorAndAllow(operatorId, address(acceptor), selectorAtOffset32, 32);

        vm.prank(admin);
        avsOperatorManager.disableSlashingRegistrationForAvs(AVS_B);

        bytes memory args = abi.encode(uint256(7), AVS_B);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AvsOperatorManager.SlashingDisabledForAvs.selector, AVS_B));
        avsOperatorManager.adminForwardCall(operatorId, address(acceptor), selectorAtOffset32, args);
    }
}
