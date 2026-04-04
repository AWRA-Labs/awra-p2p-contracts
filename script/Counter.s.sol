// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Counter} from "../src/Counter.sol";

contract CounterScript {
    function run() external returns (Counter deployedCounter) {
        deployedCounter = new Counter();
    }
}
