// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.0;

import '../../IReactive.sol';
import '../../ISubscriptionService.sol';

struct Reserves {
    uint112 reserve0;
    uint112 reserve1;
}

struct Tick {
    uint256 block_number;
    Reserves reserves;
}

contract UniswapHistoryDemoReactive is IReactive {
    event Sync(
        address indexed pair,
        uint256 indexed block_number,
        uint112 reserve0,
        uint112 reserve1
    );

    uint256 private constant REACTIVE_IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    uint256 private constant SEPOLIA_CHAIN_ID = 11155111;

    uint256 private constant UNISWAP_V2_SYNC_TOPIC_0 = 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1;
    uint256 private constant REQUEST_RESYNC_TOPIC_0 = 0xef3ee55037493e03bbb6926db7e59fe91b2af41184a35b32a106eac1557081ea;

    uint64 private constant CALLBACK_GAS_LIMIT = 1000000;

    /**
     * Indicates whether this is the contract instance deployed to ReactVM.
     */
    bool private vm;

    // State specific to reactive network contract instance

    address private owner;
    bool private paused;
    ISubscriptionService private service;

    // State specific to ReactVM contract instance

    address private l1;
    mapping(address => Tick[]) private reserves;

    constructor(
        address service_address,
        address _l1
    ) {
        owner = msg.sender;
        paused = false;
        l1 = _l1;
        service = ISubscriptionService(service_address);
        bytes memory payload = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256,uint256)",
            SEPOLIA_CHAIN_ID,
            0,
            UNISWAP_V2_SYNC_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool subscription_result,) = address(service).call(payload);
        if (!subscription_result) {
            vm = true;
        }
        bytes memory payload_2 = abi.encodeWithSignature(
            "subscribe(uint256,address,uint256,uint256,uint256,uint256)",
            SEPOLIA_CHAIN_ID,
            l1,
            REQUEST_RESYNC_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        (bool subscription_result_2,) = address(service).call(payload_2);
        if (!subscription_result_2) {
            vm = true;
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 'Unauthorized');
        _;
    }

    modifier rnOnly() {
        require(!vm, 'Reactive Network only');
        _;
    }

    modifier vmOnly() {
        // TODO: fix the assertion after testing.
        //require(vm, 'VM only');
        _;
    }

    // Methods specific to reactive network contract instance

    function pause() external rnOnly onlyOwner {
        require(!paused, 'Already paused');
        service.unsubscribe(
            SEPOLIA_CHAIN_ID,
            address(0),
            UNISWAP_V2_SYNC_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        paused = true;
    }

    function resume() external rnOnly onlyOwner {
        require(paused, 'Not paused');
        service.subscribe(
            SEPOLIA_CHAIN_ID,
            address(0),
            UNISWAP_V2_SYNC_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        paused = false;
    }

    // Methods specific to ReactVM contract instance

    function react(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 /* topic_3 */,
        bytes calldata data,
        uint256 block_number,
        uint256 /* op_code */
    ) external vmOnly {
        if (topic_0 == UNISWAP_V2_SYNC_TOPIC_0) {
            Reserves memory sync = abi.decode(data, ( Reserves ));
            Tick[] storage ticks = reserves[_contract];
            ticks.push(Tick({ block_number: block_number, reserves: sync }));
            emit Sync(_contract, block_number, sync.reserve0, sync.reserve1);
        } else {
            Tick[] storage ticks = reserves[address(uint160(topic_1))];
            uint112 reserve0 = 0;
            uint112 reserve1 = 0;
            for (uint ix = 0; ix != ticks.length; ++ix) {
                if (ticks[ix].block_number > topic_2) {
                    break;
                }
                reserve0 = ticks[ix].reserves.reserve0;
                reserve1 = ticks[ix].reserves.reserve1;
            }
            bytes memory payload = abi.encodeWithSignature(
                "resync(address,address,uint256,uint112,uint112)",
                address(0),
                address(uint160(topic_1)),
                topic_2,
                reserve0,
                reserve1
            );
            emit Callback(chain_id, l1, CALLBACK_GAS_LIMIT, payload);
        }
    }
}
