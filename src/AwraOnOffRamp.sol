// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AwraOnOffRamp is Ownable, ReentrancyGuard {
    enum TxType {
        OFFRAMP, // user deposits crypto → gets fiat
        ONRAMP // user gets crypto → paid fiat off-chain
    }

    struct Transaction {
        address user;
        address token;
        uint256 amount;
        TxType txType;
        bool processed;
    }

    uint256 public txId;
    mapping(uint256 => Transaction) public transactions;

    event TransactionCreated(
        uint256 indexed id,
        address indexed user,
        address token,
        uint256 amount,
        TxType txType
    );

    event TransactionProcessed(
        uint256 indexed id,
        address indexed user,
        TxType txType
    );

    constructor() Ownable(msg.sender) {}

    // 🔹 USER: Only used for OFF-RAMP (deposit crypto)
    function createOffRamp(
        address token,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Invalid amount");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        transactions[txId] = Transaction({
            user: msg.sender,
            token: token,
            amount: amount,
            txType: TxType.OFFRAMP,
            processed: false
        });

        emit TransactionCreated(
            txId,
            msg.sender,
            token,
            amount,
            TxType.OFFRAMP
        );

        txId++;
    }

    // 🔹 ADMIN: handles BOTH on-ramp & off-ramp
    function processTransaction(
        uint256 id,
        address user,
        address token,
        uint256 amount,
        TxType txType
    ) external onlyOwner nonReentrant {
        if (txType == TxType.ONRAMP) {
            // send tokens to user
            require(
                IERC20(token).balanceOf(address(this)) >= amount,
                "Insufficient liquidity"
            );

            IERC20(token).transfer(user, amount);

            emit TransactionProcessed(id, user, TxType.ONRAMP);
        } else {
            // OFFRAMP confirmation
            Transaction storage txn = transactions[id];

            require(!txn.processed, "Already processed");
            require(txn.txType == TxType.OFFRAMP, "Wrong type");

            txn.processed = true;

            emit TransactionProcessed(id, txn.user, TxType.OFFRAMP);
        }
    }
}
