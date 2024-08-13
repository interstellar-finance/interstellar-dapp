module interstellar_dapp::money_market {

    use aptos_framework::signer::Signer;
    use aptos_framework::timestamp::Timestamp;
    use interstellar_dapp::oracle;

    struct GlobalConfig has key, store {
        oracle_address: address,
    }

    struct MarketInfo has key, store {
        deposit_rate: u64,
        borrow_rate: u64,
        total_deposits: u64,
        total_debt: u64,
        last_time_updated: u64,
    }

    struct UserPosition has key, store {
        deposits: table::Table<address, u64>,
        borrows: table::Table<address, u64>,
    }

    struct MarketMap has key, store {
        markets: table::Table<address, MarketInfo>,
    }

    public fun initialize(account: &signer, oracle_address: address) {
        let config = GlobalConfig { oracle_address };
        move_to(account, config);

        let market_map = MarketMap {
            markets: table::Table::new(),
        };
        move_to(account, market_map);
    }

    public fun set_market(account: &signer, token_address: address, deposit_rate: u64, borrow_rate: u64) {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = MarketInfo {
            deposit_rate,
            borrow_rate,
            total_deposits: 0,
            total_debt: 0,
            last_time_updated: Timestamp::now_microseconds(),
        };
        table::add(&mut market_map.markets, token_address, market_info);
    }

    public fun deposit(account: &signer, token_address: address, amount: u64) {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = table::borrow_mut(&mut market_map.markets, token_address);

        market_info.total_deposits += amount;
        market_info.last_time_updated = Timestamp::now_microseconds();

        let user_position = borrow_global_mut<UserPosition>(signer::address_of(account));
        let user_deposit = table::borrow_mut(&mut user_position.deposits, token_address);
        *user_deposit += amount;
    }

    public fun borrow(account: &signer, token_address: address, amount: u64) {
        let market_map = borrow_global_mut<MarketMap>(signer::address_of(account));
        let market_info = table::borrow_mut(&mut market_map.markets, token_address);

        market_info.total_debt += amount;
        market_info.last_time_updated = Timestamp::now_microseconds();

        let user_position = borrow_global_mut<UserPosition>(signer::address_of(account));
        let user_borrow = table::borrow_mut(&mut user_position.borrows, token_address);
        *user_borrow += amount;
    }

    public fun get_token_price(account: &signer, token_address: address): u64 {
        let config = borrow_global<GlobalConfig>(signer::address_of(account));
        OracleModule::get_price(config.oracle_address, token_address)
    }
}