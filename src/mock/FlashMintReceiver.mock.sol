pragma solidity 0.6.7;

import { GemAbstract } from "dss-interfaces/ERC/GemAbstract.sol";

contract FlashMintReceiverMock {

    address dai;

    bool    public onFlashMintHasBeenCalled = false;
    uint256 public amount;
    uint256 public fee;
    bytes   public data;


    uint256 amountToPay;

    // constructor
    constructor(address dai_) public {
        dai = dai_;
    }

    function onFlashMint(address _sender, uint256 _amount, uint256 _fee, bytes calldata _data) external {
        // Just pay back the original amount
        onFlashMintHasBeenCalled = true;
        amount = _amount;
        fee = _fee;
        data = _data;
        GemAbstract(dai).transfer(msg.sender, amountToPay);

    }

    function setAmountToPay(uint256 amount_) external {
        amountToPay = amount_;
    }

    function reset() external {
        onFlashMintHasBeenCalled = false;
    }

}