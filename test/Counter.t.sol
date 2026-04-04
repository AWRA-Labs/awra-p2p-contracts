// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Counter} from "../src/Counter.sol";

contract CounterTest {
    Counter internal counter;

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialNumberIsZero() public view {
        assert(counter.number() == 0);
    }

    function test_Increment() public {
        counter.increment();

        assert(counter.number() == 1);
    }

    function test_SetNumber() public {
        counter.setNumber(42);

        assert(counter.number() == 42);
    }
}

