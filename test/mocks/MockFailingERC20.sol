//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockFailingERC20 is ERC20 {
    constructor() ERC20("Failing", "FAIL") {}

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false;
    }

    function burn(uint256) public pure {}
}
