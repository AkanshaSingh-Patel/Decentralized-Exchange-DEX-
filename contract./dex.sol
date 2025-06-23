// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DecentralizedExchange {
    struct Pool {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalSupply;
        mapping(address => uint256) liquidity;
    }
    
    mapping(bytes32 => Pool) public pools;
    mapping(address => mapping(address => uint256)) public userLiquidity;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 public constant FEE_NUMERATOR = 3; // 0.3% fee
    address public owner;
    uint256 public totalPools;
    
    event PoolCreated(address indexed tokenA, address indexed tokenB, bytes32 poolId);
    event LiquidityAdded(address indexed user, bytes32 poolId, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed user, bytes32 poolId, uint256 amountA, uint256 amountB);
    event TokensSwapped(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        totalPools = 0;
    }
    
    function createPool(address _tokenA, address _tokenB) external returns (bytes32) {
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid token addresses");
        
        // Ensure consistent ordering
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }
        
        bytes32 poolId = keccak256(abi.encodePacked(_tokenA, _tokenB));
        require(pools[poolId].tokenA == address(0), "Pool already exists");
        
        pools[poolId].tokenA = _tokenA;
        pools[poolId].tokenB = _tokenB;
        totalPools++;
        
        emit PoolCreated(_tokenA, _tokenB, poolId);
        return poolId;
    }
    
    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountA,
        uint256 _amountB
    ) external {
        // Ensure consistent ordering
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
            (_amountA, _amountB) = (_amountB, _amountA);
        }
        
        bytes32 poolId = keccak256(abi.encodePacked(_tokenA, _tokenB));
        Pool storage pool = pools[poolId];
        require(pool.tokenA != address(0), "Pool does not exist");
        
        // Transfer tokens from user
        require(IERC20(_tokenA).transferFrom(msg.sender, address(this), _amountA), "Transfer A failed");
        require(IERC20(_tokenB).transferFrom(msg.sender, address(this), _amountB), "Transfer B failed");
        
        uint256 liquidityMinted;
        if (pool.totalSupply == 0) {
            liquidityMinted = sqrt(_amountA * _amountB);
        } else {
            liquidityMinted = min(
                (_amountA * pool.totalSupply) / pool.reserveA,
                (_amountB * pool.totalSupply) / pool.reserveB
            );
        }
        
        pool.reserveA += _amountA;
        pool.reserveB += _amountB;
        pool.totalSupply += liquidityMinted;
        pool.liquidity[msg.sender] += liquidityMinted;
        userLiquidity[msg.sender][_tokenA] += _amountA;
        userLiquidity[msg.sender][_tokenB] += _amountB;
        
        emit LiquidityAdded(msg.sender, poolId, _amountA, _amountB);
    }
    
    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity
    ) external {
        // Ensure consistent ordering
        if (_tokenA > _tokenB) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }
        
        bytes32 poolId = keccak256(abi.encodePacked(_tokenA, _tokenB));
        Pool storage pool = pools[poolId];
        require(pool.liquidity[msg.sender] >= _liquidity, "Insufficient liquidity");
        
        uint256 amountA = (_liquidity * pool.reserveA) / pool.totalSupply;
        uint256 amountB = (_liquidity * pool.reserveB) / pool.totalSupply;
        
        pool.liquidity[msg.sender] -= _liquidity;
        pool.totalSupply -= _liquidity;
        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        
        require(IERC20(_tokenA).transfer(msg.sender, amountA), "Transfer A failed");
        require(IERC20(_tokenB).transfer(msg.sender, amountB), "Transfer B failed");
        
        emit LiquidityRemoved(msg.sender, poolId, amountA, amountB);
    }
    
    function swapTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minAmountOut
    ) external {
        require(_tokenIn != _tokenOut, "Tokens must be different");
        
        // Ensure consistent ordering for pool lookup
        address tokenA = _tokenIn < _tokenOut ? _tokenIn : _tokenOut;
        address tokenB = _tokenIn < _tokenOut ? _tokenOut : _tokenIn;
        
        bytes32 poolId = keccak256(abi.encodePacked(tokenA, tokenB));
        Pool storage pool = pools[poolId];
        require(pool.tokenA != address(0), "Pool does not exist");
        
        // Calculate output amount using AMM formula: x * y = k
        uint256 reserveIn = _tokenIn == tokenA ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = _tokenIn == tokenA ? pool.reserveB : pool.reserveA;
        
        uint256 amountInWithFee = _amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        uint256 amountOut = (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
        
        require(amountOut >= _minAmountOut, "Insufficient output amount");
        require(amountOut < reserveOut, "Insufficient liquidity");
        
        // Transfer tokens
        require(IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn), "Transfer in failed");
        require(IERC20(_tokenOut).transfer(msg.sender, amountOut), "Transfer out failed");
        
        // Update reserves
        if (_tokenIn == tokenA) {
            pool.reserveA += _amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += _amountIn;
            pool.reserveA -= amountOut;
        }
        
        emit TokensSwapped(msg.sender, _tokenIn, _tokenOut, _amountIn, amountOut);
    }
    
    function getAmountOut(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) external view returns (uint256) {
        address tokenA = _tokenIn < _tokenOut ? _tokenIn : _tokenOut;
        address tokenB = _tokenIn < _tokenOut ? _tokenOut : _tokenIn;
        
        bytes32 poolId = keccak256(abi.encodePacked(tokenA, tokenB));
        Pool storage pool = pools[poolId];
        
        uint256 reserveIn = _tokenIn == tokenA ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = _tokenIn == tokenA ? pool.reserveB : pool.reserveA;
        
        if (reserveIn == 0 || reserveOut == 0) return 0;
        
        uint256 amountInWithFee = _amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        return (amountInWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + amountInWithFee);
    }
    
    // Helper functions
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
