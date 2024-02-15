// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IAladdin is IERC4626 {
    function aladdin() external view returns (address);
}
