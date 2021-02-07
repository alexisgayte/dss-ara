pragma solidity 0.6.7;

import { GemAbstract } from "dss-interfaces/ERC/GemAbstract.sol";

contract PokerMock {

    bool public pokeHasBeenCalled = false;
    address token;
    address dai;
    uint256 amount;

    uint256 price0CumulativeLast;
    uint256 price1CumulativeLast;
    uint112 daiReserve;
    uint112 tokenReserve;

    // constructor
    constructor(address dai_) public {
        dai = dai_;
    }

    function poke(address token_, uint256 price0CumulativeLast_, uint256 price1CumulativeLast_, uint112 daiReserve_, uint112 tokenReserve_, uint112 daiBalance_, uint112 tokenBalance_) external {
        pokeHasBeenCalled = true;
        token = token_;
        price0CumulativeLast = price0CumulativeLast_;
        price1CumulativeLast = price1CumulativeLast_;
        daiReserve = daiReserve_;
        tokenReserve = tokenReserve_;

        GemAbstract(token_).transfer(msg.sender, amount);
        GemAbstract(dai).transfer(msg.sender, amount);
    }

    function setAmount(uint256 amount_) external {
        amount = amount_;
    }

    function reset() external {
        pokeHasBeenCalled = false;
    }

}