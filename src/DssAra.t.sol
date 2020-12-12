pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssAra.sol";

contract DssAraTest is DSTest {
    DssAra ara;

    function setUp() public {
        ara = new DssAra();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
