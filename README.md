# 🥩 Staking Contracts

This repository contains two Ethereum smart contracts implemented using the Solidity language. These contracts offer functionality for staking ERC20 or ERC721 (NFTs) tokens and distributing rewards as ERC20 tokens. Both contracts supports adjustable staking periods and reward rates and has built-in protection mechanisms against common pitfalls.

## 📄 Contracts

- **ERC20Staking.sol** allows users to stake tokens of a specific ERC20 token and earn rewards in the form of another ERC20 token.

- **ERC721Staking.sol** allows user to stake non-fungible tokens (NFTs) conforming to ERC721 standards and earn rewards in the form of a ERC20 tokens.

## 🔑 Key Features

- **State Variables:** Both contain several state variables to keep track of various parameters like the NFT collection or ERC20 being staked (`nftCollection` / `stakingToken`), the token used as a reward (`rewardToken`), start and end of staking period, reward rate, and others. It also has a few mappings to track user-specific data like staked assets and rewards.

- **Constructor:** When deploying the contract, the owner needs to specify the addresses of the ERC721 collection / ERC20 token to stake and the ERC20 reward token.

- **Admin Functions:** The owner can modify parameters like the start and end times of the staking period (`setStartAt()` and `setEndAt()`), increase or decrease the reward allocation (`increaseRewardAllocation()` and `decreaseRewardAllocation()`), and recover any ERC20 tokens accidentally sent to the contract (`recoverERC20()`).

- **Staking and Withdrawal:** Users can stake their NFTs / ERC20 token in the contract using the stake function, which transfers the ownership of the NFTs / ERC20 token to the contract for the duration of the stake. Users can withdraw their NFTs / ERC20 token using the withdraw function. There's also a `exit()` function for withdrawing all staked NFTs / ERC20 tokens and claiming earned rewards.

- **Rewards:** Users earn rewards over time. They can check their earned rewards and claim them using the `earned()` and `claimReward()` functions.

- **Events:** Various events are emitted during the execution of the contract's functions. These events can be watched by external entities to track the contract's operations.

- **Modifiers:** There is a `updateReward()` modifier that is used to update rewards before executing any action.

- **View Functions:** These functions can be used to get information from the contract without making any changes. For example, to check the reward per token or to get the staking information for a user.

## :wrench: Development Tools

- **Solidity**: I've used Solidity version **0.8.17** to write the smart contracts in this repository.
- **Foundry**: a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.

## :rocket: Getting Started

1. Clone this repository. `git clone https://github.com/0xValerius/staking-contracts.git`
2. Compile the smart contracts. `forge build`
3. Run the test suite. `forge test`

## :scroll: License

[MIT](https://choosealicense.com/licenses/mit/)

## 🚨 Disclaimer

The Staking Contracts are provided "as is" and without warranties of any kind, whether express or implied. The user assumes all responsibility and risk for the use of this software.
