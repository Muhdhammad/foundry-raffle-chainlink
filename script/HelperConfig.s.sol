// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /* Vrf Mock value */
    uint96 public mock_base_fee = 0.25 ether;
    uint96 public mock_gas_price = 1e9;
    // LINK/ETH price
    int256 public mock_wei_per_unit_link = 4e15;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainID();

    struct NetworkConfig {
        uint256 interval;
        uint256 entranceFee;
        address vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig public localconfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        // if vrfCoordinator is not empty
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        }
        // if it is empty then
        else if (chainId == LOCAL_CHAIN_ID) {
            return getorCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainID();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            interval: 30, // 30 secs
            entranceFee: 0.01 ether, // 1e16
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            subscriptionId: 11154462420731842817929174819225298936855424793215074254617401709622891118122,
            callbackGasLimit: 500000,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            account: 0x428176e2CfB7c829928871b91ff7d9E43e1d4d75 // our acc key
        });
    }

    function getorCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // check to see if we set an active network config
        if (localconfig.vrfCoordinator != address(0)) {
            return localconfig;
        }

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMocks =
            new VRFCoordinatorV2_5Mock(mock_base_fee, mock_gas_price, mock_wei_per_unit_link);
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localconfig = NetworkConfig({
            interval: 30, // 30 secs
            entranceFee: 0.01 ether, // 1e16
            vrfCoordinator: address(vrfCoordinatorMocks),
            // does'nt matter
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            subscriptionId: 0,
            callbackGasLimit: 500000,
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // foundry default sender from 'Base.sol'
        });
        return localconfig;
    }
}
