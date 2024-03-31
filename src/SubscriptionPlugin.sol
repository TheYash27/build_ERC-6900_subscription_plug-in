// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {BasePlugin} from "erc6900/reference-implementation/plugins/BasePlugin.sol";
import {IPluginExecutor} from "erc6900/reference-implementation/interfaces/IPluginExecutor.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    PluginManifest,
    PluginMetadata,
    IPlugin
} from "erc6900/reference-implementation/interfaces/IPlugin.sol";

/// @title Counter Plugin
/// @author Alchemy
/// @notice This plugin lets increment a count!
contract SubscriptionPlugin is BasePlugin {
    // metadata used by the pluginMetadata() method down below
    string public constant NAME = "Subscription Plugin";
    string public constant VERSION = "1.0.0";
    string public constant AUTHOR = "Yash";

    // this is a constant used in the manifest, to reference our only dependency: the single owner plugin
    // since it is the first, and only, plugin the index 0 will reference the single owner plugin
    // we can use this to tell the modular account that we should use the single owner plugin to validate our user op
    // in other words, we'll say "make sure the person calling increment is an owner of the account using our single plugin"
    uint256 internal constant _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION = 0;

    mapping(address => mapping(address => SubscriptionData)) public subscriptions;

    struct SubscriptionData {
        uint256 amount,
        uint256 lastPaid,
        bool enabled
    };

    mapping(address => uint256) public count;

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Execution functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    function subscribe(address service, uint256 amount) external {
        subscriptions[service][msg.sender] = SubscriptionData(amount, 0, true);
    }

    function collect(address subscriber, uint256 amount) external {
        SubscriptionData storage subscription = subscriptions[msg.sender][subscriber];

        require(subscription.amount == amount, "Uh oh! Amount passed to this function is NOT equal to monthly subscription fee for the address of subscriber passed to this function!");
        require((block.timestamp - subscription.lastPaid) >= 4 weeks, "Uh oh! Subscription fee from the address of subscriber passed to this function has been withdrawn < 4 weeks ago!");
        require(subscription.enabled, "Address of subscriber passed to this function is NOT subscribed!");

        subscription.lastPaid = block.timestamp;

        IPluginExecutor(subscriber).executeFromPluginExternal(msg.sender, amount, "");
    }

    // ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    // ┃    Plugin interface functions    ┃
    // ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata) external pure override {}

    /// @inheritdoc BasePlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        // since we are using the modular account, we will specify one depedency
        // which will handle the user op validation for ownership
        // you can find this depedency specified in the installPlugin call in the tests
        manifest.dependencyInterfaceIds = new bytes4[](1);
        manifest.dependencyInterfaceIds[0] = type(IPlugin).interfaceId;

        // we only have one execution function that can be called, which is the increment function
        // here we define that increment function on the manifest as something that can be called during execution
        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.subscribe.selector;

        // you can think of ManifestFunction as a reference to a function somewhere,
        // we want to say "use this function" for some purpose - in this case,
        // we'll be using the user op validation function from the single owner dependency
        // and this is specified by the depdendency index
        ManifestFunction memory ownerUserOpValidationFunction = ManifestFunction({
            functionType: ManifestAssociatedFunctionType.DEPENDENCY,
            functionId: 0, // unused since it's a dependency
            dependencyIndex: _MANIFEST_DEPENDENCY_INDEX_OWNER_USER_OP_VALIDATION
        });

        // here we will link together the increment function with the single owner user op validation
        // this basically says "use this user op validation function and make sure everythings okay before calling increment"
        // this will ensure that only an owner of the account can call increment
        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.subscribe.selector,
            associatedFunction: ownerUserOpValidationFunction
        });

        // finally here we will always deny runtime calls to the increment function as we will only call it through user ops
        // this avoids a potential issue where a future plugin may define
        // a runtime validation function for it and unauthorized calls may occur due to that
        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](1);
        manifest.preRuntimeValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.increment.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.permitAnyExternalAddress = true;
        manifest.canSpendNativeToken = true;

        return manifest;
    }

    /// @inheritdoc BasePlugin
    function pluginMetadata() external pure virtual override returns (PluginMetadata memory) {
        PluginMetadata memory metadata;
        metadata.name = NAME;
        metadata.version = VERSION;
        metadata.author = AUTHOR;
        return metadata;
    }
}
