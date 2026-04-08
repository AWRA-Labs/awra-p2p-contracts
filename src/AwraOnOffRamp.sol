// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AwraOnOffRamp is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    enum TxType {
        OFFRAMP,
        ONRAMP
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
    mapping(address => uint256) public lockedBalances;

    EnumerableSet.AddressSet private supportedTokens;

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

    event SupportedTokenAdded(address indexed token);
    event SupportedTokenRemoved(address indexed token);
    event TokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    constructor() Ownable(msg.sender) {}

    function addSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(supportedTokens.add(token), "Token already supported");

        emit SupportedTokenAdded(token);
    }

    function removeSupportedToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(supportedTokens.remove(token), "Token not supported");

        emit SupportedTokenRemoved(token);
    }

    function isSupportedToken(address token) public view returns (bool) {
        return supportedTokens.contains(token);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens.values();
    }

    function availableBalance(address token) public view returns (uint256) {
        if (token == address(0)) {
            return 0;
        }

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 locked = lockedBalances[token];

        if (balance <= locked) {
            return 0;
        }

        return balance - locked;
    }

    // User deposits crypto for an off-ramp request.
    function createOffRamp(
        address token,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(isSupportedToken(token), "Unsupported token");

        IERC20 erc20 = IERC20(token);
        uint256 balanceBefore = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        uint256 receivedAmount = erc20.balanceOf(address(this)) - balanceBefore;

        require(receivedAmount == amount, "Fee-on-transfer unsupported");

        uint256 currentId = txId;
        lockedBalances[token] += receivedAmount;

        transactions[currentId] = Transaction({
            user: msg.sender,
            token: token,
            amount: receivedAmount,
            txType: TxType.OFFRAMP,
            processed: false
        });

        emit TransactionCreated(
            currentId,
            msg.sender,
            token,
            receivedAmount,
            TxType.OFFRAMP
        );

        txId = currentId + 1;
    }

    // Owner finalizes off-ramp requests and fulfills on-ramp requests.
    function processTransaction(
        uint256 id,
        address user,
        address token,
        uint256 amount,
        TxType txType
    ) external onlyOwner nonReentrant {
        if (txType == TxType.ONRAMP) {
            _processOnRamp(user, token, amount);
            return;
        }

        _processOffRamp(id);
    }

    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(token != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(
            availableBalance(token) >= amount,
            "Insufficient available balance"
        );

        IERC20(token).safeTransfer(to, amount);

        emit TokenWithdrawn(token, to, amount);
    }

    function _processOnRamp(
        address user,
        address token,
        uint256 amount
    ) internal {
        require(amount > 0, "Invalid amount");
        require(user != address(0), "Invalid user");
        require(isSupportedToken(token), "Unsupported token");
        require(availableBalance(token) >= amount, "Insufficient liquidity");

        uint256 currentId = txId;
        transactions[currentId] = Transaction({
            user: user,
            token: token,
            amount: amount,
            txType: TxType.ONRAMP,
            processed: true
        });

        emit TransactionCreated(currentId, user, token, amount, TxType.ONRAMP);

        txId = currentId + 1;

        IERC20(token).safeTransfer(user, amount);

        emit TransactionProcessed(currentId, user, TxType.ONRAMP);
    }

    function _processOffRamp(uint256 id) internal {
        Transaction storage txn = transactions[id];

        require(txn.amount > 0, "Transaction not found");
        require(!txn.processed, "Already processed");
        require(txn.txType == TxType.OFFRAMP, "Wrong type");

        txn.processed = true;
        lockedBalances[txn.token] -= txn.amount;

        emit TransactionProcessed(id, txn.user, TxType.OFFRAMP);
    }
}
