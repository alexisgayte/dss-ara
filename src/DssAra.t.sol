pragma solidity ^0.6.7;

import "ds-math/math.sol";
import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";
import {Vat}              from "dss/vat.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai}              from "dss/dai.sol";
import "./DssAra.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract User is DSTest {
    using SafeMath  for uint256;
    DssAra public ara;
    DSToken public mkrToken;
    Dai public dai;

    //rounds to zero if x*y < RAY / 2
    uint constant WAD = 10 ** 18;
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    constructor(Dai _dai, DSToken _mkrToken, DssAra _ara) public {
        dai = _dai;
        mkrToken = _mkrToken;
        ara = _ara;
    }

    function doDeposit(uint256 amount0, uint256 amount1) public {
        dai.transfer(address(ara), amount0);
        mkrToken.transfer(address(ara), amount1);
        ara.deposit();
    }

    function doWithdraw(uint256 amount0, uint256 amount1, User user) public {
        ara.withdraw(amount0, amount1, address(user));
    }

    function doRely(address auth) public {
        ara.rely(auth);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In, User user) public {

        dai.transfer(address(ara), amount0In);
        mkrToken.transfer(address(ara), amount1In);

        ara.swap(amount0Out, amount1Out, address(user));
    }

}

contract DssArsTest is DSTest {
    Hevm hevm;

    address me;

    TestVat vat;
    DaiJoin daiJoin;
    Dai dai;
    DSToken mkrToken;

    /* ========== ARA ========== */
    DssAra ara;

    /* ========== USER ========== */
    User gov;
    User user1;
    User user2;

    /* ========== Set UP ========== */
    function setUp() public {
        me = address(this);

        vat = new TestVat();
        vat = vat;

        dai = new Dai(0);

        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        mkrToken = new DSToken("MKR");
        mkrToken.mint(10000 ether);

        ara = new DssAra(address(dai) , address(mkrToken));

        gov = new User(dai, mkrToken, ara);
        mkrToken.transfer(address(gov), 7000 ether);
        dai.mint(address(gov), 400000 ether);

        user1 = new User(dai, mkrToken, ara);
        mkrToken.transfer(address(user1), 100 ether);
        dai.mint(address(user1), 5000 ether);

        user2 = new User(dai, mkrToken, ara);

        ara.rely(address(gov));
        ara.file("fees", 100);
        ara.deny(me);

    }

    /* ========== SANITY TEST ========== */
    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }

    function testFail_auth_sanity() public {
        //gov.doRely(me);
        ara.rely(address(user1));
    }

    function testFail_file_sanity() public {
        //gov.doRely(me);
        ara.file("fees", 1000);
    }

    function testFail_deposit_sanity() public {
        ara.deposit();
    }

    function testFail_withdraw_sanity() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));
        //gov.doRely(me);
        ara.withdraw(100, 100, me);
    }


    /* ========== TEST ========== */

    function test_deposit() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        log_named_uint("bla", _reserve0);

        assertEq(_reserve0, uint256(200000 ether));
        assertEq(_reserve1, uint256(4000 ether));

    }

    function test_withdraw() public {
        uint112 _reserve0;
        uint112 _reserve1;
        uint32 _blockTimestampLast;

        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(uint256(_reserve0), uint256(200000 ether));
        assertEq(uint256(_reserve1), uint256(4000 ether));

        gov.doWithdraw(uint256(100000 ether), uint256(2000 ether), user2);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        assertEq(_reserve0, uint256(100000 ether));
        assertEq(_reserve1, uint256(2000 ether));

        assertEq(dai.balanceOf(address(user2)), uint256(100000 ether));
        assertEq(mkrToken.balanceOf(address(user2)), uint256(2000 ether));
    }
    function test_swap() public {
        uint112 _reserve0;
        uint112 _reserve1;
        uint32 _blockTimestampLast;

        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(uint256(_reserve0), uint256(200000 ether));
        assertEq(uint256(_reserve1), uint256(4000 ether));

        user1.swap(uint256(100 ether), uint256(0 ether), 0, 1.9 ether, user1);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        assertEq(_reserve0, uint256(199900 ether));
        assertEq(_reserve1, uint256(4001.9 ether));

        assertEq(dai.balanceOf(address(user1)), uint256(5100 ether));
        assertEq(mkrToken.balanceOf(address(user1)), uint256(98.1 ether));
    }

}

