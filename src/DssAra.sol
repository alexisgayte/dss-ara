pragma solidity ^0.6.7;

interface TokenLike {
    function balanceOf(address account) external view returns (uint256);
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

contract DssAra {
    using SafeMath  for uint256;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private locked = 1;
    uint256 public fees;


    /* ========== VIEWS ========== */

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /* ========== EVENTS ========== */
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Deposit(address indexed sender, uint amount0, uint amount1);
    event Withdraw(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event File(bytes32 indexed what, uint256 data);

    /* ========== MODIFIER AUTH ========== */

    function rely(address guy) external auth { emit Rely(guy); wards[guy] = 1; }
    function deny(address guy) external auth { emit Deny(guy); wards[guy] = 0; }
    mapping (address => uint256) public wards;
    modifier auth {
        require(wards[msg.sender] == 1, "dss-ara/not-authorized");
        _;
    }

    /* ========== MODIFIER REENTRANT ========== */

    modifier nonReentrant {
        require(locked == 1, "dss-ara/reentrancy-guard");
        locked = 2;
        _;
        locked = 1;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function file(bytes32 what, uint256 data) external auth {
        // Update parameter
        if (what == "fees") fees = data;
        else revert("dss-ara/file-unrecognized-param");

        // Emit event
        emit File(what, data);
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _token0,
        address _token1
    ) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        token0 = _token0;
        token1 = _token1;
    }

    /* ========== PRIVATE METHODS ========== */

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'dss-ara/transfer-failed');
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'dss-ara/overflow');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.uqdiv(UQ112x112.encode(_reserve1), _reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.uqdiv(UQ112x112.encode(_reserve0), _reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // this low-level function should be called from a contract which performs important safety checks
    function deposit() external nonReentrant auth returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = TokenLike(token0).balanceOf(address(this));
        uint256 balance1 = TokenLike(token1).balanceOf(address(this));
        amount0 = balance0.sub(_reserve0);
        amount1 = balance1.sub(_reserve1);

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Deposit(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function withdraw(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant auth {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings

        _safeTransfer(_token0, to, amount0Out);
        _safeTransfer(_token1, to, amount1Out);

        uint256 balance0 = TokenLike(_token0).balanceOf(address(this));
        uint256 balance1 = TokenLike(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Withdraw(msg.sender, amount0Out, amount1Out, to);
    }

    /* ========== NON RESTRICTED FUNCTIONS ========== */

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        require(amount0Out > 0 || amount1Out > 0, 'dss-ara/insufficient-output-amount');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'dss-ara/insufficient-liquidity');

        uint256 balance0;
        uint256 balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'dss-ara/invalid-to');
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            balance0 = TokenLike(_token0).balanceOf(address(this));
            balance1 = TokenLike(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'dss-ara/insufficient-input-amount');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = balance0.mul(100000).sub(amount0In.mul(fees));
            uint256 balance1Adjusted = balance1.mul(100000).sub(amount1In.mul(fees));
            require(balance0Adjusted.mul(balance1Adjusted) >= uint256(_reserve0).mul(_reserve1).mul(1000**2), 'dss-ara/K-mismatch');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

}
