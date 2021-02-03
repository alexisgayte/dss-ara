pragma solidity ^0.6.7;

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

contract AmountHelper {
    using SafeMath  for uint256;

    uint256 public fees;
    uint256 public feesDenominator;

    constructor(uint256 fees_, uint256 feesDenominator_) public {
        fees            = fees_;
        feesDenominator = feesDenominator_;
    }

    function setFees(uint256 fees_) external {
        fees = fees_;
    }

    function setFeesDenominator(uint256 feesDenominator_) external {
        feesDenominator = feesDenominator_;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external returns (uint amountOut) {
        require(amountIn > 0);
        require(reserveIn > 0 && reserveOut > 0);
        uint amountInWithFee = amountIn.mul(feesDenominator - fees);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(feesDenominator).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external returns (uint amountIn) {
        require(amountOut > 0);
        require(reserveIn > 0 && reserveOut > 0);
        uint numerator = reserveIn.mul(amountOut).mul(feesDenominator);
        uint denominator = reserveOut.sub(amountOut).mul(feesDenominator - fees);
        amountIn = (numerator / denominator).add(1);
    }


}