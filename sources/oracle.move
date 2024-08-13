module interstellar_dapp::oracle {

    use aptos_framework::signer::Signer;

    enum PriceSource {
        FixedPrice { price: u64 },
        ExternalModule { module_address: address },
    }

    struct PriceInfo has key, store {
        source: PriceSource,
    }

    struct PriceMap has key, store {
        prices: table::Table<address, PriceInfo>,
    }

    public fun initialize(account: &signer) {
        let price_map = PriceMap {
            prices: table::Table::new(),
        };
        move_to(account, price_map);
    }

    public fun set_price_source(account: &signer, token_address: address, source: PriceSource) {
        let price_map = borrow_global_mut<PriceMap>(signer::address_of(account));
        let price_info = PriceInfo { source };
        table::add(&mut price_map.prices, token_address, price_info);
    }

    public fun get_price(token_address: address): u64 acquires PriceInfo {
        let price_map = borrow_global<PriceMap>(@0x1);
        let price_info = table::borrow(&price_map.prices, token_address);

        match &price_info.source {
            PriceSource::FixedPrice { price } => *price,
            PriceSource::ExternalModule { module_address } => {
                let price_module = borrow_global<OracleModule>(module_address);
                price_module.get_price(token_address)
            }
        }
    }
}