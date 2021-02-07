pragma solidity ^0.6.7;

import "./interface/IFlashLenderReceiver.sol";
import "./interface/IFlashMinterReceiver.sol";
import { GemAbstract } from "dss-interfaces/ERC/GemAbstract.sol";


interface IPoker {
    function poke(address token, uint256 price0CumulativeLast, uint256 price1CumulativeLast, uint112 _daiReserve, uint112 _tokenReserve, uint112 _daiBalance, uint112 _tokenBalance) external;
}

library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

contract DssAra {
    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; emit Rely(usr); }
    function deny(address usr) external auth { wards[usr] = 0; emit Deny(usr); }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- Lock ---
    uint private unlocked = 1;
    modifier lock() {require(unlocked == 1, 'DssAraFlashLender/re-entrance');unlocked = 0;_;unlocked = 1;}

    // --- Data ---
    address public dai;
    address public token;

    uint112 private daiReserve;           // uses single storage slot, accessible via getReserves
    uint112 private tokenReserve;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint32  private blockLastPeriodCheck; // uses to call poker

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // daiReserve * tokenReserve, as of immediately after the most recent liquidity event

    uint32  public fees;
    uint32  public flashFees;
    uint32  public period;
    IPoker  public poker;

    // --- Event ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);
    event Deposit(address indexed sender, uint amount0, uint amount1);
    event Withdraw(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(address indexed sender, uint amount0In, uint amount1In, uint amount0Out,uint amount1Out, address indexed to);
    event Sync(uint112 daiReserve, uint112 tokenReserve);
    event Loan(address indexed receiver, uint256 amount, uint256 fee);
    event Mint(address indexed receiver, uint256 amount, uint256 fee);

    // --- Init ---
    constructor(address _dai, address _token) public {
        wards[msg.sender] = 1;
        dai = _dai;
        token = _token;

        emit Rely(msg.sender);
    }

    // --- Math ---
    uint256 constant FEES_PRECISION = 10 ** 6;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }

    // --- Administration ---
    function file(bytes32 what, uint32 data) external auth {
        if (what == "fees"){
            require(fees < FEES_PRECISION, "DssAra/more-100-percent");
            fees = uint32(data);
        }
        else if (what == "flash_fees"){
            require(fees < FEES_PRECISION, "DssAra/more-100-percent");
            flashFees = uint32(data);
        }
        else if (what == "period") period = uint32(data);
        else revert("DssAra/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "poker") poker = IPoker(data);
        else revert("DssAra/file-unrecognized-param");
        emit File(what, data);
    }

    // --- Primary Functions ---

    // --- Restricted Functions ---
    function deposit() external lock auth returns (uint256 amount0, uint256 amount1) {
        (uint112 _daiReserve, uint112 _tokenReserve,) = getReserves();
        uint256 daiBalance   = GemAbstract(dai).balanceOf(address(this));
        uint256 tokenBalance = GemAbstract(token).balanceOf(address(this));
        amount0 = sub(daiBalance, _daiReserve);
        amount1 = sub(tokenBalance, _tokenReserve);

        _update(daiBalance, tokenBalance, _daiReserve, _tokenReserve);
        emit Deposit(msg.sender, amount0, amount1);
    }


    function withdraw(uint256 amount0Out, uint256 amount1Out, address to) external lock auth {
        (uint112 _daiReserve, uint112 _tokenReserve,) = getReserves();
        address _dai   = dai;
        address _token = token;

        GemAbstract(_dai).transfer(to, amount0Out);
        GemAbstract(_token).transfer(to, amount1Out);

        uint256 daiBalance   = GemAbstract(_dai).balanceOf(address(this));
        uint256 tokenBalance = GemAbstract(_token).balanceOf(address(this));

        _update(daiBalance, tokenBalance, _daiReserve, _tokenReserve);
        emit Withdraw(msg.sender, amount0Out, amount1Out, to);
    }

    // --- Private Functions ---
    function _update(uint256 daiBalance, uint256 tokenBalance, uint112 _daiReserve, uint112 _tokenReserve) private {
        require(daiBalance <= uint112(-1) && tokenBalance <= uint112(-1), 'DssAra/overflow');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _daiReserve != 0 && _tokenReserve != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.uqdiv(UQ112x112.encode(_tokenReserve), _daiReserve)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.uqdiv(UQ112x112.encode(_daiReserve), _tokenReserve)) * timeElapsed;
        }

        uint32 timePeriod = blockTimestamp - blockLastPeriodCheck;
        if (period <= timePeriod && address(poker) != address(0)) {
            address _token = token;

            poker.poke(_token, price0CumulativeLast, price1CumulativeLast, _daiReserve, _tokenReserve, uint112(daiBalance), uint112(tokenBalance));

            daiBalance   = GemAbstract(dai).balanceOf(address(this));
            tokenBalance = GemAbstract(_token).balanceOf(address(this));
            require(daiBalance <= uint112(-1) && tokenBalance <= uint112(-1), 'DssAra/overflow');

            blockLastPeriodCheck = blockTimestamp;
        }

        daiReserve   = uint112(daiBalance);
        tokenReserve = uint112(tokenBalance);
        blockTimestampLast = blockTimestamp;
        emit Sync(daiReserve, tokenReserve);
    }

    // --- Main Functions ---
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'DssAra/insufficient-output-amount');
        (uint112 _daiReserve, uint112 _tokenReserve,) = getReserves();
        require(amount0Out < _daiReserve && amount1Out < _tokenReserve, 'DssAra/insufficient-liquidity');

        uint256 daiBalance;
        uint256 tokenBalance;
        { // scope for _token{0,1}, avoids stack too deep errors
            address _dai   = dai;
            address _token = token;
            require(to != _dai && to != _token, 'DssAra/invalid-to');

            if (amount0Out > 0) GemAbstract(_dai).transfer(to, amount0Out);
            if (amount1Out > 0) GemAbstract(_token).transfer(to, amount1Out);

            daiBalance   = GemAbstract(_dai).balanceOf(address(this));
            tokenBalance = GemAbstract(_token).balanceOf(address(this));
        }
        uint256 amount0In = daiBalance > _daiReserve - amount0Out ? daiBalance - (_daiReserve - amount0Out) : 0;
        uint256 amount1In = tokenBalance > _tokenReserve - amount1Out ? tokenBalance - (_tokenReserve - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'DssAra/insufficient-input-amount');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 daiBalanceAdjusted   = sub(mul(daiBalance, FEES_PRECISION), mul(amount0In, fees));
            uint256 tokenBalanceAdjusted = sub(mul(tokenBalance, FEES_PRECISION), mul(amount1In, fees));

            require(mul(daiBalanceAdjusted, tokenBalanceAdjusted) >= mul(mul(uint256(_daiReserve), _tokenReserve), FEES_PRECISION**2), 'DssAra/K-mismatch');
        }

        _update(daiBalance, tokenBalance, _daiReserve, _tokenReserve);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }


    // --- Flash Lender/Minter Functions---
    function flashLoan(address _receiver, uint256 _amount, bytes calldata _data) external lock {
        uint256 _fee = mul(_amount, flashFees) / FEES_PRECISION;
        address _token = token;
        uint256 _balanceTarget = add(GemAbstract(_token).balanceOf(address(this)), _fee);

        GemAbstract(_token).transfer(_receiver, _amount);

        IFlashLenderReceiver(_receiver).onFlashLoan(msg.sender, _amount, _fee, _data);
        uint256 tokenBalance = GemAbstract(_token).balanceOf(address(this));
        require(tokenBalance >= _balanceTarget, "DssAraFlashLender/token-unpaid-loan");

        (uint112 _daiReserve, uint112 _tokenReserve,) = getReserves();
        uint256 daiBalance = GemAbstract(dai).balanceOf(address(this));
        _update(daiBalance, tokenBalance, _daiReserve, _tokenReserve);

        emit Loan(_receiver, _amount, _fee);
    }

    function flashMint(address _receiver, uint256 _amount, bytes calldata _data) external lock {
        uint256 _fee = mul(_amount, flashFees) / FEES_PRECISION;
        address _dai = dai;
        uint256 _balanceTarget = add(GemAbstract(_dai).balanceOf(address(this)), _fee);

        GemAbstract(_dai).transfer(_receiver, _amount);

        IFlashMinterReceiver(_receiver).onFlashMint(msg.sender, _amount, _fee, _data);
        uint256 daiBalance = GemAbstract(_dai).balanceOf(address(this));
        require(daiBalance >= _balanceTarget, "DssAraFlashLender/dai-unpaid-loan");

        (uint112 _daiReserve, uint112 _tokenReserve,) = getReserves();
        uint256 tokenBalance = GemAbstract(token).balanceOf(address(this));
        _update(daiBalance, tokenBalance, _daiReserve, _tokenReserve);

        emit Mint(_receiver, _amount, _fee);
    }

    // --- View ---
    function getReserves() public view returns (uint112 _daiReserve, uint112 _tokenReserve, uint32 _blockTimestampLast) {
        _daiReserve = daiReserve;
        _tokenReserve = tokenReserve;
        _blockTimestampLast = blockTimestampLast;
    }

}
