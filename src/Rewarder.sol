//SPDX-License-Identifier: MIT
pragma solidity =0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function withdraw(uint wad) external;
}

contract Rewarder {
    using SafeERC20 for IERC20;

    address private immutable owner;
    IERC20 private immutable rewardToken;
    mapping(address => uint256) public rewards;
    uint256 public totalRewards;

    constructor(address _owner, address _rewardToken) {
        require(_owner != address(0));
        owner = _owner;
        rewardToken = IERC20(_rewardToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Rewarder: unauthorized");
        _;
    }

    function batchReward(
        address[] calldata _recipients,
        uint256[] calldata _amounts
    ) external onlyOwner {
        uint256 length = _recipients.length;
        require(_amounts.length == length, "Rewarder: length mismatch");
        uint256 totalAmount;
        for (uint256 i = 0; i < length; i++) {
            totalAmount += _amounts[i];
            rewards[_recipients[i]] += _amounts[i];
        }
        totalRewards += totalAmount;
        rewardToken.safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    function claim() external {
        uint256 amount = rewards[msg.sender];
        require(amount > 0, "Rewarder: nothing to claim");
        rewards[msg.sender] = 0;
        totalRewards -= amount;
        rewardToken.safeTransfer(msg.sender, amount);
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);

        if (_token == address(rewardToken)) {
            uint256 balance = rewardToken.balanceOf(address(this));
            require(
                totalRewards <= balance,
                "Rewarder: insufficient reward balance"
            );
        }
    }
}
