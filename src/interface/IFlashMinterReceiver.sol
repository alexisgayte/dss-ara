pragma solidity ^0.6.7;

interface IFlashMinterReceiver {

    /**
    * Must transfer _amount + _fee back to the flash mint contract when complete.
    */
    function onFlashMint(address _sender, uint256 _amount, uint256 _fee, bytes calldata _params) external;

}