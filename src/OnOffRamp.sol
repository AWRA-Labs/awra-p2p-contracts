// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract OnOffRamp is ReentrancyGuard, Ownable {
    struct Deposit {
        address user;
        address token;
        uint256 amount;
        bool processed;
    }

    uint256 public depositId;
    mapping(uint256 => Deposit) public deposits;

    event Deposited(
        uint256 indexed id,
        address indexed user,
        address token,
        uint256 amount
    );

    event OffRampRequested(
        uint256 indexed id,
        address indexed user,
        address token,
        uint256 amount
    );

    event OffRampProcessed(uint256 indexed id, address indexed user);

    constructor() Ownable(msg.sender) {}

    // 🔹 Deposit ERC20 tokens
    function deposit(address token, uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        deposits[depositId] = Deposit({
            user: msg.sender,
            token: token,
            amount: amount,
            processed: false
        });

        emit Deposited(depositId, msg.sender, token, amount);

        depositId++;
    }

    // 🔹 User requests off-ramp
    function requestOffRamp(uint256 id) external {
        Deposit storage dep = deposits[id];

        require(dep.user == msg.sender, "Not your deposit");
        require(!dep.processed, "Already processed");

        emit OffRampRequested(id, msg.sender, dep.token, dep.amount);
    }

    // 🔹 Backend/admin confirms off-ramp
    function processOffRamp(uint256 id) external onlyOwner {
        Deposit storage dep = deposits[id];

        require(!dep.processed, "Already processed");

        dep.processed = true;

        emit OffRampProcessed(id, dep.user);
    }
}
