// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is CodeConstants, Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    uint256 interval;
    uint256 entranceFee;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address player = makeAddr("player");
    uint256 public constant PLAYER_STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        interval = config.interval;
        entranceFee = config.entranceFee;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(player, PLAYER_STARTING_BALANCE);
    }

    // test to check if raffle initialized as open
    function testRaffleInitializedOpen() public {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    // test to see if it reverts when player don't pay enough to enter
    function testRaffleInsufficientPayment() public {
        vm.prank(player);
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    // test to see if it actually stores the players in the array when they enter the raffle
    function testRaffleRecordsPlayers() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(player == playerRecorded);
    }

    function testEventWhenEnterRaffle() public {
        vm.prank(player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayerToEnterWhileRaffleIsCalculating() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();

        // time of block created + interval + 1 so that it shows that the time is completed
        // and now it's time to pick a winner and Raffle is now calculating
        vm.warp(block.timestamp + interval + 1); // Sets timestamp
        vm.roll(block.number + 1); // Sets block number
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__NotOpen.selector);
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        // This line asserts that upKeepNeeded should be false
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // Sets timestamp
        vm.roll(block.number + 1); // Sets block number
        raffle.performUpkeep("");

        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasPassed() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upKeepNeeded,) = raffle.checkUpkeep("");

        assert(upKeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpKeepIsTrue() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // A way to test if performUpKeep is working okay
        // If this fails, then the test fails
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpKeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        numPlayers = 1;
        currentBalance = currentBalance + entranceFee;

        // Act, Assert
        vm.expectRevert(
            // expect Revert for error with parameters
            abi.encodeWithSelector(Raffle.Raffle__upkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        // it is expected to revert because 'checkKeepup' should return false
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _; // Runs before test run
    }

    // Advanced test
    // What if we need to get data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        // Act
        vm.recordLogs();
        // Whatever events or logs are emitted by this performUpkeep function
        // keep track of those and put those in an array
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // entries[0] and topics[0] are from vrfCoordinator itself, so
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    // Stateless Fuzz Test
    function testfulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEntered
        skipFork
    {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testfulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        uint256 additionalParticipants = 3; // 4 in total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        // To enter 3 more players
        for (uint256 i = startingIndex; i < startingIndex + additionalParticipants; i++) {
            address newPlayer = address(uint160(i)); // way to convert number to address
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalParticipants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
