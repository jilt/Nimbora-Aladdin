// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 1) convert WETH to CRV and back on uniswap v3
// 2) stake CRV for cvxCRV(aCRV) (18 decimals)

import {StrategyBase} from "../StrategyBase.sol";
import {ErrorLib} from "../../lib/ErrorLib.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IPoolingManager} from "../../interfaces/IPoolingManager.sol";
import {IAladdin} from "../../interfaces/IAladdin.sol";

// refund fallback

interface IUniSwapRouter is ISwapRouter {
    function refundETH() external payable;
}

contract UniswapV3Strategy is StrategyBase {


// 1

    IUniSwapRouter public immutable swapRouter;
    IQuoter public immutable quoter;

    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // Set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000;

    constructor() {
        swapRouter = IUniSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    }

        function initialize(
        address constant _poolingManager,
        address constant _underlyingToken = 0xD533a949740bb3306d119CC777fa900bA034cd52,
        address constant _yieldToken  = 0x2b95A1Dcc3D405535f9ed33c219ab38E8d7e0884
    ) public virtual initializer {
        initializeStrategyBase(_poolingManager, _underlyingToken, _yieldToken);
        _checkAndInitSavingCRV(_underlyingToken, _yieldToken);
    }

    // get quote for bridged WETH

    function getCRVforWETH(uint256 _WETHAmount)
        external
        payable
        returns (uint256)
    {
        return (
            quoter.quoteExactInputSingle.call({
                tokenIn: WETH,
                tokenOut: CRV,
                fee: 3000, // 0.3 percent fee
                amountIn: _WETHAmount,
                sqrtPriceLimitX96: 0
            })
        );
    }
    // Used to accept swapRouter refund
    receive() external payable {}

    // swap WETH

    function convertExactEthToCRV(uint256 _deadline)
        external
        payable
        returns (uint256)
    {
        require(msg.value > 0, "Error, ETH amount in must be greater than 0");
        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: CRV,
                fee: poolFee,
                recipient: msg.sender,
                deadline: _deadline,
                amountIn: msg.value,
                amountOutMinimum: getCRVforWETH(msg.value),
                sqrtPriceLimitX96: 0
            });

        return (swapRouter.exactInputSingle{value: msg.value}(_params));
    }

    // get quote for redeemed CRV

    function getWETHforCRV(uint256 _CRVAmount)
        external
        payable
        returns (uint256)
    {
        return (
            quoter.quoteExactInputSingle.call({
                tokenIn: CRV,
                tokenOut: WETH,
                fee: 3000, // 0.3 percent fee
                amountIn: _CRVAmount,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // swap CRV

    function convertExactCRVToEth(uint256 _deadline)
        external
        payable
        returns (uint256)
    {
        require(msg.value > 0, "Error, CRV amount in must be greater than 0");
        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: CRV,
                tokenOut: WETH,
                fee: poolFee,
                recipient: msg.sender,
                deadline: _deadline,
                amountIn: msg.value,
                amountOutMinimum: getETHforCRV(msg.value),
                sqrtPriceLimitX96: 0
            });

        return (swapRouter.exactInputSingle{value: msg.value}(_params));
    }


    // 2
    // underlying token CRV
    // yield token aCRV


    function _checkAndInitSavingCRV(address _underlyingToken, address _yieldToken) internal {
        address CRV = IAladdin(_yieldToken).aladdin();
        require(CRV == _underlyingToken, "Invalid underlying: AladdinDao Strategy");
        IERC20(_underlyingToken).approve(_yieldToken, type(uint256).max);
    }

    // changed deposit function based on the aCRV contract

    function _deposit(uint256 amount) internal override returns (uint256){
        IAladdin(yieldToken).depositWithCRV(address(this), amount);
        // amount of yield tokens received
        return (amount);
    }

    function _withdraw(uint256 amount) internal override returns (uint256) {
        uint256 yieldAmountToDeposit = IAladdin(yieldToken).previewWithdraw(amount);
        uint256 yieldBalance = yieldBalance();
        if (yieldAmountToDeposit > yieldBalance) {
            uint256 assets = IAladdin(yieldToken).redeem(yieldBalance, poolingManager, address(this));
            return (assets);
        } else {
            uint256 assets = IAladdin(yieldToken).withdraw(amount, poolingManager, address(this));
            return (amount);
        }
    }

     _underlyingToYield(uint256 amount) internal view override returns (uint256) {
        return IAladdin(yieldToken).previewDeposit(amount);
    }

    function _yieldToUnderlying(uint256 amount) internal view override returns (uint256) {
        return IAladdin(yieldToken).previewRedeem(amount);
    }

}
