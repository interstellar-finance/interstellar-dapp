module interstellar_dapp::money_market {

    use aptos_framework::signer::Signer;
    use aptos_framework::timestamp::Timestamp;
    use aptos_framework::table;
    use interstellar_dapp::oracle;

    /// Structure holding the global configuration.
    struct GlobalConfig has key, store {
        oracle_address: address,
    }

    /// Structure holding the market data for a specific token.
    struct MarketInfo has key, store {
        deposit_rate: u64,
        borrow_rate: u64,
        ltv: u64,                     // Loan-to-Value (LTV) in basis points, e.g., 80% = 800
        liquidation_threshold: u64,   // Liquidation threshold in basis points, e.g., 85% = 850
        total_deposits: u64,
        total_debt: u64,
        last_time_updated: u64,
    }

    /// Structure holding the user's positions.
    struct UserPosition has key, store {
        deposits: table::Table<address, u64>,  // Map of token addresses to deposit amounts
        borrows: table::Table<address, u64>,   // Map of token addresses to borrowed amounts
    }

    /// Structure holding all the markets.
    struct MarketMap has key, store {
        markets: table::Table<address, MarketInfo>, // Map of token addresses to MarketInfo
    }

    /// Initialize the global configuration and the market map.
    public fun initialize(account: &signer, oracle_address: address) {
        let config = GlobalConfig { oracle_address };
        move_to(account, config);

        let market_map = MarketMap {
            markets: table::Table::new(),
        };
        move_to(account, market_map);
    }

    /// Function to add or update a market for a token.
    public fun set_market(
        account: &signer,
        token_address: address,
        deposit_rate: u64,
        borrow_rate: u64,
        ltv: u64,
        liquidation_threshold: u64
    ) {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = MarketInfo {
            deposit_rate,
            borrow_rate,
            ltv,
            liquidation_threshold,
            total_deposits: 0,
            total_debt: 0,
            last_time_updated: Timestamp::now_microseconds(),
        };
        table::add(&mut market_map.markets, token_address, market_info);
    }

    /// Function for users to deposit tokens.
    public fun deposit(account: &signer, token_address: address, amount: u64) {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = table::borrow_mut(&mut market_map.markets, token_address);

        // Update total_deposits and last_time_updated
        market_info.total_deposits += amount;
        market_info.last_time_updated = Timestamp::now_microseconds();

        let user_position = borrow_global_mut<UserPosition>(signer::address_of(account));
        let user_deposit = table::borrow_mut(&mut user_position.deposits, token_address);
        *user_deposit += amount;
    }

    /// Function for users to borrow tokens.
    public fun borrow(account: &signer, token_address: address, amount: u64) acquires UserPosition {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = table::borrow_mut(&mut market_map.markets, token_address);

        let user_address = signer::address_of(account);

        // Before borrowing, calculate the Health Factor (HF) using LTV
        let hf = calculate_health_factor(user_address);
        assert!(hf >= 1000, 0x1); // Ensure HF >= 1.0 (1000 in basis points)

        // Update total_debt and last_time_updated
        market_info.total_debt += amount;
        market_info.last_time_updated = Timestamp::now_microseconds();

        let user_position = borrow_global_mut<UserPosition>(user_address);
        let user_borrow = table::borrow_mut(&mut user_position.borrows, token_address);
        *user_borrow += amount;
    }

    /// Function to calculate the Health Factor (HF) using LTV.
    public fun calculate_health_factor(user_address: address): u64 acquires UserPosition {
        let user_position = borrow_global<UserPosition>(user_address);
        let market_map = borrow_global<MarketMap>(@0x1); // Assume MarketMap is stored at address 0x1
        let config = borrow_global<GlobalConfig>(@0x1); // Assume GlobalConfig is stored at address 0x1

        let mut total_collateral_value = 0u64;
        let mut total_debt_value = 0u64;

        // Calculate total collateral value and debt value
        let deposit_keys = table::keys(&user_position.deposits);
        for deposit_key in deposit_keys {
            let deposit_amount = table::borrow(&user_position.deposits, deposit_key);
            let market_info = table::borrow(&market_map.markets, deposit_key);
            let price = oracle::get_price(config.oracle_address, deposit_key);

            total_collateral_value += deposit_amount * price * market_info.ltv / 1000;
        }

        let borrow_keys = table::keys(&user_position.borrows);
        for borrow_key in borrow_keys {
            let borrow_amount = table::borrow(&user_position.borrows, borrow_key);
            let price = oracle::get_price(config.oracle_address, borrow_key);

            total_debt_value += borrow_amount * price;
        }

        // Calculate HF: HF = total_collateral_value / total_debt_value
        if total_debt_value == 0 {
            return u64::MAX; // If no debt, HF is maximum
        }
        total_collateral_value * 1000 / total_debt_value
    }

    /// Function to retrieve the user's position including deposits, debt, and Health Factor.
    public fun get_user_position(user_address: address): (u64, u64, u64) acquires UserPosition {
        let user_position = borrow_global<UserPosition>(user_address);
        let market_map = borrow_global<MarketMap>(@0x1); // Assume MarketMap is stored at address 0x1
        let config = borrow_global<GlobalConfig>(@0x1); // Assume GlobalConfig is stored at address 0x1

        let mut total_deposits_value = 0u64;
        let mut total_debt_value = 0u64;

        // Calculate total deposit value
        let deposit_keys = table::keys(&user_position.deposits);
        for deposit_key in deposit_keys {
            let deposit_amount = table::borrow(&user_position.deposits, deposit_key);
            let price = oracle::get_price(config.oracle_address, deposit_key);
            total_deposits_value += deposit_amount * price;
        }

        // Calculate total debt value
        let borrow_keys = table::keys(&user_position.borrows);
        for borrow_key in borrow_keys {
            let borrow_amount = table::borrow(&user_position.borrows, borrow_key);
            let price = oracle::get_price(config.oracle_address, borrow_key);
            total_debt_value += borrow_amount * price;
        }

        // Calculate Health Factor (HF)
        let hf = calculate_health_factor(user_address);

        (total_deposits_value, total_debt_value, hf)
    }
}