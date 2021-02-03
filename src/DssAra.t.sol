pragma solidity ^0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";
import {Dai}    from "dss/dai.sol";

import "./mock/Poker.mock.sol";
import "./mock/FlashMintReceiver.mock.sol";
import "./mock/FlashLoanReceiver.mock.sol";
import "./testhelper/AmountHelper.sol";

import {DssAra} from "./DssAra.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract User is DSTest {
    DssAra public ara;
    DSToken public mkrToken;
    Dai public dai;

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

    Dai dai;
    DSToken mkrToken;

    PokerMock poker;
    FlashMintReceiverMock flashMintReceiver;
    FlashLoanReceiverMock flashLoanReceiver;

    DssAra ara;

    AmountHelper amountHelper;

    User gov;
    User user1;
    User user2;
    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        dai = new Dai(0);

        mkrToken = new DSToken("MKR");
        mkrToken.mint(10000 ether);

        ara = new DssAra(address(dai) , address(mkrToken));

        poker = new PokerMock(address(dai));
        mkrToken.transfer(address(poker), 1000 ether);
        dai.mint(address(poker), 1000 ether);

        flashMintReceiver = new FlashMintReceiverMock(address(dai));
        dai.mint(address(flashMintReceiver), 1000 ether);

        flashLoanReceiver = new FlashLoanReceiverMock(address(mkrToken));
        mkrToken.transfer(address(flashLoanReceiver), 1000 ether);

        gov = new User(dai, mkrToken, ara);
        mkrToken.transfer(address(gov), 7000 ether);
        dai.mint(address(gov), 400000 ether);

        user1 = new User(dai, mkrToken, ara);
        mkrToken.transfer(address(user1), 100 ether);
        dai.mint(address(user1), 5000 ether);

        user2 = new User(dai, mkrToken, ara);

        amountHelper = new AmountHelper(1000, 10**6);

        ara.rely(address(gov));
        ara.file("fees", 1000);
        ara.file("flash_fees", 100);
        ara.file("period", 10 minutes);
        ara.deny(me);

    }

    // --- Sanity test ---
    function testFail_rely_non_auth() public {
        ara.rely(address(user1));
    }

    function testFail_deny_non_auth() public {
        ara.deny(address(user1));
    }

    function testFail_file_non_auth() public {
        ara.file("fees", 10000);
    }

    function testFail_file_address_non_auth() public {
        ara.file("poker", address(poker));
    }

    function testFail_deposit_non_auth() public {
        user1.doDeposit(100 ether, 100 ether);
    }

    function testFail_withdraw_non_auth() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));
        ara.withdraw(100, 100, me);
    }

    // --- file setting test ---

    function testFail_fees_over_100_percent() public {
        ara.file("fees", uint32(100001));
    }

    function test_fees_change_setting() public {
        assertEq(uint(ara.fees()), 1000);
        gov.doRely(address(me));
        ara.file("fees", uint32(10000));
        assertEq(uint(ara.fees()), 10000);
    }

    function testFail_flash_fees_over_100_percent() public {
        ara.file("flash_fees", uint32(100001));
    }

    function test_flash_fees_change_setting() public {
        assertEq(uint(ara.flashFees()), 100);
        gov.doRely(address(me));
        ara.file("flash_fees", uint32(10000));
        assertEq(uint(ara.flashFees()), 10000);
    }

    function test_fees_add_pocker() public {
        gov.doRely(address(me));
        ara.file("poker", address(poker));
    }


    // --- deposit test ---
    function test_deposit() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(_reserve0, uint256(200000 ether));
        assertEq(_reserve1, uint256(4000 ether));

    }

    function test_deposit_twice() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(_reserve0, uint256(200000 ether));
        assertEq(_reserve1, uint256(4000 ether));

        gov.doDeposit(uint256(200000 ether), uint256(3000 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(_reserve0, uint256(400000 ether));
        assertEq(_reserve1, uint256(7000 ether));
    }

    // --- withdraw test ---
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

    function test_withdraw_twice() public {
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

        gov.doWithdraw(uint256(100000 ether), uint256(2000 ether), user2);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        assertEq(_reserve0, uint256(0 ether));
        assertEq(_reserve1, uint256(0 ether));

        assertEq(dai.balanceOf(address(user2)), uint256(200000 ether));
        assertEq(mkrToken.balanceOf(address(user2)), uint256(4000 ether));
    }


    // --- swap test ---
    function test_swap_in() public {
        uint112 _reserve0;
        uint112 _reserve1;
        uint32 _blockTimestampLast;

        gov.doDeposit(uint256(100000 ether), uint256(200 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        // 500 dai for 1
        assertEq(uint256(_reserve0), uint256(100000 ether));
        assertEq(uint256(_reserve1), uint256(200 ether));

        // sell 2 so get 1000 minus slipage =
        uint amountIn = amountHelper.getAmountIn(2 ether, 100000 ether, 200 ether);
        user1.swap(uint256(0 ether), uint256(2 ether), amountIn, 0, user1);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        assertEq(_reserve0, uint256(100000 ether) + amountIn);
        assertEq(_reserve1, uint256(200 ether) - uint256(2 ether));

        uint256 feesAndSlippage = 1 ether + 10.112122223233334345 ether; // ~ 1% 100000/1000
        assertEq(dai.balanceOf(address(user1)), uint256(4000 ether) - feesAndSlippage);
        assertEq(mkrToken.balanceOf(address(user1)), uint256(102 ether));
    }

    function test_swap_out() public {
        uint112 _reserve0;
        uint112 _reserve1;
        uint32 _blockTimestampLast;

        gov.doDeposit(uint256(100000 ether), uint256(200 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        // 500 dai for 1
        assertEq(uint256(_reserve0), uint256(100000 ether));
        assertEq(uint256(_reserve1), uint256(200 ether));

        // sell 1000 dai so get 2 minus slipage =
        uint amountIn = amountHelper.getAmountIn(1000 ether, 200 ether, 100000 ether);
        user1.swap( uint256(1000 ether), uint256(0 ether), 0, amountIn, user1);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();
        assertEq(_reserve0, uint256(100000 ether) - uint256(1000 ether) );
        assertEq(_reserve1, uint256(200 ether) + amountIn);

        uint256 feesAndSlippage = 0.002 ether + 0.020224244446466669 ether; // ~ 1% 200/2
        assertEq(dai.balanceOf(address(user1)), uint256(5000 ether + 1000 ether));
        assertEq(mkrToken.balanceOf(address(user1)), uint256(100 ether - 2 ether) - feesAndSlippage);
    }

    function test_swap_in_out() public {
        uint112 _reserve0;
        uint112 _reserve1;
        uint32 _blockTimestampLast;

        gov.doDeposit(uint256(100000 ether), uint256(200 ether));

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        // 500 dai for 1
        assertEq(uint256(_reserve0), uint256(100000 ether));
        assertEq(uint256(_reserve1), uint256(200 ether));

        // sell 1000 dai so get 2 minus slipage =
        uint amountIn = amountHelper.getAmountIn(2 ether, 100000 ether, 200 ether);
        user1.swap(uint256(0 ether), uint256(2 ether), amountIn, 0, user1);

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        amountIn = amountHelper.getAmountIn(_reserve0 - uint256(100000 ether) - 1 ether , _reserve1, _reserve0);
        user1.swap( _reserve0 - uint256(100000 ether) - 1 ether , uint256(0 ether), 0, amountIn, user1);

        assertEq(dai.balanceOf(address(user1)), uint256(5000 ether - 1000 ether / 1000 )); // - fees paid
        assertEq(mkrToken.balanceOf(address(user1)), uint256(100 ether  - 2 ether / 1000 - 0.000004005987970153 ether)); // - fees paid
    }


    // --- update test ---

    function test_update_call_poke() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        gov.doRely(address(me));
        ara.file("poker", address(poker));

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        hevm.warp(11 minutes);
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        assertTrue(poker.pokeHasBeenCalled());

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(_reserve0, uint256(200000 ether));
        assertEq(_reserve1, uint256(4000 ether));

    }

    function test_update_call_poke_recalc_balance() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        gov.doRely(address(me));
        ara.file("poker", address(poker));

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        poker.setAmount(100 ether);

        hevm.warp(11 minutes);
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        assertTrue(poker.pokeHasBeenCalled());

        (_reserve0, _reserve1, _blockTimestampLast) = ara.getReserves();

        assertEq(_reserve0, uint256(200100 ether));
        assertEq(_reserve1, uint256(4100 ether));

    }

    function test_update_poker_not_set() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        gov.doRely(address(me));

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        hevm.warp(11 minutes);
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        assertTrue(!poker.pokeHasBeenCalled());
    }

    function test_update_period_skip() public {
        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        gov.doRely(address(me));
        ara.file("poker", address(poker));
        ara.file("period", 10 minutes);

        assertEq(uint256(_reserve0), uint256(0 ether));
        assertEq(uint256(_reserve1), uint256(0 ether));

        hevm.warp(11 minutes);
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        assertTrue(poker.pokeHasBeenCalled());
        poker.reset();

        hevm.warp(20 minutes);
        gov.doDeposit(uint256(200 ether), uint256(40 ether));

        assertTrue(!poker.pokeHasBeenCalled());

        hevm.warp(21 minutes + 1 seconds);
        gov.doDeposit(uint256(200 ether), uint256(40 ether));

        assertTrue(poker.pokeHasBeenCalled());
    }

    // --- Flash mint test ---

    function test_flashMint_pay_fees() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(200000 ether + 20 ether);
        ara.flashMint(address(flashMintReceiver), 200000 ether, new bytes(0));

        assertEq(flashMintReceiver.fee(), 20 ether);
        assertEq(flashMintReceiver.amount(), 200000 ether);

        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        assertEq(uint256(_reserve0), uint256(200020 ether));
        assertEq(uint256(_reserve1), uint256(4000 ether));

    }

    function testFail_flashMint_fail_payment() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(200000 ether + 19 ether);
        ara.flashMint(address(flashMintReceiver), 200000 ether, new bytes(0));

        assertEq(flashMintReceiver.fee(), 20 ether);
        assertEq(flashMintReceiver.amount(), 200000 ether);

    }

    function testFail_flashMint_zero_payment() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(0 ether);
        ara.flashMint(address(flashMintReceiver), 200000 ether, new bytes(0));
    }

    function testFail_flashMint_more_than_reserve() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(0 ether);
        ara.flashMint(address(flashMintReceiver), 210000 ether, new bytes(0));
    }

    // --- Flash loan test ---

    function test_flashLoan_pay_fees() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashLoanReceiver.setAmountToPay(2000 ether + 0.2 ether);
        ara.flashLoan(address(flashLoanReceiver), 2000 ether, new bytes(0));

        assertEq(flashLoanReceiver.fee(), 0.2 ether);
        assertEq(flashLoanReceiver.amount(), 2000 ether);

        (uint112 _reserve0,uint112 _reserve1,uint32 _blockTimestampLast) = ara.getReserves();
        assertEq(uint256(_reserve0), uint256(200000 ether));
        assertEq(uint256(_reserve1), uint256(4000.2 ether));

    }

    function testFail_flashLoan_fail_payment() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(2000 ether + 0.19 ether);
        ara.flashMint(address(flashMintReceiver), 2000 ether, new bytes(0));

    }

    function testFail_flashLoan_zero_payment() public {
        gov.doDeposit(uint256(200000 ether), uint256(4000 ether));

        flashMintReceiver.setAmountToPay(0 ether);
        ara.flashMint(address(flashMintReceiver), 200000 ether, new bytes(0));
    }

}

