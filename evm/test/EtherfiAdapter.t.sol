// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "src/interfaces/ISwapAdapterTypes.sol";
import "src/libraries/FractionMath.sol";
import "src/etherfi/EtherfiAdapter.sol";

contract EtherfiAdapterTest is Test, ISwapAdapterTypes {
    EtherfiAdapter adapter;
    IWeEth weEth = IWeEth(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IeEth eEth;

    function setUp() public {
        uint256 forkBlock = 19218495;
        vm.createSelectFork(vm.rpcUrl("mainnet"), forkBlock);
        adapter = new EtherfiAdapter(address(weEth));
        eEth = weEth.eETH();

        vm.label(address(weEth), "WeETH");
        vm.label(address(eEth), "eETH");
    }

    receive() external payable {}

    function testPriceFuzzEtherfi(uint256 amount0, uint256 amount1) public {
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, IERC20(address(weEth)), IERC20(address(eEth)));
        vm.assume(amount0 < limits[0] && amount0 > 0);
        vm.assume(amount1 < limits[1] && amount1 > 0);
 
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
 
        Fraction[] memory prices = adapter.price(pair, IERC20(address(weEth)), IERC20(address(eEth)), amounts);
 
        for (uint256 i = 0; i < prices.length; i++) {
            assertGt(prices[i].numerator, 0);
            assertGt(prices[i].denominator, 0);
        }
    }

    function testSwapFuzzEtherfiEethWeEth(uint256 specifiedAmount, bool isBuy) public {
        OrderSide side = isBuy ? OrderSide.Buy : OrderSide.Sell;

        IERC20 eEth_ = IERC20(address(eEth));
        IERC20 weEth_ = IERC20(address(weEth));
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, eEth_, weEth_);

        if (side == OrderSide.Buy) {
            vm.assume(specifiedAmount < limits[1] && specifiedAmount > 100);

            /// @dev workaround for eETH "deal", as standard ERC20 does not work(balance is shares)
            deal(address(adapter), type(uint256).max);
            adapter.swap(pair, IERC20(address(0)), eEth_, OrderSide.Buy, limits[0]);

            eEth_.approve(address(adapter), type(uint256).max);
        } else {
            vm.assume(specifiedAmount < limits[0] && specifiedAmount > 100);

            /// @dev workaround for eETH "deal", as standard ERC20 does not work(balance is shares)
            deal(address(adapter), type(uint128).max);
            adapter.swap(pair, IERC20(address(0)), eEth_, OrderSide.Buy, specifiedAmount);

            eEth_.approve(address(adapter), specifiedAmount);
        }

        uint256 eEth_balance = eEth_.balanceOf(address(this));
        uint256 weEth_balance = weEth_.balanceOf(address(this));

        Trade memory trade =
            adapter.swap(pair, eEth_, weEth_, side, specifiedAmount);

        if (trade.calculatedAmount > 0) {
            if (side == OrderSide.Buy) {
                assertGe(
                    specifiedAmount,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
                /// @dev Transfer function contains rounding errors because of rewards in weETH contract, therefore we assume a +/-2 tolerance
                assertLe(
                    specifiedAmount - 2,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
                assertLe(
                    trade.calculatedAmount - 2,
                    eEth_balance - eEth_.balanceOf(address(this))
                );
            } else {
                assertGe(
                    specifiedAmount,
                    eEth_balance - eEth_.balanceOf(address(this))
                );
                /// @dev Transfer function contains rounding errors because of rewards in eETH contract, therefore we assume a +/-2 tolerance
                assertLe(
                    specifiedAmount - 2,
                    eEth_balance - eEth_.balanceOf(address(this))
                );
                assertEq(
                    trade.calculatedAmount,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
            }
        }
    }

    function testSwapFuzzEtherfiWeEthEeth(uint256 specifiedAmount, bool isBuy) public {
        OrderSide side = isBuy ? OrderSide.Buy : OrderSide.Sell;

        IERC20 eEth_ = IERC20(address(eEth));
        IERC20 weEth_ = IERC20(address(weEth));
        uint256 weEth_bal_before = weEth_.balanceOf(address(this));
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, weEth_, eEth_);

        if (side == OrderSide.Buy) {
            vm.assume(specifiedAmount < limits[1] && specifiedAmount > 100);

            /// @dev workaround for eETH "deal", as standard ERC20 does not work(balance is shares)
            deal(address(adapter), type(uint256).max);
            adapter.swap(pair, IERC20(address(0)), weEth_, OrderSide.Buy, limits[0]);

            weEth_.approve(address(adapter), type(uint256).max);
        } else {
            vm.assume(specifiedAmount < limits[0] && specifiedAmount > 100);

            /// @dev workaround for eETH "deal", as standard ERC20 does not work(balance is shares)
            deal(address(adapter), type(uint128).max);
            adapter.swap(pair, IERC20(address(0)), weEth_, OrderSide.Buy, specifiedAmount);

            weEth_.approve(address(adapter), specifiedAmount);
        }

        uint256 eEth_balance = eEth_.balanceOf(address(this));
        uint256 weEth_balance = weEth_.balanceOf(address(this));

        /// @dev as of rounding errors in Etherfi, specifiedAmount might lose small digits for small numbers
        /// therefore we use weEth_balance - weEth_bal_before as specifiedAmount
        uint256 realAmountWeEth_ = weEth_balance - weEth_bal_before;

        Trade memory trade =
            adapter.swap(pair, weEth_, eEth_, side, realAmountWeEth_);

        if (trade.calculatedAmount > 0) {
            if (side == OrderSide.Buy) {
                assertGe(
                    realAmountWeEth_,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
                /// @dev Transfer function contains rounding errors because of rewards in weETH contract, therefore we assume a +/-2 tolerance
                assertLe(
                    realAmountWeEth_ - 2,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
                assertLe(
                    trade.calculatedAmount - 2,
                    weEth_balance - weEth_.balanceOf(address(this))
                );
            } else {
                assertEq(
                    realAmountWeEth_,
                    weEth_balance - weEth_.balanceOf(address(this))
                );
                assertLe(
                    trade.calculatedAmount - 2,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
                assertGe(
                    trade.calculatedAmount,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
            }
        }
    }

    function testSwapFuzzEtherfiEthEeth(uint256 specifiedAmount, bool isBuy) public {
        OrderSide side = isBuy ? OrderSide.Buy : OrderSide.Sell;

        IERC20 eth_ = IERC20(address(0));
        IERC20 eEth_ = IERC20(address(eEth));
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, eth_, eEth_);

        if (side == OrderSide.Buy) {
            vm.assume(specifiedAmount < limits[1] && specifiedAmount > 10);

            deal(address(adapter), eEth_.totalSupply());
        } else {
            vm.assume(specifiedAmount < limits[0] && specifiedAmount > 10);

            deal(address(adapter), specifiedAmount);
        }

        uint256 eth_balance = address(adapter).balance;
        uint256 eEth_balance = eEth_.balanceOf(address(this));

        Trade memory trade =
            adapter.swap(pair, eth_, eEth_, side, specifiedAmount);

        if (trade.calculatedAmount > 0) {
            if (side == OrderSide.Buy) {
                assertGe(
                    specifiedAmount,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
                /// @dev Transfer function contains rounding errors because of rewards in eETH contract, therefore we assume a +/-2 tolerance
                assertLe(
                    specifiedAmount - 2,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
                assertEq(
                    trade.calculatedAmount,
                    eth_balance - address(adapter).balance
                );
            } else {
                assertEq(
                    specifiedAmount,
                    eth_balance - address(adapter).balance
                );
                assertEq(
                    trade.calculatedAmount,
                    eEth_.balanceOf(address(this)) - eEth_balance
                );
            }
        }
    }

    function testSwapFuzzEtherfiEthWeEth(uint256 specifiedAmount, bool isBuy) public {
        OrderSide side = isBuy ? OrderSide.Buy : OrderSide.Sell;

        IERC20 eth_ = IERC20(address(0));
        IERC20 weEth_ = IERC20(address(weEth));
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, eth_, weEth_);

        if (side == OrderSide.Buy) {
            vm.assume(specifiedAmount < limits[1] && specifiedAmount > 10);

            deal(address(adapter), weEth_.totalSupply());
        } else {
            vm.assume(specifiedAmount < limits[0] && specifiedAmount > 10);

            deal(address(adapter), specifiedAmount);
        }

        uint256 eth_balance = address(adapter).balance;
        uint256 weEth_balance = weEth_.balanceOf(address(this));

        Trade memory trade =
            adapter.swap(pair, eth_, weEth_, side, specifiedAmount);

        if (trade.calculatedAmount > 0) {
            if (side == OrderSide.Buy) {
                assertGe(
                    specifiedAmount,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
                /// @dev Transfer function contains rounding errors because of rewards in eETH contract, therefore we assume a +/-2 tolerance
                assertLe(
                    specifiedAmount - 2,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
                assertEq(
                    trade.calculatedAmount,
                    eth_balance - address(adapter).balance
                );
            } else {
                assertEq(
                    specifiedAmount,
                    eth_balance - address(adapter).balance
                );
                assertEq(
                    trade.calculatedAmount,
                    weEth_.balanceOf(address(this)) - weEth_balance
                );
            }
        }
    }

    function testSwapSellIncreasingEtherfi() public {
        executeIncreasingSwapsEtherfi(OrderSide.Sell);
    }

    function testSwapBuyIncreasingEtherfi() public {
        executeIncreasingSwapsEtherfi(OrderSide.Buy);
    }

    function executeIncreasingSwapsIntegral(OrderSide side) internal {
        bytes32 pair = bytes32(0);

        uint256 amountConstant_ = side == 10**18;
 
        uint256[] memory amounts = new uint256[](TEST_ITERATIONS);
        amounts[0] = amountConstant_;
        for (uint256 i = 1; i < TEST_ITERATIONS; i++) {
            amounts[i] = amountConstant_ * i;
        }
 
        Trade[] memory trades = new Trade[](TEST_ITERATIONS);
        uint256 beforeSwap;
        for (uint256 i = 1; i < TEST_ITERATIONS; i++) {
            beforeSwap = vm.snapshot();
 
            deal(address(USDC), address(this), amounts[i]);
            USDC.approve(address(adapter), amounts[i]);
 
            trades[i] = adapter.swap(pair, USDC, WETH, side, amounts[i]);
            vm.revertTo(beforeSwap);
        }
 
        for (uint256 i = 1; i < TEST_ITERATIONS - 1; i++) {
            assertLe(
                trades[i].calculatedAmount,
                trades[i + 1].calculatedAmount
            );
            assertLe(trades[i].gasUsed, trades[i + 1].gasUsed);
            assertEq(trades[i].price.compareFractions(trades[i + 1].price), 0);
        }
    }

    function testGetCapabilitiesEtherfi(
        bytes32 pair,
        address t0,
        address t1
    ) public {
        Capability[] memory res = adapter.getCapabilities(
            pair,
            IERC20(t0),
            IERC20(t1)
        );
 
        assertEq(res.length, 3);
    }
 
    function testGetTokensEtherfi() public {
        bytes32 pair = bytes32(0);
        IERC20[] memory tokens = adapter.getTokens(pair);
 
        assertEq(tokens.length, 3);
    }
 
    function testGetLimitsEtherfi() public {
        bytes32 pair = bytes32(0);
        uint256[] memory limits = adapter.getLimits(pair, IERC20(address(eEth)), IERC20(address(weEth)));
 
        assertEq(limits.length, 2);
    }
}
